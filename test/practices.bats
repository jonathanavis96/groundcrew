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

@test "practices::install installs executable pre-push AND pre-commit guard hooks" {
  git -C "$GROUNDCREW_TARGET" init -q --template=  # empty template: a host init.templateDir may pre-seed hooks
  run bash -c 'source lib/log.sh; source lib/guard.sh; source core/practices.sh; practices::install'
  [ "$status" -eq 0 ]
  [ -x "$GROUNDCREW_TARGET/.git/hooks/pre-push" ]
  [ -x "$GROUNDCREW_TARGET/.git/hooks/pre-commit" ]
  grep -q "git-guard" "$GROUNDCREW_TARGET/.git/hooks/pre-push"
  grep -q "git-guard" "$GROUNDCREW_TARGET/.git/hooks/pre-commit"
}

@test "practices::install does not clobber a hook the project already has" {
  git -C "$GROUNDCREW_TARGET" init -q --template=  # empty template: a host init.templateDir may pre-seed hooks
  mkdir -p "$GROUNDCREW_TARGET/.git/hooks"
  printf '#!/bin/sh\necho existing-husky-hook\n' > "$GROUNDCREW_TARGET/.git/hooks/pre-push"
  run bash -c 'source lib/log.sh; source lib/guard.sh; source core/practices.sh; practices::install'
  [ "$status" -eq 0 ]
  # Existing pre-push is preserved, not overwritten by the guard.
  grep -q "existing-husky-hook" "$GROUNDCREW_TARGET/.git/hooks/pre-push"
  ! grep -q "git-guard" "$GROUNDCREW_TARGET/.git/hooks/pre-push"
  # The free pre-commit slot still gets the guard.
  grep -q "git-guard" "$GROUNDCREW_TARGET/.git/hooks/pre-commit"
}

@test "practices::install skips the git hook when target is not a git repo" {
  run bash -c 'source lib/log.sh; source lib/guard.sh; source core/practices.sh; practices::install'
  [ "$status" -eq 0 ]
  [ ! -e "$GROUNDCREW_TARGET/.git" ]
}

@test "practices::install installs the guard hooks into a git worktree (.git is a file)" {
  main="$BATS_TEST_TMPDIR/main"
  git init -q "$main"
  git -C "$main" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
  rmdir "$GROUNDCREW_TARGET"
  git -C "$main" worktree add -q "$GROUNDCREW_TARGET"
  [ -f "$GROUNDCREW_TARGET/.git" ]
  run bash -c 'source lib/log.sh; source lib/guard.sh; source core/practices.sh; practices::install'
  [ "$status" -eq 0 ]
  hooks="$(git -C "$GROUNDCREW_TARGET" rev-parse --path-format=absolute --git-common-dir)/hooks"
  grep -q "git-guard" "$hooks/pre-push"
  grep -q "git-guard" "$hooks/pre-commit"
}

@test "practices::install leaves a dangling AGENTS.md symlink alone instead of writing through it" {
  ln -s "$BATS_TEST_TMPDIR/elsewhere.md" "$GROUNDCREW_TARGET/AGENTS.md"
  run bash -c 'source lib/log.sh; source lib/guard.sh; source core/practices.sh; practices::install'
  [ "$status" -eq 0 ]
  [ -L "$GROUNDCREW_TARGET/AGENTS.md" ]
  [ ! -e "$BATS_TEST_TMPDIR/elsewhere.md" ]
}

@test "practices::install never falls through a broken .git to a parent repo's hooks" {
  parent="$BATS_TEST_TMPDIR/parent"
  git init -q "$parent"
  export GROUNDCREW_TARGET="$parent/sub"
  mkdir -p "$GROUNDCREW_TARGET/.git"
  run bash -c 'source lib/log.sh; source lib/guard.sh; source core/practices.sh; practices::install'
  [ "$status" -eq 0 ]
  [ ! -e "$parent/.git/hooks/pre-push" ]
  [ ! -e "$parent/.git/hooks/pre-commit" ]
}
