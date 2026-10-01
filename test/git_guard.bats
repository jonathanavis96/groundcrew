setup() {
  load test_helper
  export REPO="$BATS_TEST_TMPDIR/repo"
  # Empty template: a host init.templateDir may pre-seed its own hooks.
  git init -q --template= "$REPO"
  mkdir -p "$REPO/.git/hooks"
  cp "$REPO_ROOT/payload/hooks/git-guard.sh" "$REPO/.git/hooks/pre-commit"
  chmod +x "$REPO/.git/hooks/pre-commit"
  git -C "$REPO" config user.email t@example.com
  git -C "$REPO" config user.name t
  git -C "$REPO" config commit.gpgsign false
  git -C "$REPO" commit -q --allow-empty -m init
}

@test "pre-commit blocks a staged .env" {
  echo SECRET=1 > "$REPO/.env"
  git -C "$REPO" add .env
  run git -C "$REPO" commit -q -m secret
  [ "$status" -ne 0 ]
  [[ "$output" == *"looks like a secret"* ]]
}

@test "pre-commit allows an ordinary file" {
  echo hi > "$REPO/notes.txt"
  git -C "$REPO" add notes.txt
  run git -C "$REPO" commit -q -m ok
  [ "$status" -eq 0 ]
}

@test "pre-commit blocks a secret staged as a rename" {
  echo SECRET=1 > "$REPO/notes.txt"
  git -C "$REPO" add notes.txt
  git -C "$REPO" commit -q -m notes
  git -C "$REPO" mv notes.txt .env
  run git -C "$REPO" commit -q -m rename
  [ "$status" -ne 0 ]
  [[ "$output" == *"looks like a secret"* ]]
}

@test "pre-commit blocks a secret under a non-ASCII directory" {
  mkdir -p "$REPO/café"
  echo SECRET=1 > "$REPO/café/.env"
  git -C "$REPO" add "café/.env"
  run git -C "$REPO" commit -q -m quoted
  [ "$status" -ne 0 ]
  [[ "$output" == *"looks like a secret"* ]]
}

@test "pre-commit blocks an ed25519 private key but not its .pub" {
  echo key > "$REPO/id_ed25519"
  echo pub > "$REPO/id_ed25519.pub"
  git -C "$REPO" add id_ed25519.pub
  run git -C "$REPO" commit -q -m pub
  [ "$status" -eq 0 ]
  git -C "$REPO" add id_ed25519
  run git -C "$REPO" commit -q -m key
  [ "$status" -ne 0 ]
  [[ "$output" == *"looks like a secret"* ]]
}
