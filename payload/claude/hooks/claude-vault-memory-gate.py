#!/usr/bin/env python3
"""Stop-hook gate: vault+memory sync enforcement + dirty-work-tree warning.

Runs when the main agent tries to stop. Two independent checks on the
just-ended turn:

1. VAULT/MEMORY SYNC (blocking, once): if the turn shipped a MILESTONE (a Bash
   command with git commit / git push|merge / gh pr create|merge) but did NOT
   write to the vault ($CLAUDE_VAULT_DIR, default ~/ObsidianVault) or a memory
   dir (~/.claude/projects/*/memory) — via the file tools or an obsidian MCP
   write — it blocks the stop once with a reminder to sync.

2. DIRTY WORK TREE (non-blocking warning): for every repo whose tracked files I
   edited this turn, if my edits are still uncommitted at stop, it surfaces a
   one-line systemMessage to the user (e.g. "left ~/code/X dirty"). It never
   blocks and never auto-commits — just makes the dirty tree visible.

3. EMPTY-NOTE SWEEP (opt-in, OFF by default): deletes zero-byte phantom notes
   Obsidian materialises from unresolved [[slug]] links. It DELETES FILES, so
   it only runs when CLAUDE_VAULT_SWEEP=1 is set. Leave it off until you trust
   it.

Loop-safe via stop_hook_active; never hard-fails (a gate bug must not wedge a
turn). Read by the "Stop" hook in ~/.claude/settings.json.
"""
import sys, json, os, subprocess

EDIT_TOOLS = {"Edit", "Write", "MultiEdit", "NotebookEdit"}
COMPLETION_MARKERS = (
    "git commit",
    "git push",
    "git merge",
    "gh pr create",
    "gh pr merge",
)
# Shell redirections/commands that mean "this wrote something", used to tell a
# vault WRITE from a harmless read (cat/grep/ls/wc of a note is not a sync).
WRITE_MARKERS = (">>", "> ", "tee ", "sed -i", "cp ", "mv ", "python3 - ")


def _cmd_touches(cmd, markers):
    return any(m in cmd for m in markers)


def _cmd_writes(cmd):
    return any(m in cmd for m in WRITE_MARKERS)


def main():
    try:
        data = json.load(sys.stdin)
    except Exception:
        return

    if data.get("stop_hook_active"):
        return

    tpath = data.get("transcript_path")
    if not tpath or not os.path.exists(tpath):
        return

    home = os.path.expanduser("~")
    vault = os.path.realpath(
        os.path.expanduser(os.environ.get("CLAUDE_VAULT_DIR") or "~/ObsidianVault")
    )
    # Substrings that identify a vault/memory path inside a raw shell command.
    vault_markers = (vault, "/.claude/projects/")

    records = []
    try:
        with open(tpath, encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    records.append(json.loads(line))
                except json.JSONDecodeError:
                    continue
    except OSError:
        return
    if not records:
        return

    # Window = everything after the last genuine user prompt.
    last_user = -1
    for i, rec in enumerate(records):
        msg = rec.get("message") or {}
        role = msg.get("role") or rec.get("type")
        if role != "user":
            continue
        content = msg.get("content")
        is_tool_result = False
        has_text = False
        if isinstance(content, str):
            has_text = bool(content.strip())
        elif isinstance(content, list):
            for b in content:
                if isinstance(b, dict):
                    if b.get("type") == "tool_result":
                        is_tool_result = True
                    elif b.get("type") == "text" and b.get("text", "").strip():
                        has_text = True
                elif isinstance(b, str) and b.strip():
                    has_text = True
        if has_text and not is_tool_result:
            last_user = i
    turn = records[last_user + 1:] if last_user >= 0 else records

    def real(path):
        try:
            return os.path.realpath(path)
        except Exception:
            return path or ""

    def under_vault(path):
        rp = real(path)
        return rp == vault or rp.startswith(vault + os.sep)

    def is_memory(path):
        rp = real(path)
        return "/.claude/projects/" in rp and ("/memory/" in rp or rp.endswith("/memory"))

    shipped = False
    synced = False
    edited = []  # real paths of files written this turn

    for rec in turn:
        msg = rec.get("message") or {}
        content = msg.get("content")
        if not isinstance(content, list):
            continue
        for b in content:
            if not isinstance(b, dict) or b.get("type") != "tool_use":
                continue
            name = b.get("name", "") or ""
            inp = b.get("input") or {}
            if name == "Bash":
                cmd = inp.get("command", "") or ""
                if any(m in cmd for m in COMPLETION_MARKERS):
                    shipped = True
                # A heredoc append to a changelog is a real sync. Without this the
                # gate only sees the Edit/Write tools and blocks a turn that DID
                # write to the vault via the shell.
                if _cmd_touches(cmd, vault_markers) and _cmd_writes(cmd):
                    synced = True
                continue
            if name.startswith("mcp__obsidian__") and any(
                k in name for k in ("append", "patch", "put", "delete", "create")
            ):
                synced = True
                continue
            if name in EDIT_TOOLS:
                fp = inp.get("file_path") or inp.get("notebook_path") or ""
                if not fp:
                    continue
                rp = real(fp)
                if under_vault(rp) or is_memory(rp):
                    synced = True
                else:
                    edited.append(rp)

    out = {}

    # --- Check 1: vault/memory sync on a shipping turn (blocking once) ---
    if shipped and not synced:
        out["decision"] = "block"
        out["reason"] = (
            "STOP-GATE (vault+memory sync): this turn shipped a milestone (commit / "
            "push / PR) but did not update the Obsidian vault or memory.\n\n"
            "Read the vault's VAULT_AGENT_RULES.md and route the update per its "
            "classification rules — do NOT route from memory, and do not guess note "
            "filenames; open the project's existing note family and match it. Then "
            "run the baseline-aware lint command given in the vault's CLAUDE.md.\n\n"
            "Save a memory entry only if a durable rule or pointer emerged — not for "
            "anything the repo or the vault already records.\n\n"
            "If you have genuinely assessed there is nothing worth recording, say so "
            "in one line and stop."
        )

    # --- Check 3: sweep empty phantom notes (opt-in; it DELETES files) ---
    try:
        removed = (
            _sweep_empty_vault_notes(vault)
            if os.environ.get("CLAUDE_VAULT_SWEEP") == "1"
            else []
        )
        if removed:
            names = ", ".join(removed[:8])
            extra = f" (+{len(removed) - 8} more)" if len(removed) > 8 else ""
            out["systemMessage"] = (
                out.get("systemMessage", "")
                + ("\n" if out.get("systemMessage") else "")
                + f"🧹 Removed {len(removed)} empty phantom vault note(s): {names}{extra}."
            ).strip()
    except Exception:
        pass

    # --- Check 2: dirty work tree for repos edited this turn (warn only) ---
    try:
        dirty = _dirty_repos(set(edited))
        if dirty:
            parts = []
            for root, n in dirty:
                label = root.replace(home, "~")
                parts.append(f"{label} ({n})")
            out["systemMessage"] = (
                "⚠ Left uncommitted edits in: " + ", ".join(parts)
                + ". Say \"commit it\" if you want them committed."
            )
    except Exception:
        pass  # warning is best-effort; never break the gate

    if out:
        print(json.dumps(out))


def _sweep_empty_vault_notes(vault):
    """Delete *.md files in the vault whose content is empty/whitespace-only
    (phantom notes Obsidian materialises from unresolved [[slug]] links). Skips
    dotted dirs (.obsidian/.trash). Returns the basenames removed.

    Only called when CLAUDE_VAULT_SWEEP=1 — it is a real delete, not a move."""
    removed = []
    for root, dirs, files in os.walk(vault):
        dirs[:] = [d for d in dirs if not d.startswith(".")]
        for fn in files:
            if not fn.endswith(".md"):
                continue
            fp = os.path.join(root, fn)
            try:
                if os.path.getsize(fp) > 4:  # cheap pre-filter
                    continue
                with open(fp, encoding="utf-8") as fh:
                    if fh.read().strip():
                        continue
                os.remove(fp)
                removed.append(fn)
            except OSError:
                continue
    return sorted(removed)


def _dirty_repos(files):
    """Given real file paths edited this turn, return [(repo_root, count)] for
    repos where those files are still uncommitted. Best-effort, fast, quiet."""
    def git(args, cwd):
        return subprocess.run(
            ["git"] + args, cwd=cwd, capture_output=True, text=True, timeout=5
        )

    root_cache = {}
    per_repo = {}
    for rp in list(files)[:60]:
        d = os.path.dirname(rp)
        if not os.path.isdir(d):
            continue
        root = root_cache.get(d)
        if root is None:
            try:
                r = git(["rev-parse", "--show-toplevel"], d)
            except Exception:
                root_cache[d] = ""
                continue
            root = r.stdout.strip() if r.returncode == 0 else ""
            root_cache[d] = root
        if not root:
            continue
        try:
            st = git(["status", "--porcelain", "--", rp], root)
        except Exception:
            continue
        if st.returncode == 0 and st.stdout.strip():
            per_repo[root] = per_repo.get(root, 0) + 1
    return sorted(per_repo.items())


if __name__ == "__main__":
    try:
        main()
    except Exception:
        pass
