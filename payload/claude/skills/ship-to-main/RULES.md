# ship-to-main — your configuration

The `ship-to-main` skill is **inert until this file is filled in.** Its first
instruction is to read this file, and if the placeholder marker below is still
present it stops and tells you to configure it rather than guessing how your
project ships.

That is deliberate. A shipping workflow that guesses at your default branch,
your review gate or your merge policy is worse than no workflow at all.

---

<!-- GROUNDCREW-UNCONFIGURED: delete this entire comment line once you have
     filled in every field below. The skill refuses to run while it is here. -->

## Default branch

**Branch:** `main`

The branch finished work lands on. Change to `master`, `develop`, or whatever
your projects actually use.

## The review gate

**Gate:** _(unset)_

This is the **named slot** the skill waits on. It is deliberately not a specific
tool — fill in whatever actually reviews your changes. Any of these are valid:

- a bot reviewer that comments on the PR
- a named human reviewer whose approval is required
- a CI check that must go green
- a sub-agent you dispatch to review the diff
- "none — I self-review", which is a legitimate answer for a solo project

**How to request a verdict:** _(the exact command, comment, or action)_

**Where the verdict appears:** _(the exact place to look — a PR review, an issue
comment, a check run. Getting this wrong is the classic failure: an agent polls
the endpoint where a *failure* lands and never sees the pass, so it waits
forever on a review that already succeeded.)_

**What counts as a pass:** _(the exact string or state. Be literal. "Looks fine"
is not a verdict; `APPROVED`, `PASS`, or a green check is.)_

**What counts as "not yet":** _(silence is never a pass. Say what pending looks
like so it is not mistaken for either outcome.)_

**Verdicts are pinned to a commit.** A review of an older commit is not a review
of the PR. If your gate reports which commit it reviewed, say where that appears
here — the skill compares it to `HEAD` before allowing a merge.

**Reviewed-commit appears at:** _(where, or "not reported" if your gate doesn't)_

## Rounds

**Maximum review rounds:** `2`

After this many rounds of findings, stop looping. Say what happens next:

**After the cap:** _(merge anyway having fixed everything found / escalate to a
human / abandon the branch)_

## Merge policy

**Merge command:** `gh pr merge <N> --squash --delete-branch`

**After merging:** _(sync local, mirror elsewhere, restart anything running the
old code — list what applies to you, or "nothing")_

## Commit message policy

**AI attribution in commits and PR bodies:** _(allowed / never)_

If your repositories are public, "never" is usually the right answer — a squash
merge turns the PR body into the commit message, so it lands in public history.
