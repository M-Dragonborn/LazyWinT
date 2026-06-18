# LazyWinT
LazyWinT — Your machine. Your rules. One menu.  Look, we both know the drill. Fresh Windows install. Now you spend the next 45 minutes playing treasure hunt across GitHub, Reddit, and some random blog from 2021 trying to find the right commands for massgrave, Raphire, sfc, DISM, and whatever else your setup needs. Every. Single. Time.  LazyWinT is the "fuck that" solution.  One terminal. One numbered list. You pick a number, it pulls the real script from the real repo and runs it. No middleman. No sketchy bundled installers. No reading through 47 pages of a README to find the one-liner. Just pick, run, done.  It doesn't modify anything. It doesn't host anything. It doesn't pretend to be smarter than the tools it launches. It's just the menu you wish existed the first time you set up Windows and realized you'd be copy-pasting commands until the heat death of the universe.  Built by someone who values their time enough to automate the boring part. If that's not you, close this and go enjoy your Google search.

LazyWinT is a terminal-only Windows tool launcher. One command to install, one menu to rule them all. Pick a number, run a tool, done.

---

## Install & Run

Open PowerShell and run:

```powershell
irm https://raw.githubusercontent.com/M-Dragonborn/LazyWinT/main/lazywint.ps1 | iex
```

That's it. No setup, no dependencies, no bullshit. Works on any modern Windows machine.

---

## How It Works

1. **Categories** — Tools are organized by category (e.g., Windows Setup)
2. **Pick a number** — Navigate the menu by typing numbers
3. **Run or view** — Launch the tool in a new window or open its GitHub repo
4. **Done** — When the tool finishes, you're back in the menu

### Controls

- **Numbers** — Navigate menus
- **Y / N** — Confirm or cancel actions
- **Enter** — Check status while a tool is running

### Color Coding

| Color | Meaning |
|---|---|
| Green | Tool ran successfully this session |
| Red | Tool failed last run |
| Dark Gray | Not yet run |

A checkmark appears next to tools you've already run.

---

## What It Does

- **Launches tools in a new window** — You interact with the actual tool directly. LazyWinT waits in the background.
- **Auto-detects when tools exit** — Returns to the menu automatically.
- **Keeps a log** — `lazywint.log` on your Desktop. One line per run: timestamp, tool name, success/fail.
- **Cleans up after itself** — Deletes all temp files on exit. Only the log stays behind.
- **Updates itself** — Checks for an updated tool list on every launch.

---

## Adding Tools

Edit `tools.json` in this repo. Add a tool to any category:

```json
{
  "name": "Tool Name",
  "description": "What it does",
  "run_command": "the command that runs it",
  "github_url": "https://github.com/user/repo"
}
```

Add a new category:

```json
{
  "name": "Category Name",
  "tools": []
}
```

No code changes needed. The menu updates automatically.

---

## Current Tools

### Windows Setup

| Tool | Description |
|---|---|
| massgrave | Microsoft Activation Scripts |
| Win11Debloat | Windows 11 debloating script |

---

## Exit Summary

When you quit, LazyWinT shows a quick summary:

```
3 tools run, 1 failed, log saved to Desktop
```

---

## FAQ

**Is this safe?**
LazyWinT doesn't modify anything itself. It runs the official command from each tool's official repo. You see the exact command before it runs.

**What if I have no internet?**
It uses a cached tool list from the last successful fetch. If it's never been run before, a built-in fallback list is used.

**Can I close it while a tool is running?**
Ctrl+C asks you whether to kill the running tool or leave it running.

**Where's the log?**
`lazywint.log` on your Desktop.

---

## Contributing

Found a tool that belongs here? Open a PR with the tool added to `tools.json`. Keep it to tools that are:
- Open source
- Actively maintained
- Useful for Windows setup/maintenance

---

## License

MIT. Use it, fork it, break it, fix it. Not my problem.
