---
name: ship-to-main
description: Use when the user says "ship it", "get it on to main", "let's merge it", "put it on main", or otherwise asks for finished work to reach the default branch via a branch, a PR, a review gate and a merge. Reads RULES.md for the project's own branch, gate and merge policy, and refuses to run until that file is configured.
---

# Ship to main

The route from working code to the default branch. The user should not have to
recite these steps.

## Step 0 — read `RULES.md`, and stop if it is unconfigured

**Before anything else, read `RULES.md` in this skill's own directory.**

If it still contains the line `GROUNDCREW-UNCONFIGURED`, **stop immediately**
and tell the user:

> `ship-to-main` is not configured yet. It needs to know your default branch,
> your review gate, and your merge policy before it can ship anything. Open
> `~/.claude/skills/ship-to-main/RULES.md`, fill in the fields, and delete the
> `GROUNDCREW-UNCONFIGURED` marker line. I'll walk you through it if you like.

Do not guess. Do not ship using plausible defaults. A shipping workflow that
invents a review gate is worse than none, because it produces the *appearance*
of a gate having been satisfied.

Everything below reads its specifics from `RULES.md`. Where this file says
"the gate", "the default branch" or "the merge command", it means the values
configured there.

## The steps

1. **Verify the work first.** Run the tests, the linter, the build. Read your
   own diff. A review gate is not a substitute for having checked — and if the
   gate is a bot, it is checking a change you have not yet validated yourself.
   Report the real output.

2. **Branch.** Never commit finished work directly to the default branch.

   ```bash
   git switch -c <descriptive-branch-name>
   ```

3. **Commit.** Small, focused commits with messages that explain *why*. Follow
   the AI-attribution policy in `RULES.md` — for a public repository that
   usually means no AI trailers, in the commit *and* in the PR body, because a
   squash merge turns the body into public commit history.

4. **Push and open a PR.**

   ```bash
   git push -u origin HEAD
   gh pr create --body-file <file>
   ```

   Use `--body-file`, not `--body`. An inline body breaks on apostrophes.

5. **Request a verdict from the gate**, exactly as `RULES.md` describes. Naming
   a reviewer in prose is usually not a request — most systems need a specific
   action (a comment, an assignment, a check trigger) to actually notify anyone.

6. **Wait for the verdict, and look where `RULES.md` says it appears.**

   **This is where agents fail, and it fails silently.** The common shape: an
   agent writes its own poll loop against the endpoint where *findings* land,
   waits for a pass to show up there, and spins until timeout — because a clean
   pass never appears on that endpoint at all. The loop is structurally
   incapable of observing the one outcome it is waiting for.

   So: poll the place `RULES.md` names, not the place that seems obvious. If
   `RULES.md` names a script or command that encodes the verdict rules, run
   **that** rather than writing your own wait.

   Report what you see roughly every few minutes rather than blocking silently.
   A long opaque wait is how a *refusal* masquerades as "still working".

   **Silence is not a pass.** No verdict means not reviewed.

7. **Check the verdict is for the current commit.**

   ```bash
   git rev-parse HEAD
   ```

   If your gate reports a reviewed commit (see `RULES.md`), it must equal this.
   **A review of an older commit is not a review of the PR** — and this bites
   constantly, because your own fixes move `HEAD`. A PR that keeps receiving
   commits silently keeps a stale pass and *looks* reviewed.

8. **Findings? You fix them.** The gate reviews; it does not fix. You hold the
   context that produced the diff, so fixing it is yours and it is faster.

   Take each finding on its merits rather than on faith. A correct finding can
   imply an incorrect fix — verify the underlying problem, fix that, and say so
   in your reply so the reasoning is on the record.

   Then re-request a verdict **at the new commit**, because your fix moved
   `HEAD` and a verdict does not follow a push.

9. **Respect the round cap in `RULES.md`.** After the configured number of
   rounds, stop and do whatever `RULES.md` says happens next. The cap exists
   because the marginal finding stops being worth the round-trip — not because
   the findings are wrong. Fixing every earlier round properly is what earns the
   right to stop.

10. **Merge**, using the command in `RULES.md`, then **verify it merged.**

    ```bash
    gh pr view <N> --json state --jq .state    # must print MERGED
    ```

    `gh pr merge` prints nothing on success, so "it didn't error" is not
    evidence.

11. **Sync local and do the post-merge steps** listed in `RULES.md`.

    After a squash merge, local default-branch history diverges and
    `git pull --ff-only` refuses. Before `git reset --hard origin/<branch>`,
    prove nothing is lost:

    ```bash
    git diff <your-branch> origin/<branch>    # must be empty
    ```

## Red flags

Each of these is a real failure, not a hypothetical:

- **"It passed."** — *At which commit?* Compare it to `HEAD`.
- **"The review endpoint is empty, so nothing came back."** — Check where
  `RULES.md` says a pass actually appears. Silence there proves nothing.
- **"`gh pr merge` didn't error, so it merged."** — Verify the state.
- **"It's been quiet a while, it must have passed."** — Silence is pending,
  never clean.
- **"It passed, then I pushed one more fix."** — Your verdict is now stale.
- **"The gate flagged it, so I'll do exactly what it says."** — Verify the
  finding first; the implied fix is sometimes the wrong one.
- **"I'll ask the reviewer to fix it."** — Most gates review and do not fix.
  Asking burns a round-trip and strands the PR.
- **"A green gate means my fix works."** — It does not. Run the suite.
- **"`RULES.md` isn't filled in but I know roughly how this project ships."** —
  Stop. That guess is the exact thing step 0 exists to prevent.

## Related

- `RULES.md` — this skill's configuration. It does not run without it.
- `~/.claude/CLAUDE.md` — verification and safety rules that apply throughout.
