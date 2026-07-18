# shellcheck shell=bash
node::install() {
  guard::run_once core-node _node__do
}
_node__do() {
  log::step "Installing Node 20 via nvm"
  export NVM_DIR="$HOME/.nvm"
  if [[ ! -s "$NVM_DIR/nvm.sh" ]]; then
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash || return 1
  fi
  # shellcheck disable=SC1091
  . "$NVM_DIR/nvm.sh"
  nvm install 20 || return 1
  nvm alias default 20 || return 1
  log::ok "node 20 installed"
}
