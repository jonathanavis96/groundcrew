# shellcheck shell=bash
: "${GROUNDCREW_PATH_PROBE:=}"

_detect__has() {
  if [[ -n "$GROUNDCREW_PATH_PROBE" ]]; then
    "$GROUNDCREW_PATH_PROBE" "$1"
  else
    command -v "$1" >/dev/null 2>&1
  fi
}

detect::agents() {
  _detect__has claude   && echo claude-code
  _detect__has opencode && echo opencode
  _detect__has codex    && echo codex
  _detect__has gemini   && echo gemini
  return 0
}

detect::in_windows_mount() { [[ "$PWD" == /mnt/* ]]; }

detect::is_wsl() { grep -qi microsoft /proc/version 2>/dev/null; }
