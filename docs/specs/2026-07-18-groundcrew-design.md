# Groundcrew — Design Spec

- **Date:** 2026-07-18
- **Status:** Approved (brainstorm complete) — ready to turn into an implementation plan
- **Working name:** Groundcrew · primary domain `groundcrew.sh` (also secure `groundcrew.io`)

> Spec kept at `docs/specs/` (not `docs/superpowers/specs/`) so this repo stays free of
> workflow/tooling breadcrumbs — it is destined to become a public product repo, which must
> stay AI-tooling-free.

## 1. Summary

Groundcrew is a single, source-controlled, **idempotent installer** that takes a fresh
**Windows + WSL2** machine to a fully-wired AI coding-agent environment in as close to one
command as the platform allows. It replaces the ad-hoc pair of shell scripts previously
hand-assembled per-machine (e.g. on Luke's box), and is structured so a future website can
simply *serve* it.

It is **agent-agnostic**: it fully scripts the agents whose install is proven and deterministic
(Claude Code, opencode), and onboards any other agent (Codex, Gemini, …) via a per-agent
"hand this to your agent" prompt that the agent itself executes for its last-mile config. It ships
not just tools but the **practices** that keep newcomers out of trouble (guardrails + an
agent-agnostic ruleset + onboarding).

The tagline is literal: *the ground crew that gets your agent off the ground.*

## 2. Goals

- One reusable, versioned repo — not per-machine copies.
- **Idempotent** modules: any partial/failed run is safe to re-run. This is the key upgrade
  over the old hand-run scripts.
- Zero-baseline friendly: assume the user has **nothing** installed.
- Multi-agent: works for whatever coding agent the user runs, not just Claude Code.
- Ships **practices, not just tools** — the guardrails and ruleset that prevent the common
  newcomer failures, agent-agnostically.
- As few manual steps as the platform allows; the irreducible ones become copy-paste checklists.
- Self-verifying: a post-install check proves the environment actually works.

## 3. Non-goals (this round)

- Public marketing website / download portal (future — this repo is built to be *served* by it).
- Licensing, keys, or any paywall. Onboarding is **free and ungated**.
- macOS / native Linux, and **full** native-Windows parity. v1 targets **Windows + WSL2**
  (strongly recommended); if WSL is declined, a **reduced native-Windows-lite** mode installs only
  the cross-platform essentials (agent CLI, Node/Python/git via winget, markdown rules) — no
  graphify-mcp, bash hooks, or obsidian bridge (see §11a).
- Deterministic (fully-scripted) install adapters for Codex / Gemini / Kimi — those use the
  hand-to-agent path in v1. The `agents/` interface leaves room to script them later.

## 4. Locked decisions (from brainstorm)

| Decision | Choice |
|---|---|
| First deliverable | Source-controlled installer repo (no website yet) |
| "Other providers" | Other AI coding **agents** (Claude Code, opencode/Kimi, Codex, Gemini, …) |
| Access model | Free, no gate |
| Platforms | Windows + WSL2 (strongly recommended); **native-Windows-lite** reduced fallback if WSL declined |
| Delivery | Double-click **`.exe`** with the payload **compiled in**, shipped as a GitHub **Release asset from a private repo** |
| Competency gate | **First question**, 4 tiers (Never used a terminal · New to this · Some experience · Experienced) → drives verbosity + defaults |
| Multi-agent depth | **Approach C** — deterministic core + fully-scripted proven agents + hand-to-agent for the rest |
| Obsidian / vault | Optional opt-in module with a **clean starter vault** (never personal content) |
| Installer UX | Guided, **explained** picker — each choice says what it does + why + cost |
| Practices payload | **Full** — guardrails + agent-agnostic ruleset + onboarding; superpowers skills **referenced, not copied** |
| First real test | **Liam**, on **Kimi K3 via opencode** — exercises the hand-to-agent branch from day one |
| Name / domain | **Groundcrew**, `groundcrew.sh` primary (+ `groundcrew.io`) |

## 5. Architecture — repo layout

```
groundcrew/
  windows/                 # Windows entry (compiled to the double-click .exe)
    bootstrap.ps1          # WSL gate → install WSL/Ubuntu/Obsidian → unpack payload → run install.sh
    build-exe.ps1          # ps2exe build: embeds the bash payload, emits the release .exe
    native-lite.ps1        # winget reduced install when WSL is declined (§11a)
  install.sh              # WSL entry point — orchestrates modules, drives the explained picker
  core/
    base.sh               # git, gh, curl, wget, unzip, ca-certificates, build-essential,
                          #   pkg-config, jq, sqlite3, shellcheck, tmux
    python.sh             # python3, pip, uv, pipx, ruff, pyright
    node.sh               # Node 20 (nvm-managed), npm
    terminal-qol.sh       # ripgrep, fd, fzf, bat
    graphify.sh           # graphify via PyPI pkg `graphifyy` (provides graphify + graphify-mcp)
    path.sh               # idempotent PATH wiring into ~/.bashrc
  agents/
    claude-code.sh        # FULLY scripted: CLI, 11 official plugins (incl. superpowers), MCP, hooks
    opencode.sh           # scripted install; Kimi-K3 provider/auth via checklist + hand-to-agent
    prompts/
      codex.md            # "hand this to your agent" last-mile prompts
      gemini.md
      _template.md        # a new agent is a new prompt file, not new install code
  rules/
    AGENTS.md             # single cross-agent rules standard (each agent's native file imports it)
    practices.md          # the workflow practices the ruleset encodes (see §10)
  hooks/
    guard-destructive-git.sh  # refuses reset --hard / checkout -- / clean on dirty tree w/o confirm
    (further guardrail hooks as needed)
  onboarding/
    first-timer.md        # terminal primer + "your next 5 commands"
    mental-model.md       # how context windows / cold-start memory / cost actually work
  optional/
    rembg.sh              # background removal (onnxruntime + model)
    media.sh              # ffmpeg + ImageMagick
    playwright.sh         # Playwright + chromium (--with-deps)
    docker.sh             # Docker in WSL
    vault.sh              # Obsidian bridge + clean starter vault
  vault-template/         # clean starter vault: _Agent_System + empty dashboards
  lib/
    log.sh                # consistent logging/output
    guard.sh              # idempotency guards (is-installed checks)
    detect.sh             # detect which agents / tools are already present
  VERIFY.sh               # post-install self-check
  README.md               # human quick-start + the paste-blocks
```

## 6. Install flow

1. **Delivery = a double-click `.exe`** (a compiled PowerShell bootstrap with the bash payload
   embedded, shipped as a GitHub Release asset from the private repo). On launch it: (a) asks the
   **competency** question (§7); (b) checks for WSL2 — if absent, shows a **"strongly recommend
   WSL because …"** gate; (c) **if accepted:** enable WSL2, `wsl --install -d Ubuntu`, install
   Obsidian (if the vault module is wanted), unpack the payload into WSL, open a WSL window running
   `install.sh`; (d) **if WSL declined:** run the **native-Windows-lite** path (§11a). The
   **Support Gateway** path remains a fallback for remote/assisted installs (as used for Luke).
2. **`install.sh`** (inside WSL):
   1. Run all `core/*` modules (idempotent).
   2. **Detect / prompt** which agent(s) the user has → run `agents/claude-code.sh` and/or
      `agents/opencode.sh`; for any other agent, print/open the matching `agents/prompts/*.md`.
   3. Present the **guided explained picker** (see §7) for optional modules and agents → run the
      chosen ones. Install the **practices payload** (§10) for the chosen agent(s).
   4. Run `VERIFY.sh` and print a clear pass/fail summary + the remaining manual checklist.
3. **Irreducibly manual steps** (kept, but as copy-paste checklists): agent OAuth / API-key auth,
   Obsidian "Local REST API" plugin enable, `passwd`. The auth checklist **explicitly explains
   subscription login vs API key** — warning that a stray `ANTHROPIC_API_KEY` overrides a Pro/Max
   login and silently switches you to pay-per-token billing — plus plan gating and the cost model.
4. **End-of-run:** `exec bash` (so PATH is live without a manual restart), a short **terminal
   primer / "your next 5 commands"** screen for first-timers, and a reminder to keep projects in the
   **Linux home** (`~`), not `/mnt/c`, for speed and correct permissions.

## 7. Guided installer UX — the explained picker

The installer is not blind `y/N` prompts; it is an **interactive, explained picker** that doubles
as the newcomer's first lesson in *why* the stack is shaped this way. Each optional component is a
toggle with plain-language copy so the user chooses deliberately, not blindly.

- **Form:** a TUI checklist (`gum`/`whiptail`/`dialog`, or a small `fzf` menu — installed early in
  `core/`), with a graceful fallback to numbered text prompts on a bare terminal.
- **Each item shows:** name · one-line *what it does* · one-line *why it helps* · rough cost
  (time / disk / download). Example copy:
  - **Graphify** — "Turns your codebase into a queryable knowledge graph." *Why:* "Your agent finds
    the right files fast instead of grepping blindly — cheaper, more accurate answers."
  - **Obsidian + starter vault** — "A local notes app wired into your agent." *Why:* "Gives the
    agent a persistent memory and a place to track projects, so context survives between sessions."
  - **rembg / media / Playwright / Docker** — each with its own what/why plus a heavy-download warning.
- **Agents** get the same treatment: a short explainer of *Claude Code* vs *opencode / Kimi* vs
  *"I use another agent"* (hand-to-agent), so the user understands what they are wiring. The agent
  screen also explains **subscription vs API-key billing**, so nobody accidentally opts into
  pay-per-token pricing.
- **Competency (first screen):** 4 tiers — *Never used a terminal · New to this · Some experience ·
  Experienced* — asked before anything else. It sets the default preset and how much the picker
  explains: the two beginner tiers get the onboarding primer, full what/why copy, and the
  `recommended` preset pre-selected; experienced tiers get terse prompts and can jump to `everything`.
- **Quick-picks / defaults:** `minimal` · `recommended` (graphify + vault pre-checked) · `everything`.
  Core (toolchain) is always on and not a toggle.
- **Review screen** before anything installs: the full selection + total download size + one confirm.

This makes the installer a teaching surface — the first place a newcomer learns what graphify,
Obsidian, and the agent options actually give them.

## 8. Toolchain (full, tiered)

- **Core base (always):** git, gh, curl, wget, unzip, ca-certificates, build-essential,
  pkg-config, jq, sqlite3, shellcheck, tmux
- **Python (always):** python3, pip, uv, pipx, ruff, pyright
- **Node (always):** Node 20 (nvm-managed), npm
- **Terminal QoL (always):** ripgrep, fd, fzf, bat
- **Agent core (always):** graphify — installed from the PyPI package **`graphifyy`** (double-y; provides both the `graphify` CLI and the bundled `graphify-mcp` server) — then the selected agent CLIs
- **PATH wiring (always):** `~/.local/bin`, `~/bin`, npm-global bin, uv, pipx, nvm → `~/.bashrc`,
  written idempotently (no duplicate appends on re-run)
- **Optional opt-in modules (prompted via the explained picker):**
  - `rembg` — background removal (onnxruntime + model download)
  - media — ffmpeg + ImageMagick
  - Playwright — `npx playwright install --with-deps chromium`
  - Docker — container runtime in WSL
  - Obsidian + starter vault

Rationale for the additions beyond the original Luke set: `jq` / `sqlite3` / `fd` / `fzf` are
tools the *agents themselves* reach for constantly; `shellcheck` lints the very install scripts;
`tmux` keeps long agent runs alive; `pipx` gives clean global Python CLIs. Heavy/niche items are
opt-in so a minimal user isn't forced to download models and browsers.

## 9. Multi-agent mechanism (the core idea — Approach C)

- **Claude Code** → deterministic script (`agents/claude-code.sh`): CLI, the 11 official plugins
  (incl. superpowers), the obsidian MCP, hooks. Proven, so fully automated.
- **opencode** → `agents/opencode.sh` scripts the CLI install (its own `curl … | bash`
  installer is deterministic); the model/provider auth (Kimi K3 API key) + `AGENTS.md` wiring is
  a short checklist plus a hand-to-agent prompt. opencode already reads `AGENTS.md`, which fits
  the single-rules-file design; opencode is itself multi-provider, quietly covering part of
  "works for other providers".
- **Any other agent (Codex, Gemini, …)** → `agents/prompts/<agent>.md`: the deterministic core
  (toolchain + vault) is already in place, so the user hands the prompt to *their* agent, which
  wires its own native rules file, MCP, and hooks conversationally. Portable by construction;
  adding an agent is a new prompt file, not new install code.
- **One rules standard:** `rules/AGENTS.md` is the source of truth; each agent's native file
  (`CLAUDE.md`, `GEMINI.md`, opencode's `AGENTS.md`, …) imports it. Matches the existing repo
  convention (`CLAUDE.md` imports `AGENTS.md`).

## 10. Practices payload — guardrails, ruleset & onboarding

The workflow struggles newcomers hit (see §15) are not solved by installing binaries; they are
solved by **practices**. Groundcrew v1 ships the full set, encoded **agent-agnostically** so it
applies whether the user runs Claude Code, opencode/Kimi, or another agent.

**Delivery model.** The practices live in `rules/` (the `AGENTS.md` standard that each agent's
native file imports) and `hooks/` (enforced guardrails). Skill-style workflows that already exist
as the third-party **superpowers** plugin are **installed / referenced, not copied** —
`agents/claude-code.sh` installs the plugin, and the hand-to-agent prompts point other agents at
the equivalent workflow. Only Groundcrew's own agent-agnostic rules ship in-repo, keeping the
public repo clean and free of redistribution problems.

**What the ruleset encodes** (each mapped to a researched struggle):
- **Plan / brainstorm-first** before implementing — fixes oversized tasks & vague prompting.
- **Systematic debugging** (root-cause before retry) — breaks fix-break-fix loops.
- **Verify-don't-trust** + tests before "done" — catches blind trust & happy-path-only code.
- **Incremental-commit discipline** + the **destructive-git guard** — prevents wiped work.
- **Subagent delegation / explore-plan-execute** — caps context growth & cost, clean handoffs.
- **Context hygiene / checkpointing** + graphify — counters context rot.
- **Doc-grounding via context7 MCP** — catches hallucinated APIs/libraries.
- **Staged autonomy** (plan-mode / approve-before-execute defaults) — right level of intervention.

**Guardrail hooks** (`hooks/`). The flagship is the **destructive-git guard**: a pre-tool/Stop guard
that refuses `reset --hard` / `checkout --` / `clean` against an uncommitted working tree without an
explicit confirm. Enforced as a real hook where the agent supports hooks (Claude Code); where it
doesn't, the rule is stated in that agent's `AGENTS.md` import + hand-to-agent prompt.

**Onboarding docs** (`onboarding/`). A first-timer **terminal primer** ("your next 5 commands") and a
plain-language **mental-model note** — how context windows fill and degrade, why the agent starts
cold each session, and how billing/cost actually works — closing the "it remembers like a person"
gap that the research flagged as a root cause.

## 11. Starter vault (optional module)

Ships a **clean** vault via `optional/vault.sh` + `vault-template/`:

- `_Agent_System` rules + the Stop-hook vault lint (baseline-aware).
- Empty starter dashboards: Ideas Inbox, Open Todos, and a `Projects/` folder.
- The Obsidian bridge scripts in `~/bin` + vault symlink + `~/.claude/mcp.json` obsidian server.
- Gives the agent **cross-session memory** + project tracking (directly answers the "no memory
  between sessions" struggle).
- **Never** ships personal Obsidian content. Fully skippable.

## 11a. Native-Windows-lite fallback (WSL declined)

If the user declines WSL after the recommendation gate, Groundcrew does **not** fail — it runs a
**reduced** native-Windows path that installs only what genuinely works without a POSIX shell:

- **Installed (via winget):** the chosen agent CLI (Claude Code / opencode), Node, Python, git, plus
  ripgrep/fd/jq where a Windows build exists.
- **Shipped:** the markdown rules/practices (`rules/AGENTS.md` + the practices) and the onboarding
  docs — agent-agnostic text that works anywhere.
- **NOT available (stated up front):** graphify-mcp, the bash guardrail hooks (e.g. the
  destructive-git guard as a hook), and the Obsidian bridge — all assume a POSIX shell. The user is
  told exactly what they give up.
- **Framing:** WSL is the full experience; native-lite is a deliberately smaller, honestly-labelled
  subset. Full native parity is a future phase (§17), pursued only on real demand.

## 12. Idempotency & verification

- Every module checks-before-installing via `lib/guard.sh`, so re-running after a failure is safe
  and cheap — the central reliability upgrade over the old hand-run scripts.
- `VERIFY.sh` asserts: each tool on PATH + version; selected agent(s) authenticated; MCP servers
  reachable; vault symlink resolves (if vault installed); hooks registered; the destructive-git
  guard actually blocks a simulated `reset --hard` on a dirty tree. Emits a green/red summary and
  lists any remaining manual steps.

## 13. First test — Liam

- **User:** Liam. **Agent:** Kimi K3 via **opencode** (not Claude Code).
- Significance: Liam's first install runs entirely through the **core + opencode + hand-to-agent**
  path, validating Approach C in the real world immediately rather than in theory.
- Acceptance for the first test: from a clean Windows machine, Liam reaches a working opencode +
  Kimi K3 session with the Groundcrew toolchain on PATH, the practices ruleset wired into
  opencode's `AGENTS.md`, and (optionally) a starter vault, with `VERIFY.sh` green, in one guided
  pass.

## 14. Naming & domain

- **Groundcrew.** `.com` / `.dev` / `.ai` are taken (acceptable for a dev tool).
- **Primary `groundcrew.sh`** — the product *is* a shell installer, so `curl -fsSL groundcrew.sh
  | bash` becomes the brand. Also secure **`groundcrew.io`** as the credible fallback / main site.

## 15. Newcomer-struggle coverage (research-backed)

Two research passes (setup/environment + workflow/mental-model) distilled the recurring struggles
of people new to agentic coding. Status: **Covered** (handled by design / the practices payload) ·
**Noted** (documented risk).

### Setup & environment

| Struggle | Status | How |
|---|---|---|
| PATH not live until shell restart | Covered | `path.sh` idempotent wiring + end-of-run `exec bash` + reload note |
| npm global EACCES → sudo footgun | Covered | Node via nvm (user-owned; no global sudo) |
| PowerShell/CMD instead of WSL bash | Covered | `bootstrap.ps1` installs into and hands off to WSL bash |
| Never used a terminal | Covered | First-timer primer + "next 5 commands" screen + the explained picker |
| API key vs subscription billing surprise | Covered | Auth checklist warns re `ANTHROPIC_API_KEY` override + cost model |
| Node missing / too old | Covered | `node.sh` installs Node 20 |
| MCP setup opaque / "Connection closed" | Covered | `claude-code.sh` wires obsidian MCP; `VERIFY.sh` checks reachability with a clear message |
| WSL not enabled / working from `/mnt/c` | Covered | `bootstrap.ps1` enables WSL; installer targets `~` and VERIFY warns on `/mnt/c` |
| Wrong shell rc file | Covered | Targets `.bashrc` (Ubuntu default) |
| Plan gating (Pro/Max required) | Covered | Auth explainer in the picker |
| Regional / proxy blocking | Noted | Documented risk + mirror/VPS fallback |
| NVM version-scoped global "disappears" | Noted | Documented; pin a default Node |

### Workflow & mental model — covered by the practices payload (§10)

| Struggle | Status | How |
|---|---|---|
| Context rot in long sessions | Covered | graphify + context-hygiene guidance in the ruleset |
| Fix-break-fix loops | Covered | systematic-debugging workflow (root-cause before retry) |
| Blind trust in plausible code | Covered | verify-don't-trust step + tests |
| Tasks scoped too big | Covered | plan/brainstorm-first workflow |
| No cross-session memory | Covered* | starter vault + agent memory (*if the vault module is chosen) |
| Destructive git wiping work | Covered | destructive-git guard hook + incremental-commit rule |
| Token / cost blowups | Covered | small-scoping + subagent-delegation guidance |
| Knowing when to intervene | Covered | approve-before-execute / plan-mode defaults |
| Vague / underspecified prompting | Covered | spec/plan-first workflow |
| Hallucinated APIs / libraries | Covered | context7 doc-grounding MCP + real test runs |
| Missing read-the-diff / mental model | Covered | onboarding mental-model note (context windows, cold start, cost) |
| Happy-path-only code | Covered | edge-case prompting + tests |

## 16. Success criteria (v1)

- A single guided run on a clean Windows + WSL2 box yields a working agent environment with the
  full core toolchain on PATH and `VERIFY.sh` green.
- Re-running the installer is safe and makes no duplicate changes.
- Both Claude Code (scripted) and opencode/Kimi (scripted install + hand-to-agent) reach a
  working session with the practices ruleset wired in.
- The destructive-git guard blocks a simulated `reset --hard` on a dirty tree.
- A first-timer can follow the onboarding primer from a bare terminal to a first working task.
- Adding a new agent requires only a new `agents/prompts/<agent>.md`, no core changes.
- Liam completes a first install (guided by checklist) on Kimi K3 via opencode.
- The double-click `.exe` takes a clean Windows machine through the WSL gate to a running `install.sh`.
- Declining WSL yields a working native-lite install of the essentials, with the reduced-scope
  trade-offs clearly shown.
- The competency question is asked first and visibly changes verbosity + defaults.

## 17. Future extension points (out of scope now, designed-for)

- Public website that serves the installer (`groundcrew.sh`).
- Licensing / gating layer.
- macOS + native Linux install paths.
- Full native-Windows parity (beyond the native-lite subset).
- Deterministic (fully-scripted) adapters for Codex / Gemini / Kimi, replacing their prompts.
