#!/usr/bin/env python3
"""PreToolUse guard: keep WebFetch, remove its licence to draw conclusions.

WebFetch does not hand the page to the model that asked for it. A smaller
secondary model reads it, answers the caller's prompt, and only that answer
reaches the main conversation.

Measured on this machine 2026-08-09, same page, same underlying question:

  vague prompt ("research this page, key facts about the largest African
  economies")        -> 3/3 runs ranked Nigeria > Egypt > South Africa when
                        the true order is the exact reverse; one run asserted
                        both "Nigeria is largest by a substantial margin" and
                        "Nigeria lags behind" in the same answer; one invented
                        a "$2.44 trillion" aggregate that appears nowhere on
                        the page.
  extraction-only    -> 2/2 runs exact. 15/15 table cells verbatim, correct
                        ordering, nothing invented.

Retrieval is reliable; synthesis is not. So rather than block the tool, this
rewrites the caller's prompt into an extraction request before it runs. The
figures come back verbatim and the *calling* model does the reasoning, with the
evidence in its own context where it can be checked.

Modes (env CLAUDE_WEBFETCH_MODE): "rewrite" (default) | "deny" | "off".
Domains in ~/.claude/webfetch-allow.txt pass through untouched.
"""
from __future__ import annotations

import json
import os
import sys
from pathlib import Path
from urllib.parse import urlparse

# WebFetch is the documented way to read these and fetchurl cannot: they need
# the session's own login rather than an anonymous curl.
BUILTIN_ALLOW = {"claude.ai", "localhost", "127.0.0.1"}

ALLOW_FILE = Path.home() / ".claude" / "webfetch-allow.txt"

PREAMBLE = """EXTRACTION ONLY — this is a retrieval request, not an analysis request.

Return content that is present on the page, quoted or reproduced as it appears.

Do NOT: summarise, rank, order, sort, compare, rate, aggregate, total, average,
compute, infer, or draw any conclusion. Do NOT add narrative, framing or
concluding sentences. Do NOT describe anything as largest/best/leading/fastest
or otherwise characterise what you return — reproduce it and stop.

Reproduce numbers, names and quotes exactly as written, with their labels,
units and column headers, so they can be checked against the source. Preserve
the order in which the page presents them.

If something the request asks for is not on the page, write "NOT PRESENT" for
it. Never supply it from prior knowledge, and never estimate it.

Extract what is needed to answer the following request, but do not answer it —
the caller will do that from what you return.

REQUEST: """

DENY_MESSAGE = (
    "WebFetch is set to deny on this machine (CLAUDE_WEBFETCH_MODE=deny).\n\n"
    "Use `fetchurl {url}` instead — it puts the real extracted text in your own "
    "context, supports --grep PATTERN, and reports bot walls instead of letting you "
    "infer content."
)

NUDGE = (
    "WebFetch returns a secondary model's extraction, not the page. Figures and quotes "
    "in this result are reproduced verbatim and can be trusted as retrieval, but any "
    "ordering, ranking, superlative or conclusion is yours to derive — do not inherit "
    "one. For research where completeness matters, use `fetchurl {url}` instead, which "
    "puts the full text in your own context."
)


def allowed_domains() -> set[str]:
    domains = set(BUILTIN_ALLOW)
    try:
        for line in ALLOW_FILE.read_text(encoding="utf-8").splitlines():
            line = line.split("#", 1)[0].strip().lower()
            if line:
                domains.add(line)
    except (OSError, UnicodeDecodeError):
        pass
    return domains


def emit(payload: dict) -> int:
    json.dump(payload, sys.stdout)
    return 0


def main() -> int:
    mode = os.environ.get("CLAUDE_WEBFETCH_MODE", "rewrite").lower()
    if mode == "off" or os.environ.get("CLAUDE_ALLOW_WEBFETCH") == "1":
        return 0

    try:
        data = json.load(sys.stdin)
    except (json.JSONDecodeError, ValueError):
        return 0  # Never break a tool call over a malformed payload.

    if data.get("tool_name") != "WebFetch":
        return 0

    tool_input = dict(data.get("tool_input") or {})
    url = tool_input.get("url", "")
    # urlparse splits "https://evil.com\@claude.ai/" at the "@" and reports
    # claude.ai, while a WHATWG parser (what actually fetches) treats "\" as
    # "/" and goes to evil.com. Never let such a URL ride the allowlist.
    host = "" if "\\" in url else (urlparse(url).hostname or "").lower()
    if host and any(host == d or host.endswith("." + d) for d in allowed_domains()):
        return 0

    if mode == "deny":
        return emit({
            "hookSpecificOutput": {
                "hookEventName": "PreToolUse",
                "permissionDecision": "deny",
                "permissionDecisionReason": DENY_MESSAGE.format(url=url or "<url>"),
            }
        })

    original = (tool_input.get("prompt") or "").strip()
    if original.startswith("EXTRACTION ONLY"):
        return 0  # Already constrained; don't nest the preamble.
    tool_input["prompt"] = PREAMBLE + (original or "Return the main content of the page.")

    return emit({
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "allow",
            "permissionDecisionReason": "Constrained to extraction-only.",
            "updatedInput": tool_input,
            "additionalContext": NUDGE.format(url=url or "the URL"),
        }
    })


if __name__ == "__main__":
    sys.exit(main())
