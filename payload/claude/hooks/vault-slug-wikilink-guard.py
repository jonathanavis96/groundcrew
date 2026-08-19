#!/usr/bin/env python3
"""PostToolUse guard: block memory-slug wikilinks written into the Obsidian vault.

Root cause of the empty "stub" notes that keep appearing in a vault: an agent
writes a wikilink to a MEMORY SLUG, e.g. `[[reference_build_pipeline]]`.
Obsidian then materialises an empty phantom note at the vault root the moment
that link is followed or synced. The rule is "reference memory slugs as inline
code, never as [[wikilinks]]" — but fresh-context subagents don't see it, so we
enforce it at write time here.

Vault root: $CLAUDE_VAULT_DIR, defaulting to ~/ObsidianVault.

Fires on Write/Edit/MultiEdit into the vault and on obsidian MCP writes (which
always target the vault). If the written content contains a slug-style wikilink
(`[[reference_… ]]`, `[[feedback_… ]]`, `[[project_… ]]`, `[[user_… ]]`) it
blocks the tool result and tells the agent to use inline code (or link the real
note) instead. Never hard-fails. Read by the "PostToolUse" hook in settings.json.
"""
import sys, json, os, re

# slug-wikilinks: [[reference_…]] / [[feedback_…]] / [[project_…]] / [[user_…]]
SLUG_RE = re.compile(r"\[\[\s*(reference|feedback|project|user)_[^\]\n]*\]\]")
# code spans are the SAFE form (don't render as links) — strip them before scan
FENCE_RE = re.compile(r"```.*?```", re.S)
INLINE_CODE_RE = re.compile(r"(`+)(?:(?!\1).)*?\1", re.S)
VAULT = os.path.realpath(
    os.path.expanduser(os.environ.get("CLAUDE_VAULT_DIR") or "~/ObsidianVault")
)


def _strip_code(text):
    """Remove fenced + inline code spans so a slug-wikilink shown as an example
    (`[[reference_foo]]`) — the recommended safe form — doesn't trip the guard."""
    return INLINE_CODE_RE.sub("", FENCE_RE.sub("", text))


def _real(p):
    try:
        return os.path.realpath(p)
    except Exception:
        return p or ""


def _under_vault(p):
    rp = _real(p)
    return rp == VAULT or rp.startswith(VAULT + os.sep)


def main():
    try:
        data = json.load(sys.stdin)
    except Exception:
        return

    name = data.get("tool_name", "") or ""
    inp = data.get("tool_input") or {}

    # Collect the text that was written, only for vault-bound writes.
    blobs = []
    is_obsidian = name.startswith("mcp__obsidian__")
    if is_obsidian:
        # obsidian MCP always writes into the vault.
        if isinstance(inp.get("content"), str):
            blobs.append(inp["content"])
    elif name in ("Write", "Edit", "MultiEdit", "NotebookEdit"):
        fp = inp.get("file_path") or inp.get("notebook_path") or ""
        if not fp or not _under_vault(fp):
            return
        if isinstance(inp.get("content"), str):
            blobs.append(inp["content"])
        if isinstance(inp.get("new_string"), str):
            blobs.append(inp["new_string"])
        for e in inp.get("edits") or []:
            if isinstance(e, dict) and isinstance(e.get("new_string"), str):
                blobs.append(e["new_string"])
    else:
        return

    matches = sorted({m.group(0) for b in blobs for m in SLUG_RE.finditer(_strip_code(b))})
    if not matches:
        return

    reason = (
        "VAULT-GUARD: you just wrote memory-slug wikilink(s) into the vault: "
        + ", ".join(matches)
        + ". These materialise EMPTY phantom notes in the vault. Rule: "
        "reference a memory slug as inline code — `reference_build_pipeline` — "
        "NEVER as a [[wikilink]]. If you meant to link a real vault note, use "
        "its title (e.g. [[Build Pipeline]]). Re-edit the note now to fix the "
        "link(s)."
    )
    print(json.dumps({"decision": "block", "reason": reason}))


if __name__ == "__main__":
    try:
        main()
    except Exception:
        pass
