setup() {
  load test_helper
  cd "$REPO_ROOT"
  export GROUNDCREW_NO_COLOR=1
  export GROUNDCREW_STATE_DIR="$BATS_TEST_TMPDIR/state"
  # Fake apt-get/sudo/brew/npm/npx/uv/pipx/node on a stub PATH that logs invocations.
  STUB="$BATS_TEST_TMPDIR/bin"; mkdir -p "$STUB"
  for c in apt-get sudo brew npm npx uv pipx node claude; do
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
  for c in mkdir cat rm chmod ln mv cp grep dirname; do
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

@test "media::install (linux) installs ffmpeg via apt-get and rembg[cpu] via uv" {
  run bash -c 'source lib/log.sh; source lib/guard.sh; source lib/detect.sh; source modules/media.sh; GROUNDCREW_OS=linux media::install'
  [ "$status" -eq 0 ]
  grep -q 'apt-get install -y ffmpeg' "$BATS_TEST_TMPDIR/calls.log"
  grep -q 'uv tool install rembg\[cpu\]' "$BATS_TEST_TMPDIR/calls.log"
  [ -f "$GROUNDCREW_STATE_DIR/optional-media" ]
}

@test "media::install (macos) installs ffmpeg via brew" {
  run bash -c 'source lib/log.sh; source lib/guard.sh; source lib/detect.sh; source modules/media.sh; GROUNDCREW_OS=macos media::install'
  [ "$status" -eq 0 ]
  grep -q 'brew install ffmpeg' "$BATS_TEST_TMPDIR/calls.log"
  grep -q 'uv tool install rembg\[cpu\]' "$BATS_TEST_TMPDIR/calls.log"
  [ -f "$GROUNDCREW_STATE_DIR/optional-media" ]
}

@test "media::install falls back to pipx for rembg[cpu] when uv is absent" {
  rm -f "$STUB/uv"
  # PATH restricted to $STUB only: the host may have a real uv install, and
  # letting that leak in would defeat this absence/fallback test.
  run env PATH="$STUB" GROUNDCREW_OS=linux "$REAL_BASH" -c 'source lib/log.sh; source lib/guard.sh; source lib/detect.sh; source modules/media.sh; media::install'
  [ "$status" -eq 0 ]
  grep -q 'pipx install rembg\[cpu\]' "$BATS_TEST_TMPDIR/calls.log"
  [ -f "$GROUNDCREW_STATE_DIR/optional-media" ]
}

@test "media::install fails and does not write the marker when neither uv nor pipx is present" {
  rm -f "$STUB/uv" "$STUB/pipx"
  run env PATH="$STUB" GROUNDCREW_OS=linux "$REAL_BASH" -c 'source lib/log.sh; source lib/guard.sh; source lib/detect.sh; source modules/media.sh; media::install'
  [ "$status" -ne 0 ]
  [ ! -f "$GROUNDCREW_STATE_DIR/optional-media" ]
}

# --- claude-kit -------------------------------------------------------------

# Shorthand: source the deps + module and run the installer, as install.sh does.
_ck() {
  bash -c 'source lib/log.sh; source lib/guard.sh; source modules/claude-kit.sh; "claude-kit::install"'
}

@test "claude-kit::install installs the claude CLI via npm when it is absent" {
  rm -f "$STUB/claude"
  # This npm stub also drops a fake "claude" onto the stub PATH, standing in
  # for the real npm global install actually putting the binary there — so
  # the plugin-marketplace step right after it has something to call.
  cat > "$STUB/npm" <<EOF
#!/usr/bin/env bash
echo "npm \$*" >> "$BATS_TEST_TMPDIR/calls.log"
cat > "$STUB/claude" <<'INNER'
#!/usr/bin/env bash
echo "claude \$*" >> "$BATS_TEST_TMPDIR/calls.log"
INNER
chmod +x "$STUB/claude"
EOF
  chmod +x "$STUB/npm"
  export GROUNDCREW_CLAUDE_DIR="$BATS_TEST_TMPDIR/dotclaude"
  # PATH restricted to $STUB only: the host may have a real claude CLI on it
  # (this repo's own dev box does), and letting that leak in would defeat
  # this absence test — install.sh's real dispatch never does that either.
  run env PATH="$STUB" "$REAL_BASH" -c 'source lib/log.sh; source lib/guard.sh; source modules/claude-kit.sh; "claude-kit::install"'
  [ "$status" -eq 0 ]
  grep -q 'npm install -g @anthropic-ai/claude-code' "$BATS_TEST_TMPDIR/calls.log"
}

@test "claude-kit::install skips the CLI install when claude is already present" {
  export GROUNDCREW_CLAUDE_DIR="$BATS_TEST_TMPDIR/dotclaude"
  run _ck
  [ "$status" -eq 0 ]
  ! grep -q 'npm install -g @anthropic-ai/claude-code' "$BATS_TEST_TMPDIR/calls.log"
}

@test "claude-kit::install fails and writes no marker when npm is absent and claude is not installed" {
  rm -f "$STUB/claude" "$STUB/npm"
  export GROUNDCREW_CLAUDE_DIR="$BATS_TEST_TMPDIR/dotclaude"
  run env PATH="$STUB" "$REAL_BASH" -c 'source lib/log.sh; source lib/guard.sh; source modules/claude-kit.sh; "claude-kit::install"'
  [ "$status" -ne 0 ]
  [ ! -f "$GROUNDCREW_STATE_DIR/optional-claude-kit" ]
}

@test "claude-kit::install adds the official marketplace and installs the curated plugin set" {
  export GROUNDCREW_CLAUDE_DIR="$BATS_TEST_TMPDIR/dotclaude"
  run _ck
  [ "$status" -eq 0 ]
  grep -q 'claude plugin marketplace add anthropics/claude-plugins-official' "$BATS_TEST_TMPDIR/calls.log"
  for p in superpowers code-review commit-commands session-report; do
    grep -q "claude plugin install $p@claude-plugins-official -y" "$BATS_TEST_TMPDIR/calls.log"
  done
}

@test "claude-kit::install skips a plugin install when 'claude plugin list' already shows it installed" {
  export GROUNDCREW_CLAUDE_DIR="$BATS_TEST_TMPDIR/dotclaude"
  # A "claude" stub whose "plugin list" subcommand reports superpowers as
  # already installed, everything else logged normally.
  cat > "$STUB/claude" <<EOF
#!/usr/bin/env bash
echo "claude \$*" >> "$BATS_TEST_TMPDIR/calls.log"
if [[ "\$1 \$2" == "plugin list" ]]; then
  echo "superpowers@claude-plugins-official"
fi
EOF
  chmod +x "$STUB/claude"
  run _ck
  [ "$status" -eq 0 ]
  ! grep -q 'claude plugin install superpowers@claude-plugins-official -y' "$BATS_TEST_TMPDIR/calls.log"
  grep -q 'claude plugin install code-review@claude-plugins-official -y' "$BATS_TEST_TMPDIR/calls.log"
}

@test "claude-kit::install lays down agents, CLAUDE.md, hooks and cache-guard" {
  export GROUNDCREW_CLAUDE_DIR="$BATS_TEST_TMPDIR/dotclaude"
  run _ck
  [ "$status" -eq 0 ]
  for a in worker scout scout-find Explore fable; do
    [ -f "$GROUNDCREW_CLAUDE_DIR/agents/$a.md" ]
  done
  [ -f "$GROUNDCREW_CLAUDE_DIR/CLAUDE.md" ]
  [ -f "$GROUNDCREW_CLAUDE_DIR/references/on-demand.md" ]
  [ -f "$GROUNDCREW_CLAUDE_DIR/hooks/webfetch-guard.py" ]
  [ -f "$GROUNDCREW_CLAUDE_DIR/hooks/session-context.py" ]
  [ -x "$GROUNDCREW_CLAUDE_DIR/cache-guard/scripts/ccg.py" ]
  [ -f "$GROUNDCREW_CLAUDE_DIR/cache-guard/config.json" ]
  [ -f "$GROUNDCREW_STATE_DIR/optional-claude-kit" ]
}

@test "claude-kit::install ships the caveman hook as BOTH .sh and .ps1" {
  # A .sh-only hook is a silent no-op on native Windows, not a degraded install.
  export GROUNDCREW_CLAUDE_DIR="$BATS_TEST_TMPDIR/dotclaude"
  run _ck
  [ "$status" -eq 0 ]
  [ -x "$GROUNDCREW_CLAUDE_DIR/hooks/caveman-autostart.sh" ]
  [ -f "$GROUNDCREW_CLAUDE_DIR/hooks/caveman-autostart.ps1" ]
}

@test "claude-kit::install ships ship-to-main inert, with its RULES.md marker" {
  export GROUNDCREW_CLAUDE_DIR="$BATS_TEST_TMPDIR/dotclaude"
  run _ck
  [ "$status" -eq 0 ]
  [ -f "$GROUNDCREW_CLAUDE_DIR/skills/ship-to-main/SKILL.md" ]
  grep -q "GROUNDCREW-UNCONFIGURED" "$GROUNDCREW_CLAUDE_DIR/skills/ship-to-main/RULES.md"
}

@test "claude-kit::install never touches an existing settings.json, only settings-additions.json" {
  export GROUNDCREW_CLAUDE_DIR="$BATS_TEST_TMPDIR/dotclaude"
  mkdir -p "$GROUNDCREW_CLAUDE_DIR"
  echo '{"mine":true}' > "$GROUNDCREW_CLAUDE_DIR/settings.json"
  run _ck
  [ "$status" -eq 0 ]
  [ "$(cat "$GROUNDCREW_CLAUDE_DIR/settings.json")" = '{"mine":true}' ]
  [ -f "$GROUNDCREW_CLAUDE_DIR/settings-additions.json" ]
}

@test "claude-kit::install writes settings.json outright when the host has none" {
  export GROUNDCREW_CLAUDE_DIR="$BATS_TEST_TMPDIR/dotclaude"
  run _ck
  [ "$status" -eq 0 ]
  [ -f "$GROUNDCREW_CLAUDE_DIR/settings.json" ]
  # Nothing to merge and nothing to lose, so it's written outright rather than
  # just dropped as settings-additions.json for a hand merge.
  diff "$GROUNDCREW_CLAUDE_DIR/settings.json" "$GROUNDCREW_CLAUDE_DIR/settings-additions.json"
}

@test "claude-kit::install a second run does not touch settings.json it wrote on the first" {
  export GROUNDCREW_CLAUDE_DIR="$BATS_TEST_TMPDIR/dotclaude"
  _ck
  echo '{"user edit": true}' > "$GROUNDCREW_CLAUDE_DIR/settings.json"
  rm -f "$GROUNDCREW_STATE_DIR/optional-claude-kit"
  run _ck
  [ "$status" -eq 0 ]
  [ "$(cat "$GROUNDCREW_CLAUDE_DIR/settings.json")" = '{"user edit": true}' ]
}

@test "claude-kit::install backs up an existing file instead of clobbering it" {
  export GROUNDCREW_CLAUDE_DIR="$BATS_TEST_TMPDIR/dotclaude"
  mkdir -p "$GROUNDCREW_CLAUDE_DIR"
  echo "my own agreements" > "$GROUNDCREW_CLAUDE_DIR/CLAUDE.md"
  run _ck
  [ "$status" -eq 0 ]
  # The payload landed...
  grep -q "Working Agreements" "$GROUNDCREW_CLAUDE_DIR/CLAUDE.md"
  # ...and the user's original survives in a timestamped sibling.
  local backup
  backup=$(echo "$GROUNDCREW_CLAUDE_DIR"/CLAUDE.md.bak-*)
  [ -f "$backup" ]
  [ "$(cat "$backup")" = "my own agreements" ]
}

@test "claude-kit::install skips the vault tier unless it is opted into" {
  export GROUNDCREW_CLAUDE_DIR="$BATS_TEST_TMPDIR/dotclaude"
  run _ck
  [ "$status" -eq 0 ]
  [ ! -d "$GROUNDCREW_CLAUDE_DIR/vault-kit" ]
  [ ! -f "$GROUNDCREW_CLAUDE_DIR/hooks/claude-vault-memory-gate.py" ]
}

@test "claude-kit::install installs the vault tier when opted into" {
  export GROUNDCREW_CLAUDE_DIR="$BATS_TEST_TMPDIR/dotclaude"
  export GROUNDCREW_CLAUDE_KIT_VAULT=1
  run _ck
  [ "$status" -eq 0 ]
  [ -f "$GROUNDCREW_CLAUDE_DIR/vault-kit/vault_lint.py" ]
  [ -f "$GROUNDCREW_CLAUDE_DIR/vault-kit/stop_vault_lint.py" ]
  [ -f "$GROUNDCREW_CLAUDE_DIR/vault-kit/mcp-obsidian.json" ]
  [ -f "$GROUNDCREW_CLAUDE_DIR/hooks/vault-slug-wikilink-guard.py" ]
  [ -f "$GROUNDCREW_CLAUDE_DIR/hooks/claude-vault-memory-gate.py" ]
  # A real API key must never ship in the payload.
  grep -q "PASTE-YOUR-LOCAL-REST-API-KEY-HERE" "$GROUNDCREW_CLAUDE_DIR/vault-kit/mcp-obsidian.json"
}

@test "claude-kit::install fails when the payload directory is missing" {
  # Copy the module somewhere with no sibling payload/ — the module resolves the
  # payload relative to its own BASH_SOURCE, so this is a genuine missing-payload
  # run rather than a stubbed one.
  export GROUNDCREW_CLAUDE_DIR="$BATS_TEST_TMPDIR/dotclaude"
  cp modules/claude-kit.sh "$BATS_TEST_TMPDIR/claude-kit.sh"
  run bash -c "source lib/log.sh; source lib/guard.sh; source '$BATS_TEST_TMPDIR/claude-kit.sh'; \"claude-kit::install\""
  [ "$status" -ne 0 ]
  [ ! -f "$GROUNDCREW_STATE_DIR/optional-claude-kit" ]
}

@test "claude-kit::install second run is a no-op" {
  export GROUNDCREW_CLAUDE_DIR="$BATS_TEST_TMPDIR/dotclaude"
  _ck
  echo "user edit" >> "$GROUNDCREW_CLAUDE_DIR/CLAUDE.md"
  run _ck
  [ "$status" -eq 0 ]
  grep -q "user edit" "$GROUNDCREW_CLAUDE_DIR/CLAUDE.md"
}
