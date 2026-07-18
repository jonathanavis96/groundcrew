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

@test "os::detect reports macos/linux and honours the override" {
  run bash -c 'source lib/detect.sh; GROUNDCREW_OS=macos os::detect'
  [ "$status" -eq 0 ]
  [ "$output" = "macos" ]
  run bash -c 'source lib/detect.sh; GROUNDCREW_OS=linux os::detect'
  [ "$output" = "linux" ]
  # No override: falls back to uname and must be one of the known families.
  run bash -c 'source lib/detect.sh; os::detect'
  [[ "$output" == "macos" || "$output" == "linux" || "$output" == "unknown" ]]
}
