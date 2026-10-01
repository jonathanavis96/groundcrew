#!/usr/bin/env bash
# shellcheck shell=bash
#
# git-guard.sh — a defensive git hook that blocks a couple of destructive
# actions before they leave the machine (or land in a commit):
#
#   * force-pushing (or any non-fast-forward push, which requires --force
#     or --force-with-lease to succeed) to a shared branch such as
#     main or master.
#   * committing a file that looks like a secret: .env files, private
#     keys (*.pem, id_rsa, id_ed25519, id_ecdsa, id_dsa and their *_<type>
#     variants), credentials files, or *.key files.
#
# This runs as a standalone git hook, invoked directly by git rather than
# sourced, so it cannot rely on this repo's lib/log.sh being available —
# it writes its own messages straight to stderr.
#
# Install as .git/hooks/pre-push and/or .git/hooks/pre-commit; it works as
# either and tells the two apart from its own filename ($0), which git sets
# to the path of the hook it invoked. If it can't tell which hook it is
# running as, it does nothing rather than guess — a safe no-op beats a
# false block.

set -u

_guard_block() {
  echo "git-guard: blocked - $*" >&2
  echo "git-guard: if this is genuinely intended, override deliberately (e.g. temporarily move the hook aside) rather than routing around it silently." >&2
  exit 1
}

_guard_is_protected_branch() {
  case "$1" in
    main | master) return 0 ;;
    *) return 1 ;;
  esac
}

_guard_is_zero_sha() {
  case "$1" in
    "" | *[!0]*) return 1 ;;
    *) return 0 ;;
  esac
}

# --- pre-push: refuse a non-fast-forward push to a protected branch ----
# A non-fast-forward update can only reach the remote via --force or
# --force-with-lease, so refusing it here is equivalent to refusing those
# flags for the branches this hook protects.
_guard_check_pre_push() {
  local local_ref local_sha remote_ref remote_sha branch rc
  while read -r local_ref local_sha remote_ref remote_sha; do
    [[ -z "$local_ref" ]] && continue
    branch="${remote_ref#refs/heads/}"
    _guard_is_protected_branch "$branch" || continue
    _guard_is_zero_sha "$local_sha" && continue   # deleting a ref, not force-pushing
    _guard_is_zero_sha "$remote_sha" && continue  # brand-new branch, nothing to overwrite

    # A remote tip this clone has never fetched cannot be an ancestor of
    # anything we hold, so the push can only land by overwriting it - the
    # exact "force-push over someone else's unseen work" case.
    if ! git cat-file -e "${remote_sha}^{commit}" 2>/dev/null; then
      _guard_block "non-fast-forward push to protected branch '$branch' (remote tip $remote_sha is not in this clone; fetch first)"
    fi

    rc=0
    git merge-base --is-ancestor "$remote_sha" "$local_sha" 2>/dev/null || rc=$?
    if [[ "$rc" -eq 1 ]]; then
      _guard_block "non-fast-forward push to protected branch '$branch'"
    fi
    # Any other rc means git itself errored - we can't be sure, so allow.
  done
}

# --- pre-commit: refuse staging a file that looks like a secret --------
# Matched case-insensitively: on a case-insensitive filesystem (macOS, Windows,
# WSL drvfs) ".ENV" or "Server.PEM" is the same secret as its lowercase twin.
_guard_is_secret_file() {
  local base
  base="$(basename -- "$1" | tr '[:upper:]' '[:lower:]')"
  case "$base" in
    .env | .env.*) return 0 ;;
    *.pem) return 0 ;;
    *_rsa | *_ed25519 | *_ecdsa | *_dsa) return 0 ;;
    *credentials*) return 0 ;;
    *.key) return 0 ;;
    *) return 1 ;;
  esac
}

# R is included so "git mv notes.txt .env" cannot slip a secret in as a rename,
# and -z keeps paths raw: without it git C-quotes any path with a non-ASCII
# byte ("caf\303\251/.env"), and the trailing quote defeats the name match.
_guard_check_pre_commit() {
  local f
  while IFS= read -r -d '' f; do
    [[ -z "$f" ]] && continue
    if _guard_is_secret_file "$f"; then
      _guard_block "staged file '$f' looks like a secret"
    fi
  done < <(git diff --cached --name-only -z --diff-filter=ACMR 2>/dev/null)
}

main() {
  case "$(basename -- "${0:-}")" in
    pre-push) _guard_check_pre_push ;;
    pre-commit) _guard_check_pre_commit ;;
    *) : ;; # unrecognised hook context - safe no-op
  esac
}

main "$@"
