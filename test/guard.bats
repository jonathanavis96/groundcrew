setup() {
  load test_helper
  cd "$REPO_ROOT"
  export GROUNDCREW_NO_COLOR=1
  export GROUNDCREW_STATE_DIR="$BATS_TEST_TMPDIR/state"
}

@test "has_cmd finds an existing command" {
  run bash -c 'source lib/log.sh; source lib/guard.sh; guard::has_cmd bash'
  [ "$status" -eq 0 ]
}

@test "has_cmd fails on a missing command" {
  run bash -c 'source lib/log.sh; source lib/guard.sh; guard::has_cmd definitely-not-real-xyz'
  [ "$status" -eq 1 ]
}

@test "run_once executes the command the first time" {
  run bash -c 'source lib/log.sh; source lib/guard.sh; guard::run_once mykey touch '"$BATS_TEST_TMPDIR"'/made'
  [ "$status" -eq 0 ]
  [ -f "$BATS_TEST_TMPDIR/made" ]
}

@test "run_once skips the command the second time" {
  bash -c 'source lib/log.sh; source lib/guard.sh; guard::run_once k touch '"$BATS_TEST_TMPDIR"'/first'
  rm -f "$BATS_TEST_TMPDIR/first"
  run bash -c 'source lib/log.sh; source lib/guard.sh; guard::run_once k touch '"$BATS_TEST_TMPDIR"'/first'
  [ "$status" -eq 0 ]
  [ ! -f "$BATS_TEST_TMPDIR/first" ]   # command did NOT run again
}

@test "run_once does not mark on command failure" {
  run bash -c 'source lib/log.sh; source lib/guard.sh; guard::run_once failkey false'
  [ "$status" -ne 0 ]
  [ ! -f "$GROUNDCREW_STATE_DIR/failkey" ]
}
