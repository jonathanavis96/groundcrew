#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=lib/log.sh
source "$HERE/lib/log.sh"

usage() {
  cat <<'EOF'
Usage: install.sh [options]
  --preset NAME    minimal | recommended | everything (default: recommended)
  --core-only      install core toolchain only (Phase 1)
  --module NAME    install a single optional module (see modules/): claude-kit | vault | playwright | docker | media
  --dry-run        print the plan without executing
  --help           show this help
EOF
}

# --preset / --core-only are parsed now but only affect agent/optional selection in Phase 2+
PRESET=recommended DRY=0 CORE_ONLY=0 MODULE=""
while (( $# )); do
  case "$1" in
    --preset) [[ $# -ge 2 ]] || { log::error "--preset requires a value"; usage; exit 64; }; PRESET="$2"; shift 2 ;;
    --core-only) CORE_ONLY=1; shift ;;
    --module) [[ $# -ge 2 ]] || { log::error "--module requires a value"; usage; exit 64; }; MODULE="$2"; shift 2 ;;
    --dry-run) DRY=1; shift ;;
    --help|-h) usage; exit 0 ;;
    *) log::error "unknown flag: $1"; usage; exit 64 ;;
  esac
done

# --module: install one optional component and exit. The friend's agent calls this
# per user pick after the core install (see the Agent Protocol in README.md).
if [[ -n "$MODULE" ]]; then
  mod_file="$HERE/modules/$MODULE.sh"
  [[ "$MODULE" =~ ^[a-z][a-z0-9-]*$ && -f "$mod_file" ]] || { log::error "unknown module: $MODULE (see: ls modules/)"; exit 64; }
  if (( DRY )); then
    log::step "Plan (module=$MODULE)"
    printf 'module: %s\n' "$MODULE"
    exit 0
  fi
  # shellcheck source=lib/guard.sh
  source "$HERE/lib/guard.sh"
  # shellcheck source=lib/detect.sh
  source "$HERE/lib/detect.sh"
  # shellcheck source=core/path.sh
  source "$HERE/core/path.sh"
  path::activate   # put core-installed node/uv on PATH for modules that need them
  # shellcheck disable=SC1090
  source "$mod_file"
  "${MODULE}::install"
  exit $?
fi

CORE_STEPS=(base python node graphify path)

if (( DRY )); then
  log::step "Plan (preset=$PRESET, core-only=$CORE_ONLY)"
  for s in "${CORE_STEPS[@]}"; do printf 'core: %s\n' "$s"; done
  exit 0
fi

# shellcheck source=lib/guard.sh
source "$HERE/lib/guard.sh"
# shellcheck source=lib/detect.sh
source "$HERE/lib/detect.sh"   # os::detect — the core modules branch on it, so source before running them
for m in base python node graphify path; do
  # shellcheck disable=SC1090
  source "$HERE/core/$m.sh"
done

log::step "Groundcrew — installing core toolchain"
base::install
python::install
node::install
path::activate
graphify::install
path::wire_shells

# shellcheck source=VERIFY.sh
source "$HERE/VERIFY.sh"
verify::run

log::ok "Core install complete. Run: exec bash   (to load PATH)"
