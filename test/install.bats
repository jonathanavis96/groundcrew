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

@test "--module with no value exits 64" {
  run bash -c 'cd '"$REPO_ROOT"' && bash install.sh --module'
  [ "$status" -eq 64 ]
  [[ "$output" != *"unbound variable"* ]]
}

@test "--module with an unknown name exits 64" {
  run bash -c 'cd '"$REPO_ROOT"' && bash install.sh --module nope-not-real'
  [ "$status" -eq 64 ]
  [[ "$output" == *"unknown module"* ]]
}

@test "--module rejects a path-shaped name instead of sourcing it" {
  run bash -c 'cd '"$REPO_ROOT"' && bash install.sh --module ../lib/log'
  [ "$status" -eq 64 ]
  [[ "$output" == *"unknown module"* ]]
}

@test "--module with --dry-run prints the plan and does not install" {
  run bash -c 'cd '"$REPO_ROOT"' && bash install.sh --module docker --dry-run'
  [ "$status" -eq 0 ]
  [[ "$output" == *"module: docker"* ]]
}
