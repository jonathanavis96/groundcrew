# shellcheck shell=bash
python::install() {
  guard::run_once core-python _python__do
}
_python__do() {
  log::step "Installing Python toolchain"
  sudo apt-get install -y python3 python3-pip python3-venv pipx || return 1
  pipx ensurepath || true
  curl -LsSf https://astral.sh/uv/install.sh | sh || return 1
  # ruff + pyright as isolated tools
  _python__pipx_tool ruff || return 1
  _python__pipx_tool pyright || return 1
  log::ok "python toolchain installed"
}
# Install a pipx tool idempotently and confirm its binary landed.
# command -v can't verify here: pipx's bin dir isn't on PATH within this run,
# so probe the install location directly.
_python__pipx_tool() {
  local tool="$1"
  local bin_dir="${PIPX_BIN_DIR:-$HOME/.local/bin}"
  [[ -x "$bin_dir/$tool" ]] && return 0
  pipx install "$tool" || return 1
  [[ -x "$bin_dir/$tool" ]] || return 1
}
