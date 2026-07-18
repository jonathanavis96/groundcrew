# shellcheck shell=bash
base::install() {
  guard::run_once core-base _base__do
}
_base__do() {
  log::step "Installing base toolchain"
  case "$(os::detect)" in
    macos) _base__macos || return 1 ;;
    linux) _base__linux || return 1 ;;
    *) log::error "unsupported OS for base toolchain (need macOS or Linux)"; return 1 ;;
  esac
  log::ok "base toolchain installed"
}
_base__linux() {
  sudo apt-get update -y || return 1
  sudo apt-get install -y \
    git gh curl wget unzip ca-certificates build-essential pkg-config \
    jq sqlite3 shellcheck tmux ripgrep fzf fd-find bat || return 1
  mkdir -p "$HOME/.local/bin"
  # Ubuntu ships fd as fdfind and bat as batcat; give them their canonical names.
  if [[ -e /usr/bin/fdfind ]]; then ln -sf /usr/bin/fdfind "$HOME/.local/bin/fd"; fi
  if [[ -e /usr/bin/batcat ]]; then ln -sf /usr/bin/batcat "$HOME/.local/bin/bat"; fi
  return 0
}
_base__macos() {
  # Xcode Command Line Tools already provide curl, unzip, git and a compiler;
  # Homebrew names fd and bat canonically, so no symlinks are needed here.
  brew install \
    git gh wget pkg-config jq sqlite shellcheck tmux ripgrep fzf fd bat || return 1
  return 0
}
