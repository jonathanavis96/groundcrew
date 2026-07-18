# shellcheck shell=bash
graphify::install() {
  guard::run_once core-graphify _graphify__do
}
_graphify__do() {
  log::step "Installing graphify"
  # graphifyy provides the graphify + graphify-mcp commands
  uv tool install graphifyy || return 1
  log::ok "graphify installed"
}
