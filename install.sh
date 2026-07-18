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
  --dry-run        print the plan without executing
  --help           show this help
EOF
}

PRESET=recommended DRY=0 CORE_ONLY=0
while (( $# )); do
  case "$1" in
    --preset) PRESET="$2"; shift 2 ;;
    --core-only) CORE_ONLY=1; shift ;;
    --dry-run) DRY=1; shift ;;
    --help|-h) usage; exit 0 ;;
    *) log::error "unknown flag: $1"; usage; exit 64 ;;
  esac
done

CORE_STEPS=(base python node graphify path)

if (( DRY )); then
  log::step "Plan (preset=$PRESET, core-only=$CORE_ONLY)"
  for s in "${CORE_STEPS[@]}"; do printf 'core: %s\n' "$s"; done
  exit 0
fi

# shellcheck source=lib/guard.sh
source "$HERE/lib/guard.sh"
for m in base python node graphify path; do
  # shellcheck disable=SC1090
  source "$HERE/core/$m.sh"
done

log::step "Groundcrew — installing core toolchain"
base::install
python::install
node::install
graphify::install
path::wire

# shellcheck source=lib/detect.sh
source "$HERE/lib/detect.sh"
# shellcheck source=VERIFY.sh
source "$HERE/VERIFY.sh"
verify::run

log::ok "Core install complete. Run: exec bash   (to load PATH)"
