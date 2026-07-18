# Shared bats helper: locate repo root (tests cd here in setup).
REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
