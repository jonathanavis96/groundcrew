setup() { load test_helper; cd "$REPO_ROOT"; export GROUNDCREW_NO_COLOR=1; }

@test "install --dry-run lists the core steps in order" {
  run bash -c 'cd '"$REPO_ROOT"' && bash install.sh --dry-run --core-only'
  [ "$status" -eq 0 ]
  [[ "$output" == *"base"* ]]
  [[ "$output" == *"python"* ]]
  [[ "$output" == *"node"* ]]
  [[ "$output" == *"graphify"* ]]
  [[ "$output" == *"path"* ]]
  # order: base before node
  [[ "$output" == *"base"*"node"* ]]
}

@test "install --help exits 0 and shows usage" {
  run bash -c 'cd '"$REPO_ROOT"' && bash install.sh --help'
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage"* ]]
}

@test "unknown flag exits non-zero" {
  run bash -c 'cd '"$REPO_ROOT"' && bash install.sh --bogus'
  [ "$status" -ne 0 ]
}

@test "--preset with no value exits 64, not an unbound-variable crash" {
  run bash -c 'cd '"$REPO_ROOT"' && bash install.sh --preset'
  [ "$status" -eq 64 ]
  [[ "$output" != *"unbound variable"* ]]
}
