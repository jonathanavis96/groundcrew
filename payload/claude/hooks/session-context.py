#!/usr/bin/env python3
"""SessionStart hook: inject a markdown file as session context.

    python3 ~/.claude/hooks/session-context.py <file.md>

Replaces the `jq -Rs '{hookSpecificOutput:...}'` one-liner that is usually used
for this. jq does not exist on a stock Windows box, and a hook that silently
fails is worse than no hook — this is stdlib Python, so it behaves identically
on macOS, Linux and native Windows.

Fails open: a missing or unreadable file exits 0 and injects nothing.

Keep the injected file SHORT. Everything here is paid for on every turn of
every session — that is the whole reason `references/on-demand.md` exists.
"""
from __future__ import annotations

import json
import sys
from pathlib import Path


def main() -> int:
    if len(sys.argv) < 2:
        return 0
    try:
        text = Path(sys.argv[1]).expanduser().read_text(encoding="utf-8")
    except (OSError, UnicodeDecodeError):
        return 0
    if not text.strip():
        return 0
    json.dump(
        {
            "hookSpecificOutput": {
                "hookEventName": "SessionStart",
                "additionalContext": text,
            }
        },
        sys.stdout,
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
