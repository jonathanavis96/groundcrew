setup() { load test_helper; cd "$REPO_ROOT"; export GROUNDCREW_NO_COLOR=1; RC="$BATS_TEST_TMPDIR/bashrc"; : > "$RC"; }

@test "wire adds the groundcrew block once" {
  bash -c 'source lib/log.sh; source core/path.sh; path::wire '"$RC"
  count=$(grep -c '>>> groundcrew path >>>' "$RC")
  [ "$count" -eq 1 ]
  grep -q '.local/bin' "$RC"
  grep -q 'HOME/bin' "$RC"
}

@test "wire is idempotent across repeated runs" {
  for _ in 1 2 3; do bash -c 'source lib/log.sh; source core/path.sh; path::wire '"$RC"; done
  count=$(grep -c '>>> groundcrew path >>>' "$RC")
  [ "$count" -eq 1 ]
}

@test "wire preserves pre-existing rc content" {
  echo 'export FOO=bar' > "$RC"
  bash -c 'source lib/log.sh; source core/path.sh; path::wire '"$RC"
  grep -q 'export FOO=bar' "$RC"
}

@test "activate puts .local/bin on PATH in-process" {
  run bash -c 'source lib/log.sh; source core/path.sh; path::activate; echo "$PATH"'
  [ "$status" -eq 0 ]
  [[ "$output" == *"$HOME/.local/bin"* ]]
}

@test "activate survives an nvm.sh that exits non-zero (set -e safe)" {
  H="$BATS_TEST_TMPDIR/home"; mkdir -p "$H/.nvm"
  # A fake nvm that emits a warning and returns non-zero (like a .npmrc prefix clash).
  printf 'echo "nvm warning" >&2\nfalse\n' > "$H/.nvm/nvm.sh"
  run env HOME="$H" bash -c 'set -euo pipefail; source lib/log.sh; source core/path.sh; path::activate; echo REACHED_END'
  [ "$status" -eq 0 ]
  [[ "$output" == *"REACHED_END"* ]]
}

@test "wire_shells wires ~/.bashrc on linux only" {
  H="$BATS_TEST_TMPDIR/home"; mkdir -p "$H"
  run env HOME="$H" GROUNDCREW_OS=linux bash -c 'source lib/log.sh; source lib/detect.sh; source core/path.sh; path::wire_shells'
  [ "$status" -eq 0 ]
  grep -q '>>> groundcrew path >>>' "$H/.bashrc"
  [ ! -f "$H/.zshrc" ]
}

@test "wire_shells also wires ~/.zshrc on macos" {
  H="$BATS_TEST_TMPDIR/home"; mkdir -p "$H"
  run env HOME="$H" GROUNDCREW_OS=macos bash -c 'source lib/log.sh; source lib/detect.sh; source core/path.sh; path::wire_shells'
  [ "$status" -eq 0 ]
  grep -q '>>> groundcrew path >>>' "$H/.bashrc"
  grep -q '>>> groundcrew path >>>' "$H/.zshrc"
}
