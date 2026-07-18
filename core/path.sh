# shellcheck shell=bash
path::wire() {
  local rc="${1:-$HOME/.bashrc}"
  local begin='# >>> groundcrew path >>>'
  local end='# <<< groundcrew path <<<'
  [[ -f "$rc" ]] || touch "$rc"
  if grep -qF "$begin" "$rc"; then
    log::info "PATH block already present in $rc"
    return 0
  fi
  cat >> "$rc" <<EOF
$begin
export PATH="\$HOME/.local/bin:\$HOME/bin:\$PATH"
export NVM_DIR="\$HOME/.nvm"
[ -s "\$NVM_DIR/nvm.sh" ] && \\. "\$NVM_DIR/nvm.sh"
$end
EOF
  log::ok "wired PATH into $rc"
}

# Wire PATH into every shell rc the user is likely to open: always ~/.bashrc, and
# ~/.zshrc as well on macOS (where zsh is the default login shell) so a fresh
# Terminal picks up the toolchain. Each wire is idempotent.
path::wire_shells() {
  path::wire "$HOME/.bashrc" || return 1
  if [[ "$(os::detect)" == macos ]]; then
    path::wire "$HOME/.zshrc" || return 1
  fi
  return 0
}

# Activate the installed toolchain in the CURRENT process (PATH + nvm), so later
# install steps and a same-process VERIFY can find uv/node/tools. path::wire persists
# this for future interactive shells; path::activate is the in-process equivalent
# (Ubuntu's ~/.bashrc early-returns for non-interactive shells, so it can't be relied on here).
path::activate() {
  export PATH="$HOME/.local/bin:$HOME/bin:$PATH"
  export NVM_DIR="$HOME/.nvm"
  # nvm can warn and exit non-zero when a user has a pre-existing .npmrc prefix;
  # we only need it to put node on PATH, so never let its exit code abort the
  # installer (this runs under `set -e`).
  if [ -s "$NVM_DIR/nvm.sh" ]; then
    # shellcheck disable=SC1091
    . "$NVM_DIR/nvm.sh" || true
  fi
  return 0
}
