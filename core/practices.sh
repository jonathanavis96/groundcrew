# shellcheck shell=bash
# Drops a starter AGENTS.md ruleset and a pre-push safety hook into the
# target project, so any coding agent (not just this one) picks up the
# same working agreements.
practices::install() {
  guard::run_once core-practices _practices__do
}

_practices__do() {
  local payload_dir target
  payload_dir="$(dirname "${BASH_SOURCE[0]}")/../payload"
  target="${GROUNDCREW_TARGET:-$PWD}"

  log::step "Installing agent working agreements"
  _practices__install_agents_md "$payload_dir" "$target" || return 1
  _practices__install_git_guard "$payload_dir" "$target" || return 1
  log::ok "agent practices installed"
}

_practices__install_agents_md() {
  local payload_dir="$1" dest="$2/AGENTS.md"
  # -L too: a dangling symlink fails -f, and cp would refuse to write through it.
  if [[ -f "$dest" || -L "$dest" ]]; then
    log::info "AGENTS.md already exists at $dest, leaving it in place"
    return 0
  fi
  cp "$payload_dir/AGENTS.md" "$dest" || return 1
  log::ok "wrote $dest"
}

_practices__install_git_guard() {
  local payload_dir="$1" target="$2" hooks_dir common
  local src="$payload_dir/hooks/git-guard.sh"
  # -e, not -d: in a linked worktree or submodule .git is a file pointing at
  # the real git dir, and hooks live in the common dir, not under $target.
  if [[ ! -e "$target/.git" ]]; then
    log::info "$target is not a git repo, skipping git-guard hook"
    return 0
  fi
  # GIT_DIR pins git to $target, so a broken .git cannot fall through to a
  # parent repository's hooks.
  target=$(cd "$target" && pwd) || return 1
  if ! common=$(GIT_DIR="$target/.git" git -C "$target" rev-parse --git-common-dir 2>/dev/null); then
    log::warn "$target/.git is not a usable git dir, skipping git-guard hook"
    return 0
  fi
  [[ "$common" == /* ]] || common="$target/$common"
  hooks_dir="$common/hooks"
  mkdir -p "$hooks_dir" || return 1
  # git-guard.sh self-dispatches on its hook name: pre-push blocks force-push to
  # main, pre-commit blocks staged secrets. Install both so both paths are live.
  _practices__install_hook "$src" "$hooks_dir/pre-push" || return 1
  _practices__install_hook "$src" "$hooks_dir/pre-commit" || return 1
  return 0
}

# Copy the guard into a hook slot without clobbering a hook the project already
# relies on (Husky, lint/test gates, etc.).
_practices__install_hook() {
  local src="$1" dest="$2"
  if [[ -e "$dest" ]]; then
    log::warn "hook already exists at $dest — leaving it; chain groundcrew's git-guard.sh in manually if you want it"
    return 0
  fi
  cp "$src" "$dest" || return 1
  chmod +x "$dest" || return 1
  log::ok "installed $(basename "$dest") guard hook"
}
