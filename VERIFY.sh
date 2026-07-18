# shellcheck shell=bash
: "${GROUNDCREW_VERIFY_PROBE:=}"

_verify__present() {
  if [[ -n "$GROUNDCREW_VERIFY_PROBE" ]]; then "$GROUNDCREW_VERIFY_PROBE" "$1";
  else command -v "$1" >/dev/null 2>&1; fi
}

verify::tool() {
  if _verify__present "$1"; then log::ok "$1"; return 0
  else log::error "$1 missing"; return 1; fi
}

verify::run() {
  local tools=(git jq rg fd bat fzf uv pipx ruff pyright node shellcheck tmux sqlite3 graphify)
  local missing=0 t
  log::step "Verifying Groundcrew environment"
  for t in "${tools[@]}"; do verify::tool "$t" || missing=$((missing+1)); done
  if declare -F detect::in_windows_mount >/dev/null && detect::in_windows_mount; then
    log::warn "You are under /mnt/ — keep projects in your Linux home (~) for speed + permissions"
  fi
  if (( missing > 0 )); then
    log::error "VERIFY FAILED — $missing tool(s) missing"
    return 1
  fi
  log::ok "VERIFY PASSED — core environment ready"
  log::info "Remaining manual steps: authenticate your agent; enable Obsidian 'Local REST API' if you chose the vault."
  return 0
}

# Allow running directly: `bash VERIFY.sh`
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  # shellcheck source=lib/log.sh
  source "$(dirname "$0")/lib/log.sh"
  # shellcheck source=lib/detect.sh
  source "$(dirname "$0")/lib/detect.sh"
  verify::run
fi
