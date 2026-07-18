setup() { load test_helper; cd "$REPO_ROOT"; export GROUNDCREW_NO_COLOR=1; }

@test "verify::tool passes for an existing tool" {
  run bash -c 'source lib/log.sh; source VERIFY.sh; verify::tool bash'
  [ "$status" -eq 0 ]
}

@test "verify::run fails when a required tool is missing" {
  # Probe reports everything missing.
  run bash -c 'source lib/log.sh; source lib/detect.sh; source VERIFY.sh;
    GROUNDCREW_VERIFY_PROBE="false" verify::run'
  [ "$status" -ne 0 ]
  [[ "$output" == *"✗"* ]]   # summary printed to stderr (bats merges into $output)
}

@test "verify::run passes when probe reports all present" {
  run bash -c 'source lib/log.sh; source lib/detect.sh; source VERIFY.sh;
    GROUNDCREW_VERIFY_PROBE="true" verify::run'
  [ "$status" -eq 0 ]
}
