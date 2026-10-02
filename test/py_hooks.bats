# Error-handling regressions in the payload's Python hooks: each of these used
# to fail silently (a dropped message, a skipped gate, a wrong exit status).
setup() {
  load test_helper
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
  export VAULT="$BATS_TEST_TMPDIR/vault"
  mkdir -p "$VAULT/_Agent_System"
  export CLAUDE_VAULT_DIR="$VAULT"
  export CLAUDE_PROJECT_DIR="$BATS_TEST_TMPDIR/nowhere"
  HOOKS="$REPO_ROOT/payload/claude/hooks"
  VAULTKIT="$REPO_ROOT/payload/claude/vault"
}

# A linter that always reports one new ERROR.
_fake_linter_with_error() {
  cat >"$VAULT/_Agent_System/vault_lint.py" <<'PY'
import json
print(json.dumps({"new": [{"severity": "ERROR", "path": "a.md", "line": 1, "code": "x", "message": "bad"}], "all_count": 1}))
PY
}

@test "stop_vault_lint blocks a vault write despite a half-written transcript line" {
  _fake_linter_with_error
  T="$BATS_TEST_TMPDIR/t.jsonl"
  printf '%s\n' \
    '{"type":"user","message":{"role":"user","content":"go"}}' \
    "{\"message\":{\"role\":\"assistant\",\"content\":[{\"type\":\"tool_use\",\"name\":\"Write\",\"input\":{\"file_path\":\"$VAULT/a.md\"}}]}}" \
    '{"message":{"role":"assistant","content":[{"ty' >"$T"
  run bash -c "echo '{\"transcript_path\":\"$T\"}' | python3 '$VAULTKIT/stop_vault_lint.py'"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"decision": "block"'* ]]
}

@test "stop_vault_lint counts a shell write to the vault via ~/" {
  _fake_linter_with_error
  mkdir -p "$HOME/ObsidianVault/_Agent_System"
  cp "$VAULT/_Agent_System/vault_lint.py" "$HOME/ObsidianVault/_Agent_System/"
  unset CLAUDE_VAULT_DIR
  T="$BATS_TEST_TMPDIR/t.jsonl"
  printf '%s\n' \
    '{"type":"user","message":{"role":"user","content":"go"}}' \
    '{"message":{"role":"assistant","content":[{"type":"tool_use","name":"Bash","input":{"command":"echo x >> ~/ObsidianVault/log.md"}}]}}' >"$T"
  run bash -c "echo '{\"transcript_path\":\"$T\"}' | python3 '$VAULTKIT/stop_vault_lint.py'"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"decision": "block"'* ]]
}

@test "stop_vault_lint reports a crashed linter instead of passing silently" {
  echo 'raise SystemExit("linter exploded")' >"$VAULT/_Agent_System/vault_lint.py"
  run bash -c "echo '{}' | python3 '$VAULTKIT/stop_vault_lint.py'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"did not run cleanly"* ]]
  [[ "$output" == *"linter exploded"* ]]
}

@test "stop_vault_lint tolerates a finding with missing keys" {
  echo 'print("{\"new\": [{\"severity\": \"ERROR\"}]}")' >"$VAULT/_Agent_System/vault_lint.py"
  run bash -c "echo '{}' | python3 '$VAULTKIT/stop_vault_lint.py'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"1 new error"* ]]
}

@test "memory gate keeps the sweep report when it also warns about a dirty tree" {
  : >"$VAULT/Phantom.md"
  R="$BATS_TEST_TMPDIR/r"
  git init -q --template= "$R"
  echo hi >"$R/f.txt"
  T="$BATS_TEST_TMPDIR/t.jsonl"
  printf '%s\n' \
    '{"type":"user","message":{"role":"user","content":"go"}}' \
    "{\"message\":{\"role\":\"assistant\",\"content\":[{\"type\":\"tool_use\",\"name\":\"Write\",\"input\":{\"file_path\":\"$R/f.txt\"}}]}}" >"$T"
  run bash -c "echo '{\"transcript_path\":\"$T\"}' | CLAUDE_VAULT_SWEEP=1 python3 '$HOOKS/claude-vault-memory-gate.py'"
  [ "$status" -eq 0 ]
  [ ! -e "$VAULT/Phantom.md" ]
  [[ "$output" == *"Removed 1 empty phantom"* ]]
  [[ "$output" == *"Left uncommitted edits"* ]]
}

@test "memory gate sees a shell write to the vault via ~/ as a sync" {
  unset CLAUDE_VAULT_DIR
  mkdir -p "$HOME/ObsidianVault"
  T="$BATS_TEST_TMPDIR/t.jsonl"
  printf '%s\n' \
    '{"type":"user","message":{"role":"user","content":"go"}}' \
    '{"message":{"role":"assistant","content":[{"type":"tool_use","name":"Bash","input":{"command":"git commit -m x"}}]}}' \
    '{"message":{"role":"assistant","content":[{"type":"tool_use","name":"Bash","input":{"command":"echo done >> ~/ObsidianVault/log.md"}}]}}' >"$T"
  run bash -c "echo '{\"transcript_path\":\"$T\"}' | python3 '$HOOKS/claude-vault-memory-gate.py'"
  [ "$status" -eq 0 ]
  [[ "$output" != *'"decision": "block"'* ]]
}

@test "wikilink guard scans NotebookEdit new_source" {
  run bash -c "echo '{\"tool_name\":\"NotebookEdit\",\"tool_input\":{\"notebook_path\":\"$VAULT/n.ipynb\",\"new_source\":\"see [[reference_foo]]\"}}' | python3 '$HOOKS/vault-slug-wikilink-guard.py'"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"decision": "block"'* ]]
}

@test "ccg watch-once exits 0 after sending a warning" {
  S="$HOME/.claude/cache-guard/sessions"
  mkdir -p "$S"
  printf '{"session_id":"s1","last_model_activity_ts":1,"estimated_context_tokens":999999999}\n' >"$S/s1.json"
  export CCG_NOTIFY_HELPER="$BATS_TEST_TMPDIR/notify"
  printf '#!/bin/sh\nexit 0\n' >"$CCG_NOTIFY_HELPER"
  chmod +x "$CCG_NOTIFY_HELPER"
  run python3 "$REPO_ROOT/payload/claude/cache-guard/scripts/ccg.py" watch-once
  [ "$status" -eq 0 ]
  ls "$HOME/.claude/cache-guard/warnings/"s1*.json
}

@test "ccg watch-once skips a session file with a corrupt timestamp and still warns on the rest" {
  S="$HOME/.claude/cache-guard/sessions"
  mkdir -p "$S"
  printf '{"session_id":"a1","ended_at_ts":"garbage","last_model_activity_ts":1,"estimated_context_tokens":999999999}\n' >"$S/a1.json"
  printf '{"session_id":"s1","last_model_activity_ts":1,"estimated_context_tokens":999999999}\n' >"$S/s1.json"
  export CCG_NOTIFY_HELPER="$BATS_TEST_TMPDIR/notify"
  printf '#!/bin/sh\nexit 0\n' >"$CCG_NOTIFY_HELPER"
  chmod +x "$CCG_NOTIFY_HELPER"
  run python3 "$REPO_ROOT/payload/claude/cache-guard/scripts/ccg.py" watch-once
  [ "$status" -eq 0 ]
  ls "$HOME/.claude/cache-guard/warnings/"s1*.json
}
