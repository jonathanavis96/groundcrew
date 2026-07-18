# shellcheck shell=bash
path::wire() {
  local rc="${1:-$HOME/.bashrc}"
  local begin='# >>> groundcrew path >>>'
  local end='# <<< groundcrew path <<<'
  [[ -f "$rc" ]] || touch "$rc"
  if grep -qF "$begin" "$rc"; then
    log::info "PATH block already present in $rc"
    return 0
  fi
  cat >> "$rc" <<EOF
$begin
export PATH="\$HOME/.local/bin:\$HOME/bin:\$PATH"
export NVM_DIR="\$HOME/.nvm"
[ -s "\$NVM_DIR/nvm.sh" ] && \\. "\$NVM_DIR/nvm.sh"
$end
EOF
  log::ok "wired PATH into $rc"
}
