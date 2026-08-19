---
name: full-auto
description: Use when the user says "full auto", "start full auto mode", "go autonomous", "proceed autonomously", "run with it", or otherwise hands over a body of agreed work and steps away. Sets the working contract — delegate to sub-agents, never block on questions, take the recommended option and report it — so they never have to recite it.
---

# Full Auto Mode

The user has approved a direction and is stepping away. They want the work done,
not a conversation about the work.

Announce it once ("Full auto — I'll batch everything for the end") and then go
quiet until the work is done.

## The contract

1. **Never block on a question.** There is nobody at the keyboard. A blocking
   question does not pause the work; it kills the whole run.
2. **When a decision arises, take the option you would have recommended**, write
   down what you chose and why, and keep going. Do not stop to ask.
3. **Save every question, assumption and judgement call for the final report.**
   One report at the end, not a running commentary.
4. **Delegate wherever the work is delegable** — see the delegation ladder in
   `~/.claude/CLAUDE.md`. Full auto is when the "could a `worker` do this?"
   habit matters most, because there is nobody to notice you grinding through
   scoped work at the most expensive tier.
5. **Verify before claiming.** Autonomy raises the cost of a false green: nobody
   is watching, so an unverified claim can sit unchallenged for hours. Run the
   tests. Quote the result.
6. **Stop and report early if a genuine blocker appears** — something where
   every available assumption is unsafe or would make the work useless if wrong.
   That bar is high. Almost nothing clears it; a missing preference does not.

## Decisions still out of scope

Full auto does not authorise what was never authorised:

- No commit, push, merge, deploy or history rewrite unless the user asked.
- No destructive or outward-facing action.
- No expanding the agreed scope. Finish what was agreed; put the good ideas in
  the report.

If the work genuinely needs one of these, do everything else and put the request
in the report.

## The final report

Lead with what shipped and its verification. Then, as separate sections:

- **Decisions I made for you** — each with the option chosen and the one-line
  reason. This is the section they actually read.
- **Questions** — the things that genuinely need them.
- **What I did not do** — anything left out, and why.

Keep it skimmable: headers, bullets, a state table. No log of the journey.

## Related

- `~/.claude/CLAUDE.md` — delegation ladder, verification and reporting rules
- `ship-to-main` — if they ask for the result to reach the default branch afterwards
