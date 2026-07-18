# shellcheck shell=bash
graphify::install() {
  guard::run_once core-graphify _graphify__do
}
_graphify__do() {
  log::step "Installing graphify"
  uv tool install graphify
  log::ok "graphify installed"
}
