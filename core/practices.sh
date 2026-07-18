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
  if [[ -f "$dest" ]]; then
    log::info "AGENTS.md already exists at $dest, leaving it in place"
    return 0
  fi
  cp "$payload_dir/AGENTS.md" "$dest" || return 1
  log::ok "wrote $dest"
}

_practices__install_git_guard() {
  local payload_dir="$1" target="$2" hooks_dir="$2/.git/hooks"
  if [[ ! -d "$target/.git" ]]; then
    log::info "$target is not a git repo, skipping git-guard hook"
    return 0
  fi
  mkdir -p "$hooks_dir" || return 1
  cp "$payload_dir/hooks/git-guard.sh" "$hooks_dir/pre-push" || return 1
  chmod +x "$hooks_dir/pre-push" || return 1
  log::ok "installed pre-push guard hook"
}
