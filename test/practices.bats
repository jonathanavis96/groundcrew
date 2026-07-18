setup() {
  load test_helper
  cd "$REPO_ROOT"
  export GROUNDCREW_NO_COLOR=1
  export GROUNDCREW_STATE_DIR="$BATS_TEST_TMPDIR/state"
  export GROUNDCREW_TARGET="$BATS_TEST_TMPDIR/target"
  mkdir -p "$GROUNDCREW_TARGET"
}

@test "practices::install drops AGENTS.md into an empty target" {
  run bash -c 'source lib/log.sh; source lib/guard.sh; source core/practices.sh; practices::install'
  [ "$status" -eq 0 ]
  [ -f "$GROUNDCREW_TARGET/AGENTS.md" ]
  grep -q "Agent Working Agreements" "$GROUNDCREW_TARGET/AGENTS.md"
}

@test "practices::install is idempotent and never overwrites an existing AGENTS.md" {
  printf 'SENTINEL: hand-edited, do not touch\n' > "$GROUNDCREW_TARGET/AGENTS.md"
  run bash -c 'source lib/log.sh; source lib/guard.sh; source core/practices.sh; practices::install'
  [ "$status" -eq 0 ]
  grep -q "SENTINEL: hand-edited, do not touch" "$GROUNDCREW_TARGET/AGENTS.md"
  ! grep -q "Agent Working Agreements" "$GROUNDCREW_TARGET/AGENTS.md"

  # Second run (guard already marked done) still must not touch it.
  run bash -c 'source lib/log.sh; source lib/guard.sh; source core/practices.sh; practices::install'
  [ "$status" -eq 0 ]
  grep -q "SENTINEL: hand-edited, do not touch" "$GROUNDCREW_TARGET/AGENTS.md"
}

@test "practices::install writes the guard marker on success" {
  run bash -c 'source lib/log.sh; source lib/guard.sh; source core/practices.sh; practices::install'
  [ "$status" -eq 0 ]
  [ -f "$GROUNDCREW_STATE_DIR/core-practices" ]
}

@test "practices::install skips the guard marker on failure" {
  # Point at a target whose AGENTS.md destination can't be written, so the
  # cp inside _practices__install_agents_md fails and the guard marker is
  # never created.
  chmod a-w "$GROUNDCREW_TARGET"
  run bash -c 'source lib/log.sh; source lib/guard.sh; source core/practices.sh; practices::install'
  chmod u+w "$GROUNDCREW_TARGET"
  [ "$status" -ne 0 ]
  [ ! -f "$GROUNDCREW_STATE_DIR/core-practices" ]
}

@test "practices::install installs an executable pre-push hook when target is a git repo" {
  git -C "$GROUNDCREW_TARGET" init -q
  run bash -c 'source lib/log.sh; source lib/guard.sh; source core/practices.sh; practices::install'
  [ "$status" -eq 0 ]
  [ -x "$GROUNDCREW_TARGET/.git/hooks/pre-push" ]
  grep -q "git-guard" "$GROUNDCREW_TARGET/.git/hooks/pre-push"
}

@test "practices::install skips the git hook when target is not a git repo" {
  run bash -c 'source lib/log.sh; source lib/guard.sh; source core/practices.sh; practices::install'
  [ "$status" -eq 0 ]
  [ ! -e "$GROUNDCREW_TARGET/.git" ]
}
