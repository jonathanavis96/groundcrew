setup() { load test_helper; export GROUNDCREW_NO_COLOR=1; }

@test "log::info writes prefixed message to stderr" {
  run bash -c 'source lib/log.sh; log::info "hello"' 2>&1
  [ "$status" -eq 0 ]
  [[ "$output" == *"hello"* ]]
}

@test "log::error is prefixed distinctly from info" {
  info=$(bash -c 'GROUNDCREW_NO_COLOR=1 source lib/log.sh; log::info x' 2>&1)
  err=$(bash -c 'GROUNDCREW_NO_COLOR=1 source lib/log.sh; log::error x' 2>&1)
  [ "$info" != "$err" ]
}

@test "no-color mode emits no ANSI escapes" {
  out=$(bash -c 'GROUNDCREW_NO_COLOR=1 source lib/log.sh; log::ok done' 2>&1)
  [[ "$out" != *$'\e['* ]]
}
