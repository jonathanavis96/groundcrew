# shellcheck shell=bash
playwright::install() {
  guard::run_once optional-playwright _playwright__do
}
_playwright__do() {
  log::step "Installing Playwright"
  if ! guard::has_cmd node || ! guard::has_cmd npm || ! guard::has_cmd npx; then
    log::error "node/npm/npx not found — install the core node toolchain first"
    return 1
  fi
  # No sudo, no -g against a system prefix: node comes from nvm, so npm's
  # global prefix already lives under the user's home directory.
  npm install -g playwright || return 1
  # Downloads the Chromium/Firefox/WebKit browser binaries into the user cache.
  npx --yes playwright install || return 1
  log::ok "playwright installed"
}
