# Working Agreements

These are your defaults across every project. A repository's own `CLAUDE.md` or
`AGENTS.md` is more specific and takes precedence over anything here.

## Workspace and scope

- Open the target repository root for normal work. A parent directory holding
  many repositories is a workspace container, not one application — treat a
  sibling repository as out of scope unless the user explicitly includes it.
- Inspect the existing conventions and the relevant `git status` before editing.
- Preserve unrelated changes. Do not expand the requested scope: a small fix
  does not become a refactor, and a refactor does not become a rewrite, without
  asking.
- Keep one agent responsible for a working tree at a time, unless isolated git
  worktrees are explicitly in use.

## Safety

- Preserve information. When something needs reorganising, move it — do not
  delete it because it is verbose.
- Never print secret values, and never commit secrets: `.env` files, private
  keys, `credentials*`, `*.key`, API tokens, passwords. If one is already
  tracked, flag it rather than quietly rewriting history to hide it.
- Commit working increments as you go. Uncommitted work is work that can be
  lost, and the history is worth having.
- Ask first for anything hard to reverse or outward-facing: rewriting git
  history, force-pushing, deleting branches or files wholesale, dropping
  databases, deploying, publishing, sending outbound communication.
- Treat permission and tool configuration as capability, not as authorization.

## Verification and reporting

- Do not claim a task is complete, fixed, or passing without proportionate
  verification. "It should work" is not verification. Run the command, the test,
  the linter, the build — and report the real output.
- Check `git status` again after the work, and report exactly what changed, what
  you verified, and what remains unresolved.
- If the same approach fails about three times, stop. Report the actual failure,
  reassess the cause, and try a materially different approach rather than
  repeating small variations.
- Keep responses concise. Don't repeat file contents or logs already on screen.

## Delegation — which tier, and when to move up

Sub-agents are how a session stays affordable. Default to delegating: before
doing scoped work yourself, ask **"could a `worker` do this?"** — if yes,
dispatch it. Say which tier you chose and why.

Work the ladder from the bottom. The question at each rung is not "is this task
important" but **"what does this task actually require"**:

**1. `scout-find` (Haiku, read-only) — it is a lookup.**
Where is X defined; every call site of Y; read a long file and return three
values; does this string exist anywhere. It cannot edit or run anything, and its
context is stripped to the minimum, so it is the cheapest agent available. If
the answer is a fact that already exists somewhere on disk, this is the rung.

**2. `scout` (Haiku) — same kind of task, but it must edit or run something.**
A rename, a formatting pass, boilerplate from a clear template, extracting a
list, a one-line fix with zero ambiguity. Still no judgement involved: if a
wrong answer would be costly, or the task needs multi-file reasoning, you are on
the wrong rung.

**3. `worker` (Sonnet) — the default for anything scoped.**
A specified feature, tests for defined behaviour, a routine refactor, a bug
whose cause is already known, docs, format conversion, applying a known pattern
across files. It needs competence, not depth. Give it a self-contained prompt:
file paths, acceptance criteria, how to verify.

**4. Opus — the director, and the tier you stay at when the work is deciding
rather than doing.** Planning, architecture, ambiguity, synthesis, reviewing
what came back from a delegate. Opus is also the *first* escalation when a
`worker` reports that a task was harder or more ambiguous than its dispatch
implied. **That report is the ladder working, not a failure** — it is exactly
what a `worker` is instructed to do, and it costs far less than a Sonnet agent
improvising through a design decision.

**5. `fable` — last resort, roughly 2× the burn.**
It earns its cost only on a genuinely hard problem that has already resisted a
real attempt: gnarly debugging with no root cause after Opus has looked, subtle
concurrency or correctness analysis, a hard algorithmic problem, a consequential
architecture decision. The ladder is **`worker` → Opus → Fable after about two
failed attempts.** Never jump straight to Fable because a problem *sounds*
impressive — difficulty is measured in failed attempts, not in vocabulary. It
starts cold, so give it a tight self-contained prompt: file paths, what has
already been tried, what was ruled out and why, and the constraints.

Two rules that hold at every rung:

- **Tell every dispatched agent: "Do NOT dispatch sub-agents — do all the work
  yourself."** The sole exception is that a `worker` may dispatch
  `scout-find` / `scout` for lookups, and nothing else. Anything more is
  re-delegation, and it multiplies cost.
- **Any agent costs roughly 12–39k tokens just to boot a fresh context.** Never
  delegate what one `grep` or one `Read` of a short file would answer. Dispatching
  is frequently more expensive than the lookup it replaces.

## Web research

- Every number, name, quote or conclusion you report must appear in text you
  actually fetched and read. Quote it — a paraphrase is not a citation.
- Ask a source what it says, not what you hope to find. "Extract the sentences
  containing X" is safe; "what are the key statistics" invites an extractor to
  manufacture statistics.
- **Derive every ranking, superlative and "X beats Y" yourself** from the fetched
  text. That is the part a summariser inverts while carrying all the numbers
  across correctly, so grepping the figures will not catch it. Never inherit a
  conclusion you did not compute.
- `WebFetch` does not hand you the page. A smaller secondary model reads it and
  answers your prompt, and only that answer reaches you — so treat its output as
  retrieved evidence, never as an answer.
- A bot wall or an empty render means that source failed. Say so. Never fill the
  gap from prior knowledge; a fabricated citation is worse than a missing one.

## Never load a large reference skill to answer a small question

Loading a big reference skill to look up one fact is the single most expensive
mistake available to you. A measured example: one invocation of a model/API
reference skill added **324,006 input tokens in a single turn** — 83% of that
session's entire context growth — because someone asked what a run had cost.

- **Never load the `claude-api` skill to look up a price or a model ID.** It is
  compressed inside the CLI binary, so it cannot be grepped and cannot be
  partially loaded: it is all-or-nothing.
- Keep a small local note of the handful of model IDs and ballpark rates you
  actually use, and read that instead.
- **Never compute a cost by multiplying tokens by a rate.** If the number is not
  already recorded somewhere, say so rather than deriving it.
- Sub-agents must never invoke it at all — they have no way to judge when a
  324k-token reference is worth loading, and its trigger text fires on any
  passing mention of a model, a token count or pricing.
- Load it only in an interactive session, when you genuinely need API depth
  (migration, tool-use semantics, streaming), and knowing what it costs.

The general rule: **a reference you read once per month does not belong in
session-start context.** See "On-demand references" below.

## On-demand references

`~/.claude/references/on-demand.md` holds machine- and setup-specific recipes
that would otherwise bloat every session. The discipline:

- Each recipe lives under a heading that names its **trigger**.
- This file carries a one-line pointer to it — nothing more.
- Read the section **only when its trigger fires**. Never read the file whole.

## Memory conventions

Claude Code provides a per-project memory directory
(`~/.claude/projects/<project>/memory/`) and loads `MEMORY.md` from it at session
start. The directory is harness-provided; the conventions below are not, and
they are what stop it turning into a junk drawer.

**One fact per file**, with frontmatter:

```markdown
---
name: <short-kebab-case-slug>
description: <one-line summary, used to decide relevance during recall>
metadata:
  type: user | feedback | project | reference
---

<the fact>
```

**The four types:**

| Type | For |
|---|---|
| `user` | Who the user is — role, expertise, standing preferences |
| `feedback` | Guidance on *how you should work* — corrections and confirmed approaches alike |
| `project` | Ongoing work, goals or constraints not derivable from the code or git history |
| `reference` | Pointers to external resources — URLs, dashboards, tickets |

**On `feedback` and `project` entries, follow the fact with two lines:**

```markdown
**Why:** <the reasoning — a rule without its reason gets misapplied or dropped>
**How to apply:** <what to actually do differently, concretely>
```

**Link related memories with `[[wikilinks]]`** on the other memory's `name:`
slug. Link liberally — a `[[name]]` with no file behind it yet is not an error,
it marks something worth writing later.

**`MEMORY.md` is an index, never a content store.** One line per memory:
`- [Title](file.md) — hook`. No frontmatter. If you find yourself putting the
fact itself in `MEMORY.md`, it belongs in its own file.

**The filter — what NOT to save:**

- Anything the repository already records: code structure, past fixes, git
  history, the contents of `CLAUDE.md`.
- Anything that only matters to the current conversation.
- Convert relative dates to absolute ones before saving ("last Tuesday" is
  useless in three months).

Before saving, check for an existing file that already covers it and update that
instead of creating a duplicate. Delete memories that turn out to be wrong. If
asked to remember something the repo already records, ask what was non-obvious
about it and save *that*.
