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

# pre-push fixture: a bare remote plus two clones, so one clone can be left
# stale while the other moves main forward.
_guard_prepush_setup() {
  export ORIGIN="$BATS_TEST_TMPDIR/origin.git"
  git init -q --bare --template= "$ORIGIN"
  git --git-dir="$ORIGIN" symbolic-ref HEAD refs/heads/main
  git -C "$REPO" branch -M main
  git -C "$REPO" remote add origin "$ORIGIN"
  git -C "$REPO" push -q origin main
  cp "$REPO_ROOT/payload/hooks/git-guard.sh" "$REPO/.git/hooks/pre-push"
  chmod +x "$REPO/.git/hooks/pre-push"
  export OTHER="$BATS_TEST_TMPDIR/other"
  git clone -q --template= "$ORIGIN" "$OTHER"
  git -C "$OTHER" config user.email o@example.com
  git -C "$OTHER" config user.name o
  git -C "$OTHER" config commit.gpgsign false
}

@test "pre-push allows a fast-forward push to main" {
  _guard_prepush_setup
  git -C "$REPO" commit -q --allow-empty -m next
  run git -C "$REPO" push -q origin main
  [ "$status" -eq 0 ]
}

@test "pre-push blocks a force-push to main over fetched remote commits" {
  _guard_prepush_setup
  git -C "$OTHER" commit -q --allow-empty -m theirs
  git -C "$OTHER" push -q origin main
  git -C "$REPO" fetch -q origin
  git -C "$REPO" commit -q --allow-empty -m mine
  run git -C "$REPO" push -q --force origin main
  [ "$status" -ne 0 ]
  [[ "$output" == *"non-fast-forward"* ]]
}

@test "pre-push blocks a force-push to main over remote commits never fetched" {
  _guard_prepush_setup
  git -C "$OTHER" commit -q --allow-empty -m theirs
  git -C "$OTHER" push -q origin main
  # No fetch: the remote tip is not in this clone's object store at all.
  git -C "$REPO" commit -q --allow-empty -m mine
  run git -C "$REPO" push -q --force origin main
  [ "$status" -ne 0 ]
  [[ "$output" == *"non-fast-forward"* ]]
  [ "$(git -C "$OTHER" rev-parse HEAD)" = "$(git --git-dir="$ORIGIN" rev-parse main)" ]
}

@test "pre-commit blocks secret names regardless of case" {
  echo SECRET=1 > "$REPO/.ENV"
  git -C "$REPO" add .ENV
  run git -C "$REPO" commit -q -m upper
  [ "$status" -ne 0 ]
  [[ "$output" == *"looks like a secret"* ]]
  git -C "$REPO" rm -q --cached .ENV
  echo '{}' > "$REPO/Credentials.json"
  git -C "$REPO" add Credentials.json
  run git -C "$REPO" commit -q -m creds
  [ "$status" -ne 0 ]
  [[ "$output" == *"looks like a secret"* ]]
}
