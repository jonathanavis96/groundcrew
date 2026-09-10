# shellcheck shell=bash
# Installs the Claude Code CLI, the official plugin marketplace, and the
# ~/.claude configuration layer (agents, working agreements, hooks, skills,
# cache-guard) from payload/claude. Never clobbers: an existing file is backed
# up to a timestamped sibling before being replaced, and an existing
# settings.json is never edited — the keys to merge are printed instead. A
# host with no settings.json at all gets one written outright (see
# _claude_kit__settings_notice).
# install.sh dispatches "${MODULE}::install", so the entry point has to carry
# the module's hyphenated name.
claude-kit::install() {
  guard::run_once optional-claude-kit _claude_kit__do
}

_claude_kit__do() {
  local payload_dir dest
  payload_dir="$(dirname "${BASH_SOURCE[0]}")/../payload/claude"
  dest="${GROUNDCREW_CLAUDE_DIR:-$HOME/.claude}"

  if [[ ! -d "$payload_dir" ]]; then
    log::error "payload/claude not found at $payload_dir"
    return 1
  fi

  log::step "Installing claude-kit into $dest"
  _claude_kit__install_cli || return 1
  _claude_kit__install_plugins || return 1
  _claude_kit__install_base "$payload_dir" "$dest" || return 1
  _claude_kit__install_optional "$payload_dir" "$dest" || return 1
  _claude_kit__install_vault "$payload_dir" "$dest" || return 1
  _claude_kit__settings_notice "$payload_dir" "$dest" || return 1
  log::ok "claude-kit installed"
}

# The Claude Code CLI itself. Installed via its npm package (same global-npm
# shape as modules/playwright.sh) so this needs the core node toolchain first.
# Pre-auth: no logged-in session is required to install the binary.
_claude_kit__install_cli() {
  if guard::has_cmd claude; then
    log::info "claude CLI already installed"
    return 0
  fi
  if ! guard::has_cmd npm; then
    log::error "npm not found — install the core node toolchain first"
    return 1
  fi
  npm install -g @anthropic-ai/claude-code || return 1
  log::ok "claude CLI installed"
}

# The curated, general-purpose subset of anthropics/claude-plugins-official —
# not the whole marketplace. That marketplace carries hundreds of entries
# (per-language LSPs, chat-channel bridges, most third-party SaaS
# integrations), and installing all of them by default would be the wrong
# call for a fresh workstation. This is the "11 official plugins (incl.
# superpowers)" from docs/specs/2026-07-18-groundcrew-design.md, matched
# against the general dev-workflow plugins (excluding per-language LSPs, chat
# bridges and third-party SaaS connectors — context7 stays in as a
# general-purpose docs lookup rather than a single-vendor integration).
_CLAUDE_KIT_PLUGINS=(
  claude-md-management
  code-review
  code-simplifier
  commit-commands
  context7
  feature-dev
  frontend-design
  mattpocock-skills
  security-guidance
  session-report
  superpowers
)

# Adds the marketplace and installs the curated plugin set. Pre-auth like the
# CLI install above, so it runs in the same pass rather than being deferred to
# a manual step. -y accepts each plugin's declared install command without an
# interactive prompt, since provisioning runs with no TTY.
#
# "claude plugin marketplace add" is itself idempotent (re-adding an
# already-known marketplace succeeds with "already on disk" rather than
# erroring, verified against the real CLI). Each plugin install is still
# skipped explicitly when already present — guard::run_once normally means
# this whole module runs once per host, but the marker is just a file, and a
# forced re-run (or a plugin installed by hand before this ever ran) should
# not have to depend on the CLI's own repeat-install behaviour to stay a
# no-op.
_claude_kit__install_plugins() {
  if ! guard::has_cmd claude; then
    log::error "claude CLI not found — cannot install plugins"
    return 1
  fi
  claude plugin marketplace add anthropics/claude-plugins-official || return 1
  local p already_installed
  already_installed="$(claude plugin list 2>/dev/null || true)"
  for p in "${_CLAUDE_KIT_PLUGINS[@]}"; do
    # Anchored on a word boundary either side: a plain substring match would
    # report e.g. a curated "review" as already installed just because
    # "code-review@claude-plugins-official" is present in the listing.
    if grep -qE "(^|[[:space:]])${p}@claude-plugins-official([[:space:]]|\$)" <<<"$already_installed"; then
      log::info "$p already installed"
      continue
    fi
    claude plugin install "$p@claude-plugins-official" -y || return 1
  done
  log::ok "official plugin set installed"
}

# Base tier: agents, working agreements, the on-demand template, the WebFetch
# guard, the session-context emitter, and cache-guard.
_claude_kit__install_base() {
  local payload_dir="$1" dest="$2" f

  mkdir -p "$dest/agents" "$dest/references" "$dest/hooks" \
    "$dest/cache-guard/scripts" || return 1

  for f in "$payload_dir"/agents/*.md; do
    _claude_kit__copy "$f" "$dest/agents/$(basename "$f")" || return 1
  done

  _claude_kit__copy "$payload_dir/CLAUDE.md" "$dest/CLAUDE.md" || return 1
  _claude_kit__copy "$payload_dir/README.md" "$dest/claude-kit-README.md" || return 1
  _claude_kit__copy "$payload_dir/references/on-demand.md" \
    "$dest/references/on-demand.md" || return 1

  for f in webfetch-guard.py session-context.py; do
    _claude_kit__copy "$payload_dir/hooks/$f" "$dest/hooks/$f" || return 1
  done

  _claude_kit__copy "$payload_dir/cache-guard/scripts/ccg.py" \
    "$dest/cache-guard/scripts/ccg.py" || return 1
  chmod +x "$dest/cache-guard/scripts/ccg.py" || return 1
  # cache-guard reads config.json from its own root; only seed it once, so a
  # tuned config survives a re-install.
  if [[ ! -f "$dest/cache-guard/config.json" ]]; then
    _claude_kit__copy "$payload_dir/cache-guard/config/config.json.example" \
      "$dest/cache-guard/config.json" || return 1
  else
    log::info "cache-guard/config.json exists, leaving your settings alone"
  fi
}

# Opt-in tier: skills and the caveman session hook. Copied but inert — a skill
# does nothing until invoked, and the hook does nothing until it is wired into
# settings.json by hand.
_claude_kit__install_optional() {
  local payload_dir="$1" dest="$2" skill f

  for skill in "$payload_dir"/skills/*/; do
    [[ -d "$skill" ]] || continue
    local name
    name="$(basename "$skill")"
    mkdir -p "$dest/skills/$name" || return 1
    for f in "$skill"*; do
      [[ -f "$f" ]] || continue
      _claude_kit__copy "$f" "$dest/skills/$name/$(basename "$f")" || return 1
    done
  done

  for f in caveman-autostart.sh caveman-autostart.ps1; do
    _claude_kit__copy "$payload_dir/hooks/$f" "$dest/hooks/$f" || return 1
  done
  chmod +x "$dest/hooks/caveman-autostart.sh" || return 1
}

# Obsidian tier: opt-in via GROUNDCREW_CLAUDE_KIT_VAULT=1, because it needs two
# manual steps (the Obsidian app, and its Local REST API plugin for an API key)
# that no installer can do. The files land inert — nothing is wired up.
_claude_kit__install_vault() {
  local payload_dir="$1" dest="$2" f
  if [[ "${GROUNDCREW_CLAUDE_KIT_VAULT:-0}" != "1" ]]; then
    log::info "skip vault tier (set GROUNDCREW_CLAUDE_KIT_VAULT=1 to install it)"
    return 0
  fi
  mkdir -p "$dest/vault-kit" || return 1
  for f in "$payload_dir"/vault/*; do
    [[ -f "$f" ]] || continue
    _claude_kit__copy "$f" "$dest/vault-kit/$(basename "$f")" || return 1
  done
  # WSL2 -> Windows Obsidian bridge (wrapper + TCP forwarder). Harmless elsewhere.
  mkdir -p "$dest/vault-kit/wsl" || return 1
  for f in "$payload_dir"/vault/wsl/*; do
    [[ -f "$f" ]] || continue
    _claude_kit__copy "$f" "$dest/vault-kit/wsl/$(basename "$f")" || return 1
  done
  chmod +x "$dest/vault-kit/wsl/mcp-obsidian-wrapper.sh" 2>/dev/null || true
  for f in vault-slug-wikilink-guard.py claude-vault-memory-gate.py; do
    _claude_kit__copy "$payload_dir/hooks/$f" "$dest/hooks/$f" || return 1
  done
  log::warn "vault tier: install Obsidian and enable its 'Local REST API' plugin, then put the key in $dest/vault-kit/mcp-obsidian.json"
}

# settings.json is the one file this module refuses to overwrite. It carries
# the user's plugins, model and permissions, and a bad merge is expensive to
# undo. When one already exists, that refusal holds exactly as before: drop
# the additions next to it and print the hand-merge notice. When none exists
# at all, there is nothing to merge and nothing to lose, so write it outright.
_claude_kit__settings_notice() {
  local payload_dir="$1" dest="$2"
  _claude_kit__copy "$payload_dir/settings-additions.json" \
    "$dest/settings-additions.json" || return 1
  if [[ -f "$dest/settings.json" ]]; then
    log::warn "settings.json NOT modified — merge $dest/settings-additions.json into $dest/settings.json by hand"
    log::info "back up settings.json first; the file explains what each key does"
  else
    cp "$payload_dir/settings-additions.json" "$dest/settings.json" || return 1
    log::ok "no settings.json found — wrote $dest/settings.json from settings-additions.json"
  fi
}

# Copy SRC to DEST, backing up an existing DEST to a timestamped sibling first.
# Identical content is a no-op so a re-run does not litter backups.
_claude_kit__copy() {
  local src="$1" dest="$2"
  if [[ -f "$dest" ]]; then
    if cmp -s "$src" "$dest"; then
      log::info "unchanged $(basename "$dest")"
      return 0
    fi
    local backup
    backup="$dest.bak-$(date +%Y%m%d-%H%M%S)"
    cp "$dest" "$backup" || return 1
    log::warn "backed up existing $(basename "$dest") to $(basename "$backup")"
  fi
  cp "$src" "$dest" || return 1
  log::ok "wrote $dest"
}
