# Vault agent rules — a starter you are meant to reshape

**Read this first: these rules are a worked example, not a standard.**

The note model below — hub / tasks / changelog / technical — is one person's way
of working. It is here so you have something concrete to react to, with the
reasoning attached to each part, so you can tell which bits are load-bearing and
which are taste. **Change it to fit how you think.** A note model you did not
choose is a note model you will not keep.

The one part worth keeping intact is the **lint baseline mechanism** (see
"Making the rules enforceable" at the bottom). That is what lets any set of
rules — including a set you invent next month — be adopted on a vault that
already exists. Rules nothing checks are decoration.

---

## Why a note model at all

An agent writing into a vault with no structure produces a vault that only the
agent can navigate: state duplicated across five notes, none of them
authoritative, and no way to tell what is currently true. The model exists to
answer one question cheaply — **where does this piece of information go?** — so
that the answer is the same every time.

Any model that answers that question consistently will work. This one does it by
splitting each project into four notes by *how the information changes over
time*.

## The four-note family (the example)

For a project called `MyProject`:

| Note | Holds | Why it is separate |
|---|---|---|
| `MyProject.md` (the hub) | Current state. What is true *right now*. | It must stay short enough to read in full every time. That only works if nothing accumulates in it. |
| `MyProject - Tasks.md` | Executable actions, as checkboxes. | Tasks have a lifecycle (open → done → gone). Mixing them into the hub makes the hub grow forever. |
| `MyProject - Changelog.md` | What shipped, dated, append-only. | This is *supposed* to grow without bound. Keeping it out of the hub is what lets the hub stay small. |
| `MyProject - Technical.md` | Durable implementation detail, decisions, gotchas. | Reference material that is read on demand, not on every visit. |

**The rule that makes it work: each fact lives in exactly one of these.** If you
find yourself copying a task into the hub "so it's visible", the model has
already broken.

### The hub

- **A dashboard, not a diary.** Replace stale state; never append dated history
  to it. History goes in the changelog.
- Target: under **80 non-blank lines**. A `## Current state` section of at most
  **8 concise bullets**.
- If the hub is over budget, that is not a formatting problem — it means content
  belongs in one of the companion notes.

*Why those numbers:* they are small enough that reading the hub is always
cheaper than reconstructing state from the other notes. Pick your own budget,
but pick one — an unbounded hub degrades into a diary within weeks.

### The task note

- Open tasks go under `## Now` or `## Next`. Nothing else.
- **A checkbox means an executable action.** Waiting on someone, "maybe later",
  optional, deferred, blocked — these are plain bullets, not unchecked tasks.
- A completed task gets its outcome logged in the changelog and is then removed
  from Now/Next.

*Why:* an unchecked box that nobody can act on is indistinguishable from work in
flight. Once a task list contains items that can never be ticked, it stops being
a task list and the whole thing gets ignored.

### Companion notes are exempt from the hub rules

An archive or an append-only changelog is *meant* to be long. The linter matches
companion notes by name suffix (`Tasks`, `Backlog`, `Changelog`, `Technical`,
`Reference`, …) precisely so a 700-line changelog is never judged as an
oversized hub.

## Rules that are worth keeping whatever model you choose

These are not about the four-note shape. They are about not corrupting the vault:

1. **Never wikilink a memory slug.** Writing `[[reference_build_pipeline]]` makes
   Obsidian materialise an *empty phantom note* at the vault root the moment the
   link is followed or synced. Reference a memory slug as inline code —
   `` `reference_build_pipeline` `` — and link real notes by their title. A
   PostToolUse hook (`vault-slug-wikilink-guard.py`) enforces this at write time,
   because fresh-context sub-agents never see this file.

2. **One canonical location per fact, linked from everywhere else.** Duplication
   is how a vault starts lying to you: two copies drift, and neither is marked
   stale.

3. **Do not auto-migrate.** Finding an old note that does not match the current
   model is not a licence to rewrite it. Preserve it and propose a focused
   migration.

4. **Memory and vault have different jobs.** Memory holds behavioural rules and
   thin pointers; the vault holds live project state. When they disagree, the
   vault wins — memory is written once and rarely revisited.

## Making the rules enforceable — the baseline mechanism

**This is the part to keep.**

`vault_lint.py` checks the rules above. On an existing vault it will find
hundreds of violations on day one, and a linter that reports 400 findings gets
turned off within the hour. The baseline solves that:

```bash
# Once: record everything wrong today as "known and accepted".
python3 _Agent_System/vault_lint.py . --write-baseline _Agent_System/lint-baseline.json

# Every time after: report only what is NEW relative to that.
python3 _Agent_System/vault_lint.py . --baseline _Agent_System/lint-baseline.json
```

So you can adopt a strict rule **without fixing a thousand old notes first**.
Only the notes you touch from now on have to be clean, and the pile of legacy
findings shrinks as you happen to pass through.

Two details that matter:

- **A finding's baseline key deliberately excludes anything that changes as a
  note is edited** (line counts and the like). When the count was part of the
  key, editing an over-budget hub shifted `437 → 447` and re-fired the *same*
  known warning as new — punishing the exact act of tidying a stale note.
- **Re-write the baseline deliberately, never casually.** `--write-baseline`
  forgives everything currently wrong. Doing it to make a red build go green is
  how the whole mechanism becomes theatre.

`stop_vault_lint.py` wires this into a `Stop` hook: a session that **wrote to the
vault** and left NEW errors is blocked with the specific findings; a session that
did not touch the vault only gets a warning, so an unrelated coding session is
never wedged by a note someone edited in Obsidian directly.

Wire it in `~/.claude/settings.json`, not only in the vault's own project
settings — vault writes overwhelmingly happen *during ordinary coding sessions*
(appending a changelog entry after shipping), not while sitting in the vault as
a project.

## When you reshape this

Keep the mechanism, replace the rules:

1. Decide what your note families actually are.
2. Edit the rules in `vault_lint.py` to match — the checks are short and
   deliberately readable.
3. Re-run `--write-baseline` once, on purpose.
4. Update this file so the reasoning matches the rules, because in six months
   this file is the only thing that will explain why the linter is shouting.
