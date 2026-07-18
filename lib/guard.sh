# shellcheck shell=bash
: "${GROUNDCREW_STATE_DIR:=$HOME/.groundcrew/state}"

guard::has_cmd() { command -v "$1" >/dev/null 2>&1; }

# guard::run_once KEY CMD...
guard::run_once() {
  local key="$1"; shift
  local marker="$GROUNDCREW_STATE_DIR/$key"
  if [[ -f "$marker" ]]; then
    log::info "skip $key (already done)"
    return 0
  fi
  "$@" || return $?
  mkdir -p "$GROUNDCREW_STATE_DIR"
  : > "$marker"
}
