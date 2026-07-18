# Shared bats helper: locate repo root and source a lib file.
REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
gc_source() { source "$REPO_ROOT/$1"; }
