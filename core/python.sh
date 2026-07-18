# shellcheck shell=bash
python::install() {
  guard::run_once core-python _python__do
}
_python__do() {
  log::step "Installing Python toolchain"
  sudo apt-get install -y python3 python3-pip python3-venv pipx
  pipx ensurepath || true
  curl -LsSf https://astral.sh/uv/install.sh | sh
  # ruff + pyright as isolated tools
  pipx install ruff || true
  pipx install pyright || true
  log::ok "python toolchain installed"
}
