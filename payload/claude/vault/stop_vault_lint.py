#!/usr/bin/env python3
"""Stop-hook: block a session that leaves NEW vault lint errors.

Wire it in ~/.claude/settings.json (Stop), not only in the vault's own project
settings. Vault writes overwhelmingly happen during ordinary coding sessions
(append a changelog entry after shipping), not while sitting in the vault as a
project — so a project-scoped-only wiring never runs in the exact sessions that
write to the vault.

Vault root: $CLAUDE_VAULT_DIR, default ~/ObsidianVault. It is also found
automatically if the current project dir contains _Agent_System/vault_lint.py.

Never hard-fails: a bug here must not wedge a turn.
"""
from __future__ import annotations

import json
import os
import subprocess
import sys
from pathlib import Path

EDIT_TOOLS = {'Edit', 'Write', 'MultiEdit', 'NotebookEdit'}
WRITE_MARKERS = ('>>', '> ', 'tee ', 'sed -i', 'cp ', 'mv ', 'python3 - ')


def _resolve_vault(payload):
    """The vault root, whether or not it is this session's project dir.

    Always resolve(): a vault is often a symlink to somewhere else, and a plain
    `find` will not descend a symlinked starting point.
    """
    cand = os.environ.get('CLAUDE_PROJECT_DIR') or payload.get('cwd') or '.'
    vault_env = os.environ.get('CLAUDE_VAULT_DIR') or '~/ObsidianVault'
    for p in (Path(cand), Path(vault_env).expanduser()):
        try:
            p = p.resolve()
        except Exception:  # noqa: BLE001,S112 - hook must degrade, never crash the session
            continue
        if (p / '_Agent_System' / 'vault_lint.py').exists():
            return p
    return None


def _touched_vault(payload, vault):
    """Did THIS turn write to the vault?

    Scoping matters: a stray edit made in Obsidian itself can introduce a lint
    error at any time. Blocking on that unconditionally would wedge every
    unrelated coding session until someone fixed a note. When the session did not
    touch the vault we warn instead of blocking.
    """
    tpath = payload.get('transcript_path')
    if not tpath or not os.path.exists(tpath):
        return False
    # Parse line by line: the transcript is still being appended to, so its
    # last line can be half-written. One bad line must not discard the turn —
    # that would downgrade a vault-writing session's block to a mere warning.
    records = []
    try:
        with open(tpath, encoding='utf-8') as f:
            for line in f:
                if not line.strip():
                    continue
                try:
                    rec = json.loads(line)
                except ValueError:
                    continue
                if isinstance(rec, dict):
                    records.append(rec)
    except Exception:  # noqa: BLE001 - hook must degrade, never crash the session
        return False

    last_user = -1
    for i, rec in enumerate(records):
        msg = rec.get('message') or {}
        if (msg.get('role') or rec.get('type')) != 'user':
            continue
        content = msg.get('content')
        is_tool_result = has_text = False
        if isinstance(content, str):
            has_text = bool(content.strip())
        elif isinstance(content, list):
            for b in content:
                if isinstance(b, dict):
                    if b.get('type') == 'tool_result':
                        is_tool_result = True
                    elif b.get('type') == 'text' and b.get('text', '').strip():
                        has_text = True
                elif isinstance(b, str) and b.strip():
                    has_text = True
        if has_text and not is_tool_result:
            last_user = i
    turn = records[last_user + 1:] if last_user >= 0 else records

    vs = str(vault)
    # A shell command names the vault however the user typed it: resolved,
    # via the unresolved $CLAUDE_VAULT_DIR (often a symlink), or as ~/...
    vault_env = os.environ.get('CLAUDE_VAULT_DIR') or '~/ObsidianVault'
    vault_forms = {vs, os.path.expanduser(vault_env).rstrip(os.sep)}
    home = os.path.expanduser('~')
    vault_forms |= {'~' + f[len(home):] for f in list(vault_forms) if f.startswith(home + os.sep)}
    for rec in turn:
        content = (rec.get('message') or {}).get('content')
        if not isinstance(content, list):
            continue
        for b in content:
            if not isinstance(b, dict) or b.get('type') != 'tool_use':
                continue
            name = b.get('name', '') or ''
            inp = b.get('input') or {}
            if name.startswith('mcp__obsidian__') and any(
                k in name for k in ('append', 'patch', 'put', 'delete', 'create')
            ):
                return True
            if name in EDIT_TOOLS:
                fp = inp.get('file_path') or inp.get('notebook_path') or ''
                try:
                    if fp and str(Path(fp).resolve()).startswith(vs + os.sep):
                        return True
                except Exception:  # noqa: BLE001,S112 - hook must degrade, never crash the session
                    continue
            if name == 'Bash':
                cmd = inp.get('command', '') or ''
                if any(v in cmd for v in vault_forms) and any(m in cmd for m in WRITE_MARKERS):
                    return True
    return False


def main():
    try:
        payload = json.load(sys.stdin)
    except Exception:  # noqa: BLE001 - hook must degrade, never crash the session
        payload = {}
    if payload.get('stop_hook_active') is True:
        return 0

    vault = _resolve_vault(payload)
    if vault is None:
        return 0
    linter = vault / '_Agent_System' / 'vault_lint.py'
    baseline = vault / '_Agent_System' / 'lint-baseline.json'

    proc = None
    try:
        proc = subprocess.run(
            [sys.executable, str(linter), str(vault), '--baseline', str(baseline), '--json'],
            capture_output=True, text=True, timeout=60, check=False,
        )
        result = json.loads(proc.stdout)
        if not isinstance(result, dict):
            raise ValueError('linter output is not a JSON object')
    except Exception as exc:  # noqa: BLE001 - hook must degrade, never crash the session
        # Degrade, but visibly: a crashed or broken linter used to read as
        # "0 new errors", so the gate silently stopped gating.
        detail = ((proc.stderr if proc else '') or '').strip().splitlines()[-1:]
        print(json.dumps({
            'systemMessage': (
                f'⚠ Vault lint did not run cleanly ({type(exc).__name__}); '
                'the vault lint gate was skipped this turn.'
                + (f' Last stderr line: {detail[0]}' if detail else '')
            )
        }))
        return 0

    errors = [
        f for f in result.get('new', [])
        if isinstance(f, dict) and f.get('severity') == 'ERROR'
    ]
    if not errors:
        return 0

    lines = [
        f"  - {f.get('path', '?')}:{f.get('line', '?')} [{f.get('code', '?')}] {f.get('message', '')}"
        for f in errors[:12]
    ]
    if len(errors) > 12:
        lines.append(f"  ... +{len(errors) - 12} more")
    body = '\n'.join(lines)

    if _touched_vault(payload, vault):
        print(json.dumps({
            'decision': 'block',
            'reason': (
                f'STOP-GATE (vault lint): this session wrote to the vault and left '
                f'{len(errors)} NEW error(s) beyond the baseline:\n\n{body}\n\n'
                'Fix or reclassify them, then re-run the baseline-aware lint command '
                "in the vault's CLAUDE.md until it reports 0 new findings. Rules: "
                "the vault's _Agent_System/VAULT_AGENT_RULES.md\n\n"
                'If a finding is pre-existing and genuinely out of scope, say so in '
                'one line and stop.'
            ),
        }))
    else:
        print(json.dumps({
            'systemMessage': (
                f'⚠ Vault lint: {len(errors)} new error(s) beyond the baseline. '
                f'Not from this session (it did not write to the vault):\n{body}'
            )
        }))
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
