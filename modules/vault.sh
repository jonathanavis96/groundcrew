# shellcheck shell=bash
vault::install() {
  guard::run_once optional-vault _vault__do
}
_vault__do() {
  local vault_dir="${GROUNDCREW_VAULT_DIR:-$HOME/ObsidianVault}"
  log::step "Setting up starter Obsidian vault"
  if [[ -d "$vault_dir" ]]; then
    log::info "vault already exists at $vault_dir, skipping"
    return 0
  fi
  mkdir -p "$vault_dir/.obsidian" || return 1
  cat > "$vault_dir/.obsidian/app.json" <<'EOF' || return 1
{}
EOF
  cat > "$vault_dir/Welcome.md" <<'EOF' || return 1
# Welcome

This is your starter Obsidian vault, created by Groundcrew.

Your coding agent can read and write notes here to keep context and
decisions across sessions. Open this folder as a vault in Obsidian to
browse it.
EOF
  cat > "$vault_dir/Ideas Inbox.md" <<'EOF' || return 1
# Ideas Inbox

Drop half-formed ideas here as they come up. Triage them into proper
notes later.
EOF
  log::ok "vault created at $vault_dir"
}
