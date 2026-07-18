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
