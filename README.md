# Groundcrew

> The ground crew that gets your agent off the ground.

One command takes a fresh machine to a wired, multi-agent AI coding environment —
the tools *and* the practices that keep newcomers out of trouble. Runs on
**macOS** and **Linux** (and Windows via WSL2).

The easiest way to use it: **point your AI coding agent at this repo** and say
"set me up." Your agent follows the [Agent Protocol](#for-your-coding-agent)
below — installing the core toolchain, then asking you which optional extras you
want. Prefer to drive it yourself? The manual quick start is right here.

---

# For humans

## Prerequisites

- **macOS**, a **Linux** box (Ubuntu 22.04 / 24.04), or **Windows 11 + WSL2**.
  - No WSL yet? In an **admin** PowerShell run `wsl --install`, reboot, open the
    new "Ubuntu" app, and finish its first-run setup.
  - On **macOS** you need [Homebrew](https://brew.sh) (`brew`). If it's missing,
    install it first — or let your agent do it.
- `sudo` rights (Linux) and an internet connection. Everything else is installed
  for you.

## Quick start

```bash
git clone https://github.com/jonathanavis96/groundcrew.git
cd groundcrew
bash install.sh --core-only    # core toolchain (macOS or Linux)
bash VERIFY.sh                 # confirm everything landed
```

Then open a new shell (or `source ~/.bashrc` / `~/.zshrc`) so the new tools are
on your PATH.

- **Preview first, change nothing:** `bash install.sh --core-only --dry-run`
- **Safe to re-run:** every step is guarded and skips work already done.

## What the core install gives you

| Group | Tools |
|---|---|
| Base | git, gh, jq, sqlite, ripgrep, fd, bat, fzf, tmux, shellcheck, wget (+ build tools) |
| Python | python3 + pipx + [uv](https://docs.astral.sh/uv/), ruff, pyright |
| Node | Node 20 via [nvm](https://github.com/nvm-sh/nvm) (never `sudo npm -g`) |
| Graph | [graphify](https://pypi.org/project/graphifyy/) — a code knowledge-graph (+ MCP server) |
| Shell | PATH wiring into `~/.bashrc` (and `~/.zshrc` on macOS) |

`VERIFY.sh` then checks each required tool is present and fails loudly if not.

## Optional modules

Add any of these after the core install with `bash install.sh --module <name>`:

| Module | What it is | Pro | Con |
|---|---|---|---|
| `vault` | A starter Obsidian notes vault | Persistent notes/memory your agent can use across sessions | It's a starter template; full use wants the Obsidian app + its Local REST API plugin |
| `playwright` | Headless browser + Chromium | Your agent can drive a real browser — scrape, test, screenshot | ~300 MB browser download |
| `docker` | Container runtime | Run containerised apps, databases, and tools in isolation | Heavy; on macOS it's Docker Desktop (GUI + licensing), on Linux needs a re-login to use without `sudo` |
| `media` | ffmpeg + rembg | Convert/transcode audio & video; one-command image background removal | rembg pulls a ~200 MB ML model on first use |

---

# For your coding agent

**You are an AI coding agent and your human pointed you at this repo to set up
their environment. Follow this protocol. Explain each step in plain language as
you go — your human may be new to all of this.**

1. **Check the OS.** Run `uname -s`. `Darwin` = macOS, `Linux` = Linux. On macOS,
   verify Homebrew: `command -v brew`; if absent, install it from https://brew.sh
   (or ask the user first). If you're on Windows without WSL, stop and tell the
   user to install WSL2 (`wsl --install`) and re-run you from inside Ubuntu.

2. **Get the repo** (if not already local):
   `git clone https://github.com/jonathanavis96/groundcrew.git && cd groundcrew`

3. **Install the core toolchain and verify:**
   ```bash
   bash install.sh --core-only
   bash VERIFY.sh
   ```
   Report the result. If `VERIFY` fails, show the user the failing line — don't
   paper over it. The install is idempotent, so it's safe to re-run.

4. **Offer the optional modules — one at a time.** For each module in the table
   under "Optional modules" above, tell the user its **What / Pro / Con** and ask
   whether they want it. Use your own interactive question UI (e.g. a yes/no per
   module); don't assume. Keep it short and honest — the Con matters.

5. **Install the picks.** For each module the user said yes to:
   `bash install.sh --module <name>` (one of: `vault`, `playwright`, `docker`,
   `media`). Report success/failure per module; a failure in one does not block
   the others.

6. **Re-verify and summarize.** Run `bash VERIFY.sh` again, then give the user a
   short summary: what's installed, anything that needs a new shell or re-login
   (Docker on Linux; PATH changes), and what they can do next.

**House rules while you work here:** this repo ships an agent-agnostic ruleset at
[`payload/AGENTS.md`](payload/AGENTS.md) — read it and follow it. In short: never
force-push or commit secrets, stay in scope, verify before claiming done, and ask
when a decision is genuinely the user's to make.

---

## Roadmap

- **Now** — macOS + Linux core toolchain, practices payload, agent-driven module
  picker (this).
- **Next** — more optional modules, the starter vault fleshed out, an interactive
  bash picker for people not using an agent.
- **Later** — a double-click Windows `.exe` that installs WSL2 and runs this, so a
  newcomer never touches a terminal.

## Design

The full design lives in [`docs/specs/`](docs/specs/).
