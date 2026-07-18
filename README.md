# Groundcrew

> The ground crew that gets your agent off the ground.

One command takes a fresh Windows + WSL2 (or plain Ubuntu) machine to a wired,
multi-agent AI coding environment — the tools *and* the practices that keep
newcomers out of trouble.

## Status

**Phase 1 — core toolchain.** Early but real: the installer is idempotent,
self-verifying, and validated end-to-end by a container smoke test. The agents,
the practices payload, optional modules, and the double-click Windows installer
land in later phases (see [Roadmap](#roadmap)).

## Prerequisites

- **Windows 11 + WSL2 with Ubuntu**, or any Ubuntu 22.04 / 24.04 machine.
  No WSL yet? In an **admin** PowerShell run `wsl --install`, reboot, then open
  the new "Ubuntu" app and finish its first-run user setup.
- `sudo` rights and an internet connection. Everything else is installed for you.

## Quick start

Inside your Ubuntu / WSL2 shell:

```bash
git clone https://github.com/jonathanavis96/groundcrew.git
cd groundcrew
bash install.sh --core-only    # Phase 1 core toolchain
bash VERIFY.sh                 # confirm everything landed
```

Then open a new shell (or `source ~/.bashrc`) so the new tools are on your PATH.

- **Preview first, change nothing:** `bash install.sh --core-only --dry-run`
- **Safe to re-run:** every step is guarded and skips work already done.
- **No GitHub access?** Extract the tarball you were sent, `cd groundcrew`, and
  run the same `install.sh` / `VERIFY.sh` commands.

## What Phase 1 installs

| Group | Tools |
|---|---|
| Base | git, gh, curl, wget, jq, sqlite3, ripgrep, fd, bat, fzf, tmux, shellcheck, build-essential |
| Python | python3 + pipx + [uv](https://docs.astral.sh/uv/), ruff, pyright |
| Node | Node 20 via [nvm](https://github.com/nvm-sh/nvm) (never `sudo npm -g`) |
| Graph | [graphify](https://pypi.org/project/graphifyy/) — a code knowledge-graph |
| Shell | PATH wiring into `~/.bashrc` |

`VERIFY.sh` then checks each required tool is present and fails loudly if not.

## Options

```
install.sh [--core-only] [--preset minimal|recommended|everything] [--dry-run] [--help]
```

`--preset` selects agents and optional modules in Phase 2+; on the Phase 1 core
path it is accepted but has no effect.

## Roadmap

- **Phase 2** — agents + practices payload: Claude Code and opencode fully
  scripted, other agents onboarded via hand-to-agent prompts, plus guardrails
  and an agent-agnostic ruleset.
- **Phase 3** — optional modules (rembg, media, Playwright, Docker), a starter
  vault, and the interactive picker + competency gate.
- **Phase 4** — a double-click Windows `.exe` that installs WSL2 and then runs
  this, so a newcomer never touches a terminal to get started.

## Design

The full design lives in [`docs/specs/`](docs/specs/).
