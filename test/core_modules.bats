setup() {
  load test_helper
  cd "$REPO_ROOT"
  export GROUNDCREW_NO_COLOR=1
  export GROUNDCREW_STATE_DIR="$BATS_TEST_TMPDIR/state"
  # Fake apt-get/curl/uv/nvm on a stub PATH that logs invocations.
  STUB="$BATS_TEST_TMPDIR/bin"; mkdir -p "$STUB"
  for c in apt-get sudo curl uv pipx; do
    printf '#!/usr/bin/env bash\necho "%s $*" >> "%s/calls.log"\n' "$c" "$BATS_TEST_TMPDIR" > "$STUB/$c"
    chmod +x "$STUB/$c"
  done
  export PATH="$STUB:$PATH"
}

@test "base::install invokes apt-get and installs core packages" {
  run bash -c 'source lib/log.sh; source lib/guard.sh; source core/base.sh; base::install'
  [ "$status" -eq 0 ]
  grep -q 'apt-get' "$BATS_TEST_TMPDIR/calls.log"
  grep -q 'shellcheck' "$BATS_TEST_TMPDIR/calls.log"
  grep -q 'ripgrep' "$BATS_TEST_TMPDIR/calls.log"
}

@test "base::install is idempotent (second run is a no-op)" {
  bash -c 'source lib/log.sh; source lib/guard.sh; source core/base.sh; base::install'
  : > "$BATS_TEST_TMPDIR/calls.log"
  run bash -c 'source lib/log.sh; source lib/guard.sh; source core/base.sh; base::install'
  [ "$status" -eq 0 ]
  [ ! -s "$BATS_TEST_TMPDIR/calls.log" ]   # nothing invoked the second time
}

@test "python::install installs uv-based tooling" {
  run bash -c 'source lib/log.sh; source lib/guard.sh; source core/python.sh; python::install'
  [ "$status" -eq 0 ]
  grep -Eq 'uv|pipx' "$BATS_TEST_TMPDIR/calls.log"
}
