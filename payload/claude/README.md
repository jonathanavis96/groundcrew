# claude-kit — the `~/.claude` layer

Groundcrew's core install gives you the toolchain. This is the layer above it:
the configuration that decides how your agent *behaves* — sub-agents, working
agreements, hooks, skills, and the memory conventions that stop your notes
turning into a junk drawer.

Install it with:

```bash
bash install.sh --module claude-kit
```

Everything lands under `~/.claude`. Nothing is overwritten: an existing file is
backed up to a timestamped sibling first, and `settings.json` is never touched
by the module at all — it prints the keys for you to merge.

## What is in here

| Path | What it is |
|---|---|
| `CLAUDE.md` | Working agreements: scope, safety, verification, web research, and the **delegation ladder** — which agent tier to use and when to move up. Also the memory-file conventions. |
| `agents/` | `scout-find`, `scout`, `worker`, `Explore`, `fable` — the tiers the ladder refers to. |
| `references/on-demand.md` | A **blank template**. The discipline it teaches: keep session-start context lean, put each recipe under a trigger heading here, leave a one-line pointer in `CLAUDE.md`, and read it only when its trigger fires. |
| `settings-additions.json` | Keys to **merge** into your `settings.json`, with the reasoning for each. |
| `hooks/webfetch-guard.py` | Rewrites `WebFetch` prompts into extraction-only requests, so figures come back verbatim and *your* model does the reasoning. |
| `hooks/session-context.py` | Injects a markdown file as session context. Replaces the usual `jq` one-liner, so the same hook works on Windows. |
| `hooks/caveman-autostart.sh` / `.ps1` | Opt-in. Auto-loads the `caveman` reply style at session start. Two twins so it is never a silent no-op. |
| `cache-guard/` | Deterministic session handoff + a guard that stops you re-warming a huge stale context after the prompt cache goes cold. Python stdlib only, no network calls. |
| `skills/caveman/` | Opt-in. A compressed reply style. |
| `skills/full-auto/` | Opt-in. The working contract for "I've approved this, I'm stepping away." |
| `skills/ship-to-main/` | Opt-in. Branch → commit → PR → review gate → merge. **Inert until `RULES.md` is filled in** — the gate is a named slot, not a named tool. |
| `vault/` | Optional Obsidian tier: MCP config template, starter agent rules, the baseline-aware linter and its `Stop` gate, and the wikilink/memory guards. |

## Things worth knowing before you install

- **`autoCompactWindow` is set to 300000 tokens**, which compacts noticeably
  earlier than the model default. That is a deliberate cost trade, explained in
  `settings-additions.json`. Raise it or delete it if it does not suit you.
- **`skipDangerousModePermissionPrompt` is deliberately NOT set.** It removes the
  confirmation before entering bypass-permissions mode. It grants no capability
  you do not already have; it only removes a check. Leave it at stock.
- **The vault tier needs two manual steps** no agent can do for you: installing
  the Obsidian desktop app, and enabling its **Local REST API** community plugin
  to get an API key.
- **The vault rules are a starter, not a standard.** They describe one person's
  note model, with the reasoning attached so you can tell taste from mechanism.
  Reshape them. The part worth keeping is the lint baseline, which is what makes
  *any* set of rules adoptable on a vault that already has a thousand notes.
