$ErrorActionPreference = "Stop"

$script:RepoRawBase = "https://raw.githubusercontent.com/M-Dragonborn/LazyWinT/main"
$script:ToolsUrl = "$script:RepoRawBase/tools.json"
$script:CacheDir = Join-Path $env:LOCALAPPDATA "LazyWinT"
$script:CacheToolsPath = Join-Path $script:CacheDir "tools.json"
$script:CacheMetaPath = Join-Path $script:CacheDir "tools.meta"
$script:WorkDir = Join-Path ([System.IO.Path]::GetTempPath()) ("LazyWinT-" + [guid]::NewGuid().ToString("N"))
$script:RunHistory = @()
$script:RunState = @{}
$script:CurrentProcess = $null
$script:CurrentToolName = $null
$script:ExitRequested = $false
$script:ToolCatalogSource = "Not loaded"

$script:FallbackTools = @"
{
  "categories": [
    {
      "name": "Windows Setup",
      "tools": [
        {
          "name": "massgrave",
          "description": "Microsoft Activation Scripts",
          "run_command": "irm https://get.activated.win | iex",
          "github_url": "https://github.com/massgravel/Microsoft-Activation-Scripts"
        },
        {
          "name": "Win11Debloat",
          "description": "Windows 11 debloating script",
          "run_command": "& ([scriptblock]::Create((irm 'https://raw.githubusercontent.com/Raphire/Win11Debloat/master/Get.ps1')))",
          "github_url": "https://github.com/Raphire/Win11Debloat"
        }
      ]
    }
  ]
}
"@

function Write-Title {
    Clear-Host
    Write-Host ""
    Write-Host "LazyWinT" -ForegroundColor Cyan
    Write-Host "Windows terminal tool launcher" -ForegroundColor DarkGray
    Write-Host "Tools: $script:ToolCatalogSource" -ForegroundColor DarkGray
    Write-Host ""
}

function Write-Notice {
    param(
        [string]$Message,
        [ConsoleColor]$Color = "Yellow"
    )
    Write-Host $Message -ForegroundColor $Color
}

function Read-Number {
    param(
        [string]$Prompt,
        [int]$Min,
        [int]$Max
    )

    while ($true) {
        $value = Read-Host $Prompt
        $number = 0
        if ([int]::TryParse($value, [ref]$number) -and $number -ge $Min -and $number -le $Max) {
            return $number
        }
        Write-Notice "Enter a number from $Min to $Max." "Red"
    }
}

function Read-YesNo {
    param([string]$Prompt)

    while ($true) {
        $value = (Read-Host "$Prompt (Y/N)").Trim().ToUpperInvariant()
        if ($value -eq "Y") { return $true }
        if ($value -eq "N") { return $false }
        Write-Notice "Enter Y or N." "Red"
    }
}

function Get-DesktopLogPath {
    $desktop = [Environment]::GetFolderPath("Desktop")
    if ([string]::IsNullOrWhiteSpace($desktop)) {
        $desktop = Join-Path $env:USERPROFILE "Desktop"
    }
    return Join-Path $desktop "lazywint.log"
}

function Get-ToolKey {
    param($Tool)
    return "$($Tool.name)|$($Tool.github_url)"
}

function Get-ToolColor {
    param($Tool)

    $key = Get-ToolKey $Tool
    if (-not $script:RunState.ContainsKey($key)) {
        return "DarkGray"
    }
    if ($script:RunState[$key] -eq "fail") {
        return "Red"
    }
    return "Green"
}

function Get-ToolPrefix {
    param($Tool)

    $key = Get-ToolKey $Tool
    if ($script:RunState.ContainsKey($key) -and $script:RunState[$key] -eq "success") {
        return ("[" + [char]0x2713 + "] ")
    }
    return "    "
}

function ConvertFrom-ToolsJson {
    param([string]$Json)

    $catalog = $Json | ConvertFrom-Json
    if ($null -eq $catalog.categories -or $catalog.categories.Count -eq 0) {
        throw "tools.json does not contain any categories."
    }

    foreach ($category in $catalog.categories) {
        if ([string]::IsNullOrWhiteSpace($category.name)) {
            throw "A category is missing a name."
        }
        if ($null -eq $category.tools) {
            throw "Category '$($category.name)' has no tools list."
        }
        foreach ($tool in $category.tools) {
            foreach ($field in @("name", "description", "run_command", "github_url")) {
                $property = $tool.PSObject.Properties[$field]
                if ($null -eq $property -or [string]::IsNullOrWhiteSpace([string]$property.Value)) {
                    throw "Tool in '$($category.name)' is missing '$field'."
                }
            }
        }
    }

    return $catalog
}

function Get-RemoteLastModified {
    try {
        $response = Invoke-WebRequest -Uri $script:ToolsUrl -Method Head -UseBasicParsing -TimeoutSec 10
        if ($response.Headers["Last-Modified"]) {
            return [datetime]::Parse($response.Headers["Last-Modified"]).ToUniversalTime()
        }
    }
    catch {
        return $null
    }
    return $null
}

function Get-CachedLastModified {
    if (-not (Test-Path $script:CacheMetaPath)) {
        return $null
    }

    try {
        $value = Get-Content -Path $script:CacheMetaPath -Raw
        if ([string]::IsNullOrWhiteSpace($value)) {
            return $null
        }
        return [datetime]::Parse($value).ToUniversalTime()
    }
    catch {
        return $null
    }
}

function Save-ToolsCache {
    param(
        [string]$Json,
        [AllowNull()]$LastModified
    )

    if (-not (Test-Path $script:CacheDir)) {
        New-Item -ItemType Directory -Path $script:CacheDir | Out-Null
    }

    Set-Content -Path $script:CacheToolsPath -Value $Json -Encoding UTF8
    if ($null -ne $LastModified) {
        Set-Content -Path $script:CacheMetaPath -Value $LastModified.ToString("o") -Encoding ASCII
    }
}

function Load-ToolCatalog {
    Write-Title
    Write-Host "Checking tool list..." -ForegroundColor DarkGray

    $remoteLastModified = Get-RemoteLastModified

    try {
        $freshToolsUrl = $script:ToolsUrl + "?t=" + [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
        $json = (Invoke-WebRequest -Uri $freshToolsUrl -UseBasicParsing -TimeoutSec 15).Content
        $catalog = ConvertFrom-ToolsJson $json
        Save-ToolsCache -Json $json -LastModified $remoteLastModified
        $script:ToolCatalogSource = "GitHub tools.json"
        return $catalog
    }
    catch {
        $script:ToolCatalogSource = "Built-in fallback"
        Write-Notice "Could not fetch GitHub tools.json. Using built-in fallback tools." "Yellow"
        Write-Notice $_.Exception.Message "DarkGray"
    }

    return ConvertFrom-ToolsJson $script:FallbackTools
}

function Show-RunSummary {
    $logPath = Get-DesktopLogPath
    $runCount = $script:RunHistory.Count
    $failedCount = ($script:RunHistory | Where-Object { $_.Status -eq "fail" }).Count

    try {
        $lines = foreach ($entry in $script:RunHistory) {
            "$($entry.Timestamp) | $($entry.ToolName) | $($entry.Status)"
        }
        New-Item -Path $logPath -ItemType File -Force | Out-Null
        if ($script:RunHistory.Count -gt 0) {
            Set-Content -Path $logPath -Value $lines -Encoding UTF8
        }
    }
    catch {
        Write-Notice "Could not write log file to Desktop: $($_.Exception.Message)" "Red"
    }

    Write-Host ""
    Write-Host "$runCount tools run, $failedCount failed, log saved to Desktop" -ForegroundColor Cyan
}

function Cleanup-LazyWinT {
    if (Test-Path $script:WorkDir) {
        try {
            Remove-Item -Path $script:WorkDir -Recurse -Force -ErrorAction Stop
        }
        catch {
            Write-Notice "Could not delete temporary files: $($_.Exception.Message)" "Yellow"
        }
    }
}

function Request-Exit {
    if ($script:CurrentProcess -and -not $script:CurrentProcess.HasExited) {
        Write-Host ""
        if (Read-YesNo "A tool is still running. Kill it before exiting?") {
            try {
                Stop-Process -Id $script:CurrentProcess.Id -Force -ErrorAction Stop
                Write-Notice "Stopped $script:CurrentToolName." "Yellow"
            }
            catch {
                Write-Notice "Could not stop $script:CurrentToolName: $($_.Exception.Message)" "Red"
            }
        }
        else {
            Write-Notice "Leaving $script:CurrentToolName running." "Yellow"
        }
    }

    $script:ExitRequested = $true
}

function Invoke-GitHubUrl {
    param($Tool)

    try {
        Start-Process $Tool.github_url
    }
    catch {
        Write-Notice "Could not open browser: $($_.Exception.Message)" "Red"
        Read-Host "Press Enter to continue" | Out-Null
    }
}

function Add-RunHistory {
    param(
        $Tool,
        [string]$Status
    )

    $script:RunHistory += [pscustomobject]@{
        Timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        ToolName = $Tool.name
        Status = $Status
    }
    $script:RunState[(Get-ToolKey $Tool)] = $Status
}

function Focus-LazyWinT {
    try {
        $shell = New-Object -ComObject WScript.Shell
        $shell.AppActivate($PID) | Out-Null
    }
    catch {
    }
}

function Wait-ForToolProcess {
    param($Tool, [System.Diagnostics.Process]$Process)

    $script:CurrentProcess = $Process
    $script:CurrentToolName = $Tool.name

    while (-not $Process.HasExited) {
        Write-Host "[running: $($Tool.name)] - press Enter to check status" -ForegroundColor Yellow

        $deadline = (Get-Date).AddSeconds(3)
        while ((Get-Date) -lt $deadline) {
            if ([Console]::KeyAvailable) {
                $key = [Console]::ReadKey($true)
                if ($key.Key -eq "Enter") {
                    break
                }
            }
            Start-Sleep -Milliseconds 150
        }

        try {
            $Process.Refresh()
        }
        catch {
            break
        }
    }

    $exitCode = $null
    try {
        $Process.Refresh()
        $exitCode = $Process.ExitCode
    }
    catch {
        $exitCode = 1
    }

    $script:CurrentProcess = $null
    $script:CurrentToolName = $null
    Focus-LazyWinT

    if ($exitCode -eq 0) {
        Add-RunHistory -Tool $Tool -Status "success"
        Write-Notice "$($Tool.name) finished successfully." "Green"
    }
    else {
        Add-RunHistory -Tool $Tool -Status "fail"
        Write-Notice "$($Tool.name) failed or was closed with exit code $exitCode." "Red"
    }

    Read-Host "Press Enter to return to the tool menu" | Out-Null
}

function Invoke-ToolRun {
    param($Tool)

    Write-Title
    Write-Host $Tool.name -ForegroundColor Cyan
    Write-Host $Tool.description -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "Command to run:" -ForegroundColor Yellow
    Write-Host $Tool.run_command -ForegroundColor White
    Write-Host ""

    if (-not (Read-YesNo "Run this tool now?")) {
        return
    }

    if (-not (Test-Path $script:WorkDir)) {
        New-Item -ItemType Directory -Path $script:WorkDir | Out-Null
    }

    $escapedWorkDir = $script:WorkDir.Replace("'", "''")
    $childScript = @'
Set-Location -LiteralPath '__WORKDIR__'
try {
    $ErrorActionPreference = 'Continue'
    $global:LASTEXITCODE = 0
    __COMMAND__
    if ($null -ne $global:LASTEXITCODE) { exit $global:LASTEXITCODE }
    exit 0
}
catch {
    Write-Host ""
    Write-Host ("LazyWinT command failed: " + $_.Exception.Message) -ForegroundColor Red
    exit 1
}
'@
    $childScript = $childScript.Replace("__WORKDIR__", $escapedWorkDir).Replace("__COMMAND__", $Tool.run_command)
    $encodedCommand = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($childScript))

    try {
        $process = Start-Process -FilePath "powershell.exe" -ArgumentList @(
            "-NoProfile",
            "-ExecutionPolicy", "Bypass",
            "-EncodedCommand", $encodedCommand
        ) -WorkingDirectory $script:WorkDir -PassThru
        Wait-ForToolProcess -Tool $Tool -Process $process
    }
    catch {
        Add-RunHistory -Tool $Tool -Status "fail"
        Write-Notice "Could not launch $($Tool.name): $($_.Exception.Message)" "Red"
        Read-Host "Press Enter to continue" | Out-Null
    }
}

function Show-ToolMenu {
    param($Tool)

    while (-not $script:ExitRequested) {
        Write-Title
        Write-Host $Tool.name -ForegroundColor Cyan
        Write-Host $Tool.description -ForegroundColor DarkGray
        Write-Host ""
        Write-Host "[1] Run"
        Write-Host "[2] View on GitHub"
        Write-Host "[3] Back"
        Write-Host ""

        $choice = Read-Number "Select an option" 1 3
        switch ($choice) {
            1 { Invoke-ToolRun $Tool }
            2 { Invoke-GitHubUrl $Tool }
            3 { return }
        }
    }
}

function Show-CategoryMenu {
    param($Category)

    while (-not $script:ExitRequested) {
        Write-Title
        Write-Host $Category.name -ForegroundColor Cyan
        Write-Host ""

        for ($i = 0; $i -lt $Category.tools.Count; $i++) {
            $tool = $Category.tools[$i]
            $number = $i + 1
            $prefix = Get-ToolPrefix $tool
            $color = Get-ToolColor $tool
            Write-Host ("[$number] $prefix$($tool.name) - $($tool.description)") -ForegroundColor $color
        }

        $backNumber = $Category.tools.Count + 1
        Write-Host "[$backNumber] Back"
        Write-Host ""

        $choice = Read-Number "Select a tool" 1 $backNumber
        if ($choice -eq $backNumber) {
            return
        }

        Show-ToolMenu $Category.tools[$choice - 1]
    }
}

function Show-MainMenu {
    param($Catalog)

    while (-not $script:ExitRequested) {
        Write-Title
        Write-Host "Categories" -ForegroundColor Cyan
        Write-Host ""

        for ($i = 0; $i -lt $Catalog.categories.Count; $i++) {
            $category = $Catalog.categories[$i]
            $number = $i + 1
            Write-Host "[$number] $($category.name)" -ForegroundColor Green
        }

        $exitNumber = $Catalog.categories.Count + 1
        Write-Host "[$exitNumber] Exit"
        Write-Host ""

        $choice = Read-Number "Select a category" 1 $exitNumber
        if ($choice -eq $exitNumber) {
            Request-Exit
            return
        }

        Show-CategoryMenu $Catalog.categories[$choice - 1]
    }
}

try {
    $catalog = Load-ToolCatalog
    Show-MainMenu $catalog
}
catch [System.Management.Automation.PipelineStoppedException] {
    Request-Exit
}
catch {
    Write-Notice "LazyWinT stopped after an error: $($_.Exception.Message)" "Red"
}
finally {
    Cleanup-LazyWinT
    Show-RunSummary
}
