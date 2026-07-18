setup() {
  load test_helper
  cd "$REPO_ROOT"
  export GROUNDCREW_NO_COLOR=1
  export GROUNDCREW_STATE_DIR="$BATS_TEST_TMPDIR/state"
  # Fake apt-get/sudo/brew/npm/npx/uv/pipx/node on a stub PATH that logs invocations.
  STUB="$BATS_TEST_TMPDIR/bin"; mkdir -p "$STUB"
  for c in apt-get sudo brew npm npx uv pipx node; do
    printf '#!/usr/bin/env bash\necho "%s $*" >> "%s/calls.log"\n' "$c" "$BATS_TEST_TMPDIR" > "$STUB/$c"
    chmod +x "$STUB/$c"
  done
  export PATH="$STUB:$PATH"
  # Absolute path to the real bash, used when a test needs a PATH restricted
  # to just $STUB (no fallthrough to the host's real node/uv/pipx) so that
  # "tool is absent" tests stay hermetic on machines that already have them.
  REAL_BASH="$(command -v bash)"
  # The stub scripts above shebang `#!/usr/bin/env bash`; under a PATH
  # restricted to $STUB, env needs a `bash` to find too. Same for the handful
  # of coreutils guard.sh/modules rely on (e.g. guard::run_once's mkdir) —
  # none of these names collide with the tools under test, so symlinking the
  # real binaries in is safe and keeps the sandbox otherwise hermetic.
  ln -sf "$REAL_BASH" "$STUB/bash"
  for c in mkdir cat rm chmod ln mv cp grep; do
    ln -sf "$(command -v "$c")" "$STUB/$c"
  done
}

# --- vault -------------------------------------------------------------

@test "vault::install creates the vault dir, .obsidian, and starter notes" {
  export GROUNDCREW_VAULT_DIR="$BATS_TEST_TMPDIR/vault"
  run bash -c 'source lib/log.sh; source lib/guard.sh; source modules/vault.sh; vault::install'
  [ "$status" -eq 0 ]
  [ -d "$GROUNDCREW_VAULT_DIR/.obsidian" ]
  [ -f "$GROUNDCREW_VAULT_DIR/Welcome.md" ]
  [ -f "$GROUNDCREW_VAULT_DIR/Ideas Inbox.md" ]
  [ -f "$GROUNDCREW_STATE_DIR/optional-vault" ]
}

@test "vault::install skips an already-existing vault dir without touching it" {
  export GROUNDCREW_VAULT_DIR="$BATS_TEST_TMPDIR/vault"
  mkdir -p "$GROUNDCREW_VAULT_DIR"
  echo "pre-existing note" > "$GROUNDCREW_VAULT_DIR/Welcome.md"
  run bash -c 'source lib/log.sh; source lib/guard.sh; source modules/vault.sh; vault::install'
  [ "$status" -eq 0 ]
  [ "$(cat "$GROUNDCREW_VAULT_DIR/Welcome.md")" = "pre-existing note" ]
  [ ! -d "$GROUNDCREW_VAULT_DIR/.obsidian" ]
  [ -f "$GROUNDCREW_STATE_DIR/optional-vault" ]
}

@test "vault::install second run is a no-op" {
  export GROUNDCREW_VAULT_DIR="$BATS_TEST_TMPDIR/vault"
  bash -c 'source lib/log.sh; source lib/guard.sh; source modules/vault.sh; vault::install'
  echo "user edit" >> "$GROUNDCREW_VAULT_DIR/Welcome.md"
  run bash -c 'source lib/log.sh; source lib/guard.sh; source modules/vault.sh; vault::install'
  [ "$status" -eq 0 ]
  grep -q "user edit" "$GROUNDCREW_VAULT_DIR/Welcome.md"
}

# --- playwright ----------------------------------------------------------

@test "playwright::install runs npm and npx when the node toolchain is present" {
  run bash -c 'source lib/log.sh; source lib/guard.sh; source modules/playwright.sh; playwright::install'
  [ "$status" -eq 0 ]
  grep -q 'npm install -g playwright' "$BATS_TEST_TMPDIR/calls.log"
  grep -q 'npx --yes playwright install' "$BATS_TEST_TMPDIR/calls.log"
  [ -f "$GROUNDCREW_STATE_DIR/optional-playwright" ]
}

@test "playwright::install errors and writes no marker when node is absent" {
  rm -f "$STUB/node"
  # PATH restricted to $STUB only: the host may have a real node/nvm install,
  # and letting that leak in would defeat this absence test.
  run env PATH="$STUB" "$REAL_BASH" -c 'source lib/log.sh; source lib/guard.sh; source modules/playwright.sh; playwright::install'
  [ "$status" -ne 0 ]
  [ ! -f "$GROUNDCREW_STATE_DIR/optional-playwright" ]
}

# --- docker --------------------------------------------------------------

@test "docker::install (linux) installs docker.io via apt-get and adds the user to the docker group" {
  run bash -c 'source lib/log.sh; source lib/guard.sh; source lib/detect.sh; source modules/docker.sh; GROUNDCREW_OS=linux docker::install'
  [ "$status" -eq 0 ]
  grep -q 'apt-get install -y docker.io' "$BATS_TEST_TMPDIR/calls.log"
  grep -q 'sudo usermod -aG docker' "$BATS_TEST_TMPDIR/calls.log"
  [ -f "$GROUNDCREW_STATE_DIR/optional-docker" ]
}

@test "docker::install (macos) installs the Docker Desktop cask via brew" {
  run bash -c 'source lib/log.sh; source lib/guard.sh; source lib/detect.sh; source modules/docker.sh; GROUNDCREW_OS=macos docker::install'
  [ "$status" -eq 0 ]
  grep -q 'brew install --cask docker' "$BATS_TEST_TMPDIR/calls.log"
  [ -f "$GROUNDCREW_STATE_DIR/optional-docker" ]
}

@test "docker::install fails and does not write the marker when apt-get fails" {
  # docker.sh runs everything through `sudo`, so the stub that must fail here
  # is sudo itself (the stub apt-get is never actually exec'd).
  printf '#!/usr/bin/env bash\necho "sudo $*" >> "%s/calls.log"\nexit 1\n' "$BATS_TEST_TMPDIR" > "$STUB/sudo"
  chmod +x "$STUB/sudo"
  run bash -c 'source lib/log.sh; source lib/guard.sh; source lib/detect.sh; source modules/docker.sh; GROUNDCREW_OS=linux docker::install'
  [ "$status" -ne 0 ]
  [ ! -f "$GROUNDCREW_STATE_DIR/optional-docker" ]
}

# --- media -----------------------------------------------------------------

@test "media::install (linux) installs ffmpeg via apt-get and rembg via uv" {
  run bash -c 'source lib/log.sh; source lib/guard.sh; source lib/detect.sh; source modules/media.sh; GROUNDCREW_OS=linux media::install'
  [ "$status" -eq 0 ]
  grep -q 'apt-get install -y ffmpeg' "$BATS_TEST_TMPDIR/calls.log"
  grep -q 'uv tool install rembg' "$BATS_TEST_TMPDIR/calls.log"
  [ -f "$GROUNDCREW_STATE_DIR/optional-media" ]
}

@test "media::install (macos) installs ffmpeg via brew" {
  run bash -c 'source lib/log.sh; source lib/guard.sh; source lib/detect.sh; source modules/media.sh; GROUNDCREW_OS=macos media::install'
  [ "$status" -eq 0 ]
  grep -q 'brew install ffmpeg' "$BATS_TEST_TMPDIR/calls.log"
  grep -q 'uv tool install rembg' "$BATS_TEST_TMPDIR/calls.log"
  [ -f "$GROUNDCREW_STATE_DIR/optional-media" ]
}

@test "media::install falls back to pipx for rembg when uv is absent" {
  rm -f "$STUB/uv"
  # PATH restricted to $STUB only: the host may have a real uv install, and
  # letting that leak in would defeat this absence/fallback test.
  run env PATH="$STUB" GROUNDCREW_OS=linux "$REAL_BASH" -c 'source lib/log.sh; source lib/guard.sh; source lib/detect.sh; source modules/media.sh; media::install'
  [ "$status" -eq 0 ]
  grep -q 'pipx install rembg' "$BATS_TEST_TMPDIR/calls.log"
  [ -f "$GROUNDCREW_STATE_DIR/optional-media" ]
}

@test "media::install fails and does not write the marker when neither uv nor pipx is present" {
  rm -f "$STUB/uv" "$STUB/pipx"
  run env PATH="$STUB" GROUNDCREW_OS=linux "$REAL_BASH" -c 'source lib/log.sh; source lib/guard.sh; source lib/detect.sh; source modules/media.sh; media::install'
  [ "$status" -ne 0 ]
  [ ! -f "$GROUNDCREW_STATE_DIR/optional-media" ]
}
