setup() { load test_helper; cd "$REPO_ROOT"; export GROUNDCREW_NO_COLOR=1; }

@test "in_windows_mount true under /mnt" {
  run bash -c 'source lib/detect.sh; cd /mnt 2>/dev/null || mkdir -p '"$BATS_TEST_TMPDIR"'/mnt/x; PWD=/mnt/c/foo detect::in_windows_mount'
  [ "$status" -eq 0 ]
}

@test "in_windows_mount false under home" {
  run bash -c 'source lib/detect.sh; PWD=/home/u/proj detect::in_windows_mount'
  [ "$status" -eq 1 ]
}

@test "agents lists claude when probe says claude exists" {
  run bash -c 'source lib/log.sh; source lib/detect.sh;
    GROUNDCREW_PATH_PROBE="test/fixtures/probe.sh" detect::agents'
  [ "$status" -eq 0 ]
  [[ "$output" == *"claude-code"* ]]
  [[ "$output" != *"gemini"* ]]
}
