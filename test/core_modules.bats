setup() {
  load test_helper
  cd "$REPO_ROOT"
  export GROUNDCREW_NO_COLOR=1
  export GROUNDCREW_STATE_DIR="$BATS_TEST_TMPDIR/state"
  # Default the OS to linux; macOS-branch tests override GROUNDCREW_OS inline.
  export GROUNDCREW_OS=linux
  # Fake the package managers on a stub PATH that logs invocations.
  STUB="$BATS_TEST_TMPDIR/bin"; mkdir -p "$STUB"
  for c in apt-get sudo curl uv brew; do
    printf '#!/usr/bin/env bash\necho "%s $*" >> "%s/calls.log"\n' "$c" "$BATS_TEST_TMPDIR" > "$STUB/$c"
    chmod +x "$STUB/$c"
  done
  # pipx stub: log, and on `install <tool>` materialise the binary so
  # _python__pipx_tool's post-install check passes hermetically (independent of
  # the runner's real HOME / ~/.local/bin).
  export PIPX_BIN_DIR="$BATS_TEST_TMPDIR/pipxbin"; mkdir -p "$PIPX_BIN_DIR"
  printf '#!/usr/bin/env bash\necho "pipx $*" >> "%s/calls.log"\nif [ "$1" = install ]; then : > "%s/$2"; chmod +x "%s/$2"; fi\nexit 0\n' \
    "$BATS_TEST_TMPDIR" "$PIPX_BIN_DIR" "$PIPX_BIN_DIR" > "$STUB/pipx"
  chmod +x "$STUB/pipx"
  export PATH="$STUB:$PATH"
}

@test "base::install (linux) invokes apt-get and installs core packages" {
  run bash -c 'source lib/log.sh; source lib/guard.sh; source lib/detect.sh; source core/base.sh; base::install'
  [ "$status" -eq 0 ]
  grep -q 'apt-get' "$BATS_TEST_TMPDIR/calls.log"
  grep -q 'shellcheck' "$BATS_TEST_TMPDIR/calls.log"
  grep -q 'ripgrep' "$BATS_TEST_TMPDIR/calls.log"
}

@test "base::install (macos) invokes brew, not apt-get" {
  run bash -c 'GROUNDCREW_OS=macos; source lib/log.sh; source lib/guard.sh; source lib/detect.sh; source core/base.sh; base::install'
  [ "$status" -eq 0 ]
  grep -q 'brew install' "$BATS_TEST_TMPDIR/calls.log"
  grep -q 'ripgrep' "$BATS_TEST_TMPDIR/calls.log"
  ! grep -q 'apt-get' "$BATS_TEST_TMPDIR/calls.log"
}

@test "base::install is idempotent (second run is a no-op)" {
  bash -c 'source lib/log.sh; source lib/guard.sh; source lib/detect.sh; source core/base.sh; base::install'
  : > "$BATS_TEST_TMPDIR/calls.log"
  run bash -c 'source lib/log.sh; source lib/guard.sh; source lib/detect.sh; source core/base.sh; base::install'
  [ "$status" -eq 0 ]
  [ ! -s "$BATS_TEST_TMPDIR/calls.log" ]   # nothing invoked the second time
}

@test "python::install (linux) installs uv-based tooling" {
  run bash -c 'source lib/log.sh; source lib/guard.sh; source lib/detect.sh; source core/python.sh; python::install'
  [ "$status" -eq 0 ]
  grep -Eq 'uv|pipx' "$BATS_TEST_TMPDIR/calls.log"
}

@test "python::install (macos) uses brew for python and pipx" {
  run bash -c 'GROUNDCREW_OS=macos; source lib/log.sh; source lib/guard.sh; source lib/detect.sh; source core/python.sh; python::install'
  [ "$status" -eq 0 ]
  grep -q 'brew install python pipx' "$BATS_TEST_TMPDIR/calls.log"
}

@test "base::install fails and does not write the done marker when apt-get fails" {
  printf '#!/usr/bin/env bash\necho "sudo $*" >> "%s/calls.log"\nexit 1\n' "$BATS_TEST_TMPDIR" > "$STUB/sudo"
  chmod +x "$STUB/sudo"
  run bash -c 'source lib/log.sh; source lib/guard.sh; source lib/detect.sh; source core/base.sh; base::install'
  [ "$status" -ne 0 ]
  [ ! -f "$GROUNDCREW_STATE_DIR/core-base" ]
}
