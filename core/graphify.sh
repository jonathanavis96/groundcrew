# shellcheck shell=bash
graphify::install() {
  guard::run_once core-graphify _graphify__do
}
_graphify__do() {
  log::step "Installing graphify"
  # graphifyy[mcp] provides the graphify CLI + a runnable graphify-mcp server.
  # The mcp extra pulls in mcp + starlette; without it the graphify-mcp entry
  # point exists but ImportErrors at runtime. Installing it here (not later)
  # keeps the core-graphify marker honest — a plain install would let the marker
  # block a future re-run that needs the MCP deps.
  uv tool install "graphifyy[mcp]" || return 1
  log::ok "graphify installed"
}
