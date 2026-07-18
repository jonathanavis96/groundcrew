# shellcheck shell=bash
base::install() {
  guard::run_once core-base _base__do
}
_base__do() {
  log::step "Installing base toolchain"
  sudo apt-get update -y
  sudo apt-get install -y \
    git gh curl wget unzip ca-certificates build-essential pkg-config \
    jq sqlite3 shellcheck tmux ripgrep fzf fd-find bat
  mkdir -p "$HOME/.local/bin"
  # Ubuntu ships fd as fdfind and bat as batcat; give them their canonical names.
  [[ -e /usr/bin/fdfind ]] && ln -sf /usr/bin/fdfind "$HOME/.local/bin/fd"
  [[ -e /usr/bin/batcat ]] && ln -sf /usr/bin/batcat "$HOME/.local/bin/bat"
  log::ok "base toolchain installed"
}
