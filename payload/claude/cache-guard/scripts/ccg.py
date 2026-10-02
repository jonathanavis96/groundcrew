#!/usr/bin/env python3
"""
Claude Cache Guard (CCG)

Deterministic, session-id-scoped handoff + cold-cache prompt guard for Claude Code.
No network calls. No model calls. Python stdlib only.

Hook subcommands read Claude Code hook JSON from stdin and write either nothing
(success/no-op) or a Claude Code JSON decision object to stdout.
"""
from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import os
import re
import subprocess
import sys
import tempfile
import time
from collections.abc import Iterable
from pathlib import Path
from typing import Any

DEFAULT_CONFIG: dict[str, Any] = {
    "ttl_seconds": 3600,
    "warn_after_seconds": 3300,
    "cold_after_seconds": 3570,
    "toast_cooldown_seconds": 1800,
    "watcher_poll_seconds": 15,
    "min_context_tokens_to_block": 100000,
    "min_transcript_bytes_to_block": 650000,
    "handoff_max_chars": 9500,
    "jsonl_tail_bytes": 2500000,
    "recent_user_prompts": 8,
    "recent_assistant_messages": 6,
    "recent_commands": 15,
    "recent_files": 80,
    "git_command_timeout_seconds": 2,
    "allow_bypass_phrase": "[cache-guard-bypass]",
    "allowed_cold_prompts": ["/clear", "/compact", "/exit", "/quit", "/help", "/hooks"],
    "notify_title": "Claude cache guard",
    "large_session_label_tokens": 100000,
    "stale_session_hours": 18,
    "pending_clear_max_age_seconds": 60,
}

BASE = Path(os.environ.get("CLAUDE_CACHE_GUARD_HOME", "~/.claude/cache-guard")).expanduser()
SESSIONS = BASE / "sessions"
HANDOFFS = BASE / "handoffs"
LATEST_BY_CWD = BASE / "latest-by-cwd"
LATEST_BY_ORIGIN = BASE / "latest-by-origin"
WARNINGS = BASE / "warnings"
LOGS = BASE / "logs"
ALLOW_NEXT = BASE / "allow-next"
PENDING_CLEAR = BASE / "pending-clear"


def utc_now() -> float:
    return time.time()


def iso(ts: float | None = None) -> str:
    return dt.datetime.fromtimestamp(ts if ts is not None else utc_now(), tz=dt.timezone.utc).isoformat(timespec="seconds")


def ensure_dirs() -> None:
    for p in [BASE, SESSIONS, HANDOFFS, LATEST_BY_CWD, LATEST_BY_ORIGIN, WARNINGS, LOGS, ALLOW_NEXT, PENDING_CLEAR]:
        p.mkdir(parents=True, exist_ok=True)


def log(msg: str) -> None:
    try:
        ensure_dirs()
        with (LOGS / "ccg.log").open("a", encoding="utf-8") as f:
            f.write(f"{iso()} {msg}\n")
    except Exception:
        pass


def safe_id(value: str) -> str:
    value = value or "unknown"
    safe = re.sub(r"[^A-Za-z0-9_.-]+", "_", value)[:100]
    digest = hashlib.sha1(value.encode("utf-8", "ignore")).hexdigest()[:10]
    return f"{safe}-{digest}"


def cwd_key(cwd: str) -> str:
    return hashlib.sha1((cwd or "").encode("utf-8", "ignore")).hexdigest()


def _read_proc_min(pid: int) -> tuple[str | None, int, bool | None]:
    """Return (comm, ppid, has_claudecode) for a pid from /proc, or (None, 0, None).

    has_claudecode is True/False if /proc/<pid>/environ is readable, else None.
    """
    try:
        data = Path(f"/proc/{pid}/stat").read_text(encoding="utf-8", errors="replace")
        lpar = data.index("(")
        rpar = data.rindex(")")
        comm = data[lpar + 1:rpar]
        rest = data[rpar + 2:].split()
        ppid = int(rest[1])
    except Exception:
        return None, 0, None
    cc: bool | None = None
    try:
        env = Path(f"/proc/{pid}/environ").read_bytes()
        cc = b"CLAUDECODE=" in env
    except Exception:
        cc = None
    return comm, ppid, cc


def claude_origin_id() -> str:
    """Stable identifier for the owning Claude Code process.

    This is the only reliable per-session link that survives `/clear`: the
    `claude` process resets context in place (same long-lived process fires both
    SessionEnd and the following SessionStart), so its PID is identical before and
    after the clear — yet differs across concurrently-running Claude Code sessions,
    even in the same cwd. `/clear` rotates session_id AND transcript_path and Claude
    Code exposes no previous-session id, so cwd alone cannot distinguish sessions.

    Resolution: walk the parent chain from the hook subprocess up to the `claude`
    process, identified by its comm, or as the CLAUDECODE boundary (descendants
    inherit CLAUDECODE=1; the `claude` process itself does not). Returns "" if it
    cannot be determined, so callers fall back to legacy cwd-scoped behaviour.

    `CCG_ORIGIN_OVERRIDE` forces the value (used by tests and as a manual escape).
    """
    override = os.environ.get("CCG_ORIGIN_OVERRIDE")
    if override:
        return f"ovr-{safe_id(override)}"
    try:
        pid = os.getppid()
        seen: set = set()
        boundary: int | None = None
        prev_cc: bool | None = True  # the immediate hook process is a CC subprocess
        for _ in range(40):
            if pid <= 1 or pid in seen:
                break
            seen.add(pid)
            comm, ppid, cc = _read_proc_min(pid)
            if comm is None:
                break
            if comm == "claude":
                return f"pid{pid}"
            if boundary is None and cc is False and prev_cc is True:
                boundary = pid
            if cc is not None:
                prev_cc = cc
            pid = ppid
        if boundary is not None:
            return f"pid{boundary}"
    except Exception as exc:
        log(f"claude_origin_id failed: {exc}")
    return ""


def current_tmux_session() -> str:
    """Name of the tmux session this process runs inside, or "" if none.

    Hooks run inside the Claude process, which inherits $TMUX when launched
    inside tmux (via claude-tmux / the dashboard's ttyd-session). Recording the
    real session name lets the dashboard tie a Claude session to its tmux session
    deterministically — so the "open terminal" link targets the right session and
    the OPEN/DESKTOP badge is correct regardless of cwd or chat name.
    """
    if not os.environ.get("TMUX"):
        return ""
    try:
        out = subprocess.check_output(
            ["tmux", "display-message", "-p", "#S"],
            stderr=subprocess.DEVNULL,
            timeout=2,
        )
        return out.decode().strip()
    except (subprocess.CalledProcessError, FileNotFoundError, subprocess.TimeoutExpired, OSError):
        return ""


def atomic_write_text(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile("w", delete=False, encoding="utf-8", dir=str(path.parent)) as tf:
        tf.write(text)
        tmp = Path(tf.name)
    tmp.replace(path)


def atomic_write_json(path: Path, data: dict[str, Any]) -> None:
    atomic_write_text(path, json.dumps(data, indent=2, sort_keys=True, ensure_ascii=False) + "\n")


def read_json(path: Path, default: dict[str, Any] | None = None) -> dict[str, Any]:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return dict(default or {})


def load_config() -> dict[str, Any]:
    ensure_dirs()
    cfg = dict(DEFAULT_CONFIG)
    cfg_path = BASE / "config.json"
    if cfg_path.exists():
        try:
            user_cfg = json.loads(cfg_path.read_text(encoding="utf-8"))
            if isinstance(user_cfg, dict):
                cfg.update(user_cfg)
        except Exception as exc:
            log(f"config read failed: {exc}")
    return cfg


def read_hook_input() -> dict[str, Any]:
    raw = sys.stdin.read()
    if not raw.strip():
        return {}
    try:
        obj = json.loads(raw)
        if isinstance(obj, dict):
            return obj
    except Exception as exc:
        log(f"bad hook json: {exc}; raw={raw[:500]!r}")
    return {}


def session_paths(session_id: str) -> tuple[Path, Path, Path]:
    sid = safe_id(session_id)
    return SESSIONS / f"{sid}.json", HANDOFFS / f"{sid}.md", HANDOFFS / f"{sid}.json"


def transcript_size(path: str | None) -> int:
    if not path:
        return 0
    try:
        return Path(path).expanduser().stat().st_size
    except Exception:
        return 0


def read_jsonl_tail(path: str | None, max_bytes: int) -> list[dict[str, Any]]:
    if not path:
        return []
    p = Path(path).expanduser()
    if not p.exists():
        return []
    try:
        size = p.stat().st_size
        with p.open("rb") as f:
            if size > max_bytes:
                f.seek(size - max_bytes)
                f.readline()  # drop possible partial first line
            data = f.read().decode("utf-8", "replace")
    except Exception as exc:
        log(f"read_jsonl_tail failed {p}: {exc}")
        return []
    out: list[dict[str, Any]] = []
    for line in data.splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            obj = json.loads(line)
            if isinstance(obj, dict):
                out.append(obj)
        except Exception:
            continue
    return out


def truncate(s: str, limit: int) -> str:
    s = re.sub(r"\s+", " ", s or "").strip()
    if len(s) <= limit:
        return s
    return s[: max(0, limit - 20)].rstrip() + f" … [+{len(s)-limit} chars]"


def iter_dicts(obj: Any) -> Iterable[dict[str, Any]]:
    if isinstance(obj, dict):
        yield obj
        for v in obj.values():
            yield from iter_dicts(v)
    elif isinstance(obj, list):
        for item in obj:
            yield from iter_dicts(item)


def text_from_content(content: Any, include_tool_results: bool = False) -> str:
    parts: list[str] = []
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        for item in content:
            if isinstance(item, str):
                parts.append(item)
            elif isinstance(item, dict):
                typ = item.get("type")
                if typ == "text" and isinstance(item.get("text"), str):
                    parts.append(item["text"])
                elif typ == "tool_result" and include_tool_results or typ not in {"tool_use", "tool_result"}:
                    parts.append(text_from_content(item.get("content"), include_tool_results=False))
    elif isinstance(content, dict):
        if isinstance(content.get("text"), str):
            return content["text"]
        return text_from_content(content.get("content"), include_tool_results=include_tool_results)
    return "\n".join(p for p in parts if p)


def get_role(obj: dict[str, Any]) -> str | None:
    for key in ("role", "type"):
        val = obj.get(key)
        if val in {"user", "assistant", "system"}:
            return val
    msg = obj.get("message")
    if isinstance(msg, dict):
        val = msg.get("role") or msg.get("type")
        if val in {"user", "assistant", "system"}:
            return val
    return None


def get_message_text(obj: dict[str, Any]) -> str:
    if "message" in obj and isinstance(obj["message"], dict):
        return text_from_content(obj["message"].get("content"))
    return text_from_content(obj.get("content"))


def extract_recent_messages(entries: list[dict[str, Any]], cfg: dict[str, Any]) -> tuple[list[str], list[str]]:
    users: list[str] = []
    assistants: list[str] = []
    for obj in entries:
        role = get_role(obj)
        text = get_message_text(obj)
        if not text:
            continue
        if role == "user":
            users.append(truncate(text, 500))
        elif role == "assistant":
            assistants.append(truncate(text, 700))
    return users[-int(cfg["recent_user_prompts"]):], assistants[-int(cfg["recent_assistant_messages"]):]


def extract_tool_activity(entries: list[dict[str, Any]], cfg: dict[str, Any]) -> tuple[list[str], list[str]]:
    files: list[str] = []
    commands: list[str] = []
    seen_files = set()
    for obj in entries:
        for d in iter_dicts(obj):
            # Claude content tool_use shape
            name = d.get("name") or d.get("tool_name")
            inp = d.get("input") if isinstance(d.get("input"), dict) else d.get("tool_input")
            if not isinstance(inp, dict):
                continue
            if name in {"Write", "Edit", "MultiEdit", "NotebookEdit"}:
                fp = inp.get("file_path") or inp.get("path") or inp.get("notebook_path")
                if isinstance(fp, str) and fp not in seen_files:
                    seen_files.add(fp)
                    files.append(fp)
            if name == "Bash":
                cmd = inp.get("command")
                if isinstance(cmd, str):
                    commands.append(truncate(cmd, 220))
    return files[-int(cfg["recent_files"]):], commands[-int(cfg["recent_commands"]):]


def extract_latest_usage(entries: list[dict[str, Any]]) -> dict[str, int]:
    latest: dict[str, int] = {}
    keys = {
        "input_tokens",
        "cache_read_input_tokens",
        "cache_creation_input_tokens",
        "output_tokens",
    }
    for obj in entries:
        for d in iter_dicts(obj):
            if any(k in d for k in keys):
                usage = {k: int(d.get(k) or 0) for k in keys if isinstance(d.get(k), int) or str(d.get(k) or "").isdigit()}
                if usage:
                    latest = usage
    total = int(latest.get("input_tokens", 0)) + int(latest.get("cache_read_input_tokens", 0)) + int(latest.get("cache_creation_input_tokens", 0))
    if total:
        latest["estimated_context_tokens"] = total
    return latest


def run_cmd(args: list[str], cwd: str | None, timeout: int, max_chars: int = 12000) -> str:
    try:
        cp = subprocess.run(args, cwd=cwd if cwd and Path(cwd).exists() else None, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=timeout)
        return (cp.stdout or "").strip()[:max_chars]
    except Exception as exc:
        return f"[unavailable: {exc}]"


def git_snapshot(cwd: str | None, cfg: dict[str, Any]) -> dict[str, str]:
    timeout = int(cfg.get("git_command_timeout_seconds", 2))
    if not cwd or not Path(cwd).exists():
        return {"cwd": cwd or "", "git": "cwd unavailable"}
    inside = run_cmd(["git", "rev-parse", "--is-inside-work-tree"], cwd, timeout, 100).strip()
    if inside != "true":
        return {"cwd": cwd, "git": "not a git work tree"}
    return {
        "cwd": cwd,
        "root": run_cmd(["git", "rev-parse", "--show-toplevel"], cwd, timeout, 500),
        "branch": run_cmd(["git", "branch", "--show-current"], cwd, timeout, 500),
        "head": run_cmd(["git", "log", "-1", "--oneline"], cwd, timeout, 500),
        "status_short": run_cmd(["git", "status", "--short"], cwd, timeout, 8000),
        "diff_names": run_cmd(["git", "diff", "--name-only"], cwd, timeout, 8000),
    }


def bullet_list(items: list[str], empty: str = "None captured.") -> str:
    if not items:
        return empty
    return "\n".join(f"- {item}" for item in items)


def build_handoff(data: dict[str, Any], cfg: dict[str, Any]) -> tuple[str, dict[str, Any]]:
    session_id = str(data.get("session_id") or "unknown")
    transcript_path = str(data.get("transcript_path") or "")
    cwd = str(data.get("cwd") or "")
    entries = read_jsonl_tail(transcript_path, int(cfg["jsonl_tail_bytes"]))
    usage = extract_latest_usage(entries)
    users, assistants = extract_recent_messages(entries, cfg)
    files, commands = extract_tool_activity(entries, cfg)
    git = git_snapshot(cwd, cfg)
    tsize = transcript_size(transcript_path)
    last_assistant = data.get("last_assistant_message")
    if isinstance(last_assistant, str) and last_assistant.strip():
        if not assistants or truncate(last_assistant, 700) != assistants[-1]:
            assistants.append(truncate(last_assistant, 700))
            assistants = assistants[-int(cfg["recent_assistant_messages"]):]
    est_tokens = int(usage.get("estimated_context_tokens") or 0)

    md = f"""# Claude Code handoff — deterministic cache guard

Generated: {iso()}  
Session ID: `{session_id}`  
CWD: `{cwd}`  
Transcript: `{transcript_path}`  
Transcript size: {tsize:,} bytes  
Estimated current context tokens from latest transcript usage: {est_tokens if est_tokens else 'unknown'}

## Resume instruction
You are resuming after `/clear` or before avoiding a cold-cache rewarm. Use this compact handoff first. Do not paste or load the full transcript unless a specific detail is missing. The full transcript path above is the lossless backing store for targeted lookup only.

## Git snapshot
- Root: `{git.get('root','')}`
- Branch: `{git.get('branch','')}`
- HEAD: `{git.get('head','')}`

### Git status --short
```text
{git.get('status_short','') or 'clean or unavailable'}
```

### Git diff --name-only
```text
{git.get('diff_names','') or 'none or unavailable'}
```

## Recently touched files from Claude tool calls
{bullet_list(files)}

## Recent bash commands
{bullet_list(commands)}

## Recent user prompts
{bullet_list(users)}

## Recent assistant messages
{bullet_list(assistants)}

## Safety and cost rules for continuation
- Keep context small; read only the exact files or transcript ranges needed.
- Keep using session-id-scoped state. Do not fall back to global latest transcript if multiple Claude sessions may run.
- Prefer deterministic extraction over model-generated handoffs unless explicitly requested.
- If context is unclear, inspect git status/diff and targeted transcript snippets instead of reloading the full old conversation.
"""
    max_chars = int(cfg["handoff_max_chars"])
    if len(md) > max_chars:
        # Preserve top and newest sections by clipping middle of recent messages last.
        md = md[: max_chars - 180] + f"\n\n[handoff clipped to {max_chars} chars; full transcript remains at {transcript_path}]\n"
    meta = {
        "generated_at": iso(),
        "session_id": session_id,
        "cwd": cwd,
        "transcript_path": transcript_path,
        "transcript_size_bytes": tsize,
        "usage": usage,
        "estimated_context_tokens": est_tokens,
        "files": files,
        "commands": commands,
        "git": git,
    }
    return md, meta


def write_handoff(data: dict[str, Any], cfg: dict[str, Any]) -> dict[str, Any]:
    ensure_dirs()
    session_id = str(data.get("session_id") or "unknown")
    _, md_path, meta_path = session_paths(session_id)
    md, meta = build_handoff(data, cfg)
    atomic_write_text(md_path, md)
    meta["handoff_path"] = str(md_path)
    atomic_write_json(meta_path, meta)
    cwd = str(data.get("cwd") or "")
    if cwd:
        atomic_write_json(LATEST_BY_CWD / f"{cwd_key(cwd)}.json", {
            "session_id": session_id,
            "cwd": cwd,
            "handoff_path": str(md_path),
            "updated_at": iso(),
        })
    origin = claude_origin_id()
    if origin:
        # Session-specific latest pointer: survives /clear, never collides with a
        # concurrent session in the same cwd. This is the robust restore fallback.
        atomic_write_json(LATEST_BY_ORIGIN / f"{origin}.json", {
            "session_id": session_id,
            "cwd": cwd,
            "origin": origin,
            "handoff_path": str(md_path),
            "updated_at": iso(),
            "updated_at_ts": utc_now(),
        })
    update_session_state(data, extra={
        "handoff_path": str(md_path),
        "handoff_generated_at": meta["generated_at"],
        "estimated_context_tokens": meta.get("estimated_context_tokens", 0),
        "transcript_size_bytes": meta.get("transcript_size_bytes", 0),
    })
    return meta


def update_session_state(data: dict[str, Any], extra: dict[str, Any] | None = None) -> dict[str, Any]:
    ensure_dirs()
    sid = str(data.get("session_id") or "unknown")
    state_path, _, _ = session_paths(sid)
    state = read_json(state_path, {})
    now = utc_now()
    state.update({
        "session_id": sid,
        "session_key": safe_id(sid),
        "cwd": str(data.get("cwd") or state.get("cwd") or ""),
        "transcript_path": str(data.get("transcript_path") or state.get("transcript_path") or ""),
        "last_hook_event": str(data.get("hook_event_name") or state.get("last_hook_event") or ""),
        "updated_at": iso(now),
        "updated_at_ts": now,
    })
    # Tie this Claude session to its tmux session (if any) so the dashboard can
    # target the right session for open/clear/end. Preserve a prior value rather
    # than clobbering with "" — every hook event runs in the same process so $TMUX
    # is stable, but be defensive.
    tmux_name = current_tmux_session()
    if tmux_name:
        state["tmux_session"] = tmux_name
    event = str(data.get("hook_event_name") or "")
    if event in {"Stop", "SessionEnd", "PreCompact"}:
        state["last_model_activity_at"] = iso(now)
        state["last_model_activity_ts"] = now
    if event == "UserPromptSubmit":
        state["last_user_prompt_at"] = iso(now)
        state["last_user_prompt_ts"] = now
    if event == "SessionEnd":
        state["ended_at"] = iso(now)
        state["ended_at_ts"] = now
        if data.get("reason"):
            state["end_reason"] = data.get("reason")
    if extra:
        state.update(extra)
    # refresh size cheaply
    state["transcript_size_bytes"] = transcript_size(state.get("transcript_path")) or int(state.get("transcript_size_bytes") or 0)
    atomic_write_json(state_path, state)
    return state


def is_allowed_prompt(prompt: str, cfg: dict[str, Any]) -> bool:
    p = (prompt or "").strip()
    if not p:
        return True
    allowed = cfg.get("allowed_cold_prompts") or []
    return any(p == cmd or p.startswith(cmd + " ") for cmd in allowed)


def consume_allow_next(session_id: str) -> bool:
    p = ALLOW_NEXT / f"{safe_id(session_id)}.allow"
    if p.exists():
        try:
            p.unlink()
        except Exception:
            pass
        return True
    return False


def is_large_session(state: dict[str, Any], cfg: dict[str, Any]) -> bool:
    tokens = int(state.get("estimated_context_tokens") or 0)
    bytes_ = int(state.get("transcript_size_bytes") or 0)
    token_threshold = int(cfg["min_context_tokens_to_block"])
    byte_threshold = int(cfg["min_transcript_bytes_to_block"])
    return tokens >= token_threshold or bytes_ >= byte_threshold


def cold_age_seconds(state: dict[str, Any]) -> float | None:
    ts = state.get("last_model_activity_ts") or state.get("updated_at_ts")
    if ts is None:
        return None
    try:
        return utc_now() - float(ts)
    except Exception:
        return None


def hook_stoplike(command_name: str) -> int:
    cfg = load_config()
    data = read_hook_input()
    try:
        write_handoff(data, cfg)
    except Exception as exc:
        log(f"{command_name}: write_handoff failed: {exc}")
        update_session_state(data)
    return 0


def hook_prompt() -> int:
    cfg = load_config()
    data = read_hook_input()
    sid = str(data.get("session_id") or "unknown")
    prompt = str(data.get("prompt") or "")
    state_path, _, _ = session_paths(sid)
    state = read_json(state_path, {})

    # Always allow control commands needed to escape/inspect the state.
    if is_allowed_prompt(prompt, cfg):
        update_session_state(data)
        return 0

    bypass_phrase = str(cfg.get("allow_bypass_phrase") or "")
    if (bypass_phrase and bypass_phrase in prompt) or consume_allow_next(sid):
        update_session_state(data, extra={"last_bypass_at": iso(), "last_bypass_prompt_prefix": truncate(prompt, 120)})
        return 0

    # If state is missing, create it and allow. We do not want a first hook install to trap the user.
    if not state:
        update_session_state(data)
        return 0

    age = cold_age_seconds(state)
    cold = age is not None and age >= float(cfg["cold_after_seconds"])
    large = is_large_session(state, cfg)

    if cold and large:
        # Ensure a deterministic handoff exists before blocking.
        handoff_path = state.get("handoff_path")
        try:
            if not handoff_path or not Path(str(handoff_path)).expanduser().exists():
                meta = write_handoff(data, cfg)
                handoff_path = meta.get("handoff_path")
        except Exception as exc:
            log(f"hook_prompt: ensure handoff failed: {exc}")

        tokens = state.get("estimated_context_tokens") or "unknown"
        bytes_ = int(state.get("transcript_size_bytes") or 0)
        reason = (
            "Cache guard blocked this prompt before Claude processed it. "
            f"This session appears cold ({int(age or 0)}s idle) and large "
            f"(~{tokens} context tokens, {bytes_:,} transcript bytes).\n\n"
            "To avoid paying to re-warm the old full context:\n"
            "- In the terminal: run `/new` (or `/clear`) to start a fresh session\n"
            "- In the Claude app: start a new chat\n"
            "The SessionStart hook will automatically inject the compact handoff either way.\n\n"
            f"Handoff: {handoff_path or 'not found, but transcript is recorded in cache-guard state'}\n\n"
            f"To intentionally continue the cold large session anyway, resubmit with `{bypass_phrase}` included once."
        )
        out = {"decision": "block", "reason": reason, "suppressOriginalPrompt": True}
        print(json.dumps(out, ensure_ascii=False))
        notify_title = str(cfg.get("notify_title") or "Claude cache guard")
        notify_body = (
            f"Session blocked — cold ({int(age or 0)}s idle) + large ({bytes_:,} bytes).\n"
            "Terminal: /new  |  App: start a new chat."
        )
        # Windows toast — visible on desktop regardless of which Claude UI is open.
        try:
            make_notification(notify_title, notify_body)
        except Exception as exc:
            log(f"hook_prompt: block toast failed: {exc}")
        # Optional second channel: set "notify_command" in config.json to any
        # argv list, e.g. ["/path/to/push", "--title"]. Title and body are
        # appended as the final two arguments. Left unset, nothing else fires.
        try:
            extra = cfg.get("notify_command") or []
            if isinstance(extra, list) and extra:
                subprocess.Popen(
                    [str(a) for a in extra] + [notify_title, notify_body],
                    stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                )
        except Exception as exc:
            log(f"hook_prompt: notify_command failed: {exc}")
        return 0

    update_session_state(data)
    return 0


def hook_session_start() -> int:
    cfg = load_config()
    data = read_hook_input()
    sid = str(data.get("session_id") or "unknown")
    source = str(data.get("source") or "")
    update_session_state(data)
    if source != "clear":
        return 0
    cwd = str(data.get("cwd") or "")
    origin = claude_origin_id()
    _, md_path, _ = session_paths(sid)
    handoff = ""

    # 1. Same session_id handoff (rare after /clear, which usually rotates the id).
    if md_path.exists():
        handoff = md_path.read_text(encoding="utf-8", errors="replace")

    # 2. Fresh consume-once pending-clear pointer (default <=60s old). Prefer the
    #    origin-keyed pointer (session-specific, survives the session_id rotation)
    #    and fall back to the legacy cwd-keyed one for back-compat.
    if not handoff.strip():
        max_age = float(cfg.get("pending_clear_max_age_seconds", 60))
        pend_keys = [k for k in (origin, cwd_key(cwd) if cwd else None) if k]
        for key in pend_keys:
            pend_path = PENDING_CLEAR / f"{key}.json"
            pend = read_json(pend_path, {})
            if not pend:
                continue
            ts = pend.get("timestamp_ts")
            try:
                fresh = ts is not None and (utc_now() - float(ts)) <= max_age
            except Exception:
                fresh = False
            if fresh:
                hp = pend.get("handoff_path")
                if hp and Path(str(hp)).exists():
                    handoff = Path(str(hp)).read_text(encoding="utf-8", errors="replace")
            # Consume the pointer either way so a stale one can never be reused.
            try:
                pend_path.unlink()
            except Exception:
                pass
            if handoff.strip():
                break

    # 3. Last resort: origin-scoped latest handoff (session-specific — NOT the
    #    cwd-shared latest, which a concurrent same-cwd session may have written).
    if not handoff.strip() and origin:
        pointer = read_json(LATEST_BY_ORIGIN / f"{origin}.json", {})
        ts = pointer.get("updated_at_ts")
        try:
            stale_cutoff = float(cfg.get("stale_session_hours", 18)) * 3600
            recent = ts is None or (utc_now() - float(ts)) <= stale_cutoff
        except Exception:
            recent = True
        hp = pointer.get("handoff_path")
        if recent and hp and Path(str(hp)).exists():
            handoff = Path(str(hp)).read_text(encoding="utf-8", errors="replace")

    # 4. Final legacy fallback: cwd-scoped latest (only when origin is undetectable;
    #    may pick another same-cwd session, but never the global latest transcript).
    if not handoff.strip() and cwd:
        pointer = read_json(LATEST_BY_CWD / f"{cwd_key(cwd)}.json", {})
        hp = pointer.get("handoff_path")
        if hp and Path(str(hp)).exists():
            handoff = Path(str(hp)).read_text(encoding="utf-8", errors="replace")

    if not handoff.strip():
        return 0
    max_chars = int(cfg["handoff_max_chars"])
    handoff = handoff[:max_chars]
    out = {
        "hookSpecificOutput": {
            "hookEventName": "SessionStart",
            "additionalContext": handoff,
        }
    }
    print(json.dumps(out, ensure_ascii=False))
    return 0


def write_pending_clear(data: dict[str, Any], meta: dict[str, Any] | None = None) -> None:
    """Consume-once restore pointer for /clear.

    Lets SessionStart(clear) find the correct handoff even though Claude Code
    rotates the session_id after /clear. Keyed by the owning Claude Code process
    (origin) when detectable — so two concurrent sessions in the SAME cwd never
    clobber each other's pointer — and falls back to the cwd hash otherwise.
    """
    cwd = str(data.get("cwd") or "")
    origin = claude_origin_id()
    key = origin or (cwd_key(cwd) if cwd else "")
    if not key:
        return
    sid = str(data.get("session_id") or "unknown")
    handoff_path = ""
    if meta and meta.get("handoff_path"):
        handoff_path = str(meta.get("handoff_path"))
    else:
        _, md_path, _ = session_paths(sid)
        if md_path.exists():
            handoff_path = str(md_path)
    now = utc_now()
    atomic_write_json(PENDING_CLEAR / f"{key}.json", {
        "session_id": sid,
        "cwd": cwd,
        "origin": origin,
        "transcript_path": str(data.get("transcript_path") or ""),
        "handoff_path": handoff_path,
        "timestamp": iso(now),
        "timestamp_ts": now,
    })


def hook_session_end() -> int:
    cfg = load_config()
    data = read_hook_input()
    meta: dict[str, Any] = {}
    try:
        meta = write_handoff(data, cfg)
    except Exception as exc:
        log(f"session_end handoff failed: {exc}")
        update_session_state(data)
    # Drop a fresh consume-once pointer so post-/clear restore is session-safe.
    reason = str(data.get("reason") or "")
    if reason in {"clear", ""}:
        try:
            write_pending_clear(data, meta)
        except Exception as exc:
            log(f"session_end pending-clear failed: {exc}")
    return 0


def make_notification(title: str, body: str) -> bool:
    # Optional user-supplied notifier: set CCG_NOTIFY_HELPER to anything
    # executable that takes (title, body).
    helper_path = os.environ.get("CCG_NOTIFY_HELPER", "")
    if helper_path:
        helper = Path(helper_path).expanduser()
        if helper.exists() and os.access(str(helper), os.X_OK):
            try:
                subprocess.Popen([str(helper), title, body], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                return True
            except Exception as exc:
                log(f"notify helper failed: {exc}")
    # Dependency-free Windows toast. Works from WSL and from native Windows,
    # where "powershell.exe" resolves to PowerShell itself.
    try:
        ps = r'''
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
$n = New-Object System.Windows.Forms.NotifyIcon
$n.Icon = [System.Drawing.SystemIcons]::Information
$n.BalloonTipTitle = $env:CCG_TOAST_TITLE
$n.BalloonTipText = $env:CCG_TOAST_BODY
$n.Visible = $true
$n.ShowBalloonTip(10000)
Start-Sleep -Seconds 11
$n.Dispose()
'''
        env = os.environ.copy()
        env["CCG_TOAST_TITLE"] = title
        env["CCG_TOAST_BODY"] = body
        subprocess.Popen(["powershell.exe", "-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", ps], env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        return True
    except Exception as exc:
        log(f"powershell toast failed: {exc}")
    return False


def _watch_session(path: Path, cfg: dict[str, Any], now: float) -> bool:
    """Warn for one session file. True when a warning was sent."""
    state = read_json(path, {})
    sid = state.get("session_id") or path.stem
    ended_ts = state.get("ended_at_ts")
    if ended_ts and now - float(ended_ts) > float(cfg["stale_session_hours"]) * 3600:
        return False
    age = cold_age_seconds(state)
    if age is None or not is_large_session(state, cfg):
        return False
    warn_after = float(cfg["warn_after_seconds"])
    cold_after = float(cfg["cold_after_seconds"])
    if age < warn_after:
        return False
    stage = "cold" if age >= cold_after else "warming"
    warn_file = WARNINGS / f"{safe_id(str(sid))}.{stage}.json"
    prev = read_json(warn_file, {})
    if prev.get("ts") and now - float(prev["ts"]) < float(cfg["toast_cooldown_seconds"]):
        return False
    title = str(cfg.get("notify_title") or "Claude cache guard")
    if stage == "warming":
        body = f"Cache nearly cold for {state.get('cwd','')}. Handoff ready. Consider /clear if you pause."
    else:
        body = "Cache is cold for a large Claude session. Next normal prompt will be blocked; run /clear to auto-restore handoff."
    sent = make_notification(title, body)
    if not sent:
        print(f"{title}: {body}", file=sys.stderr)
    atomic_write_json(warn_file, {"ts": now, "at": iso(now), "stage": stage, "session_id": sid})
    return sent


def watcher_once() -> int:
    cfg = load_config()
    now = utc_now()
    warned = 0
    for path in sorted(SESSIONS.glob("*.json")):
        # One corrupt session file (a non-numeric timestamp or token count) must
        # not stop the remaining sessions from being checked.
        try:
            warned += _watch_session(path, cfg, now)
        except (TypeError, ValueError) as exc:
            log(f"watcher: skipping {path.name}: {exc}")
    return warned


def watcher_loop() -> int:
    cfg = load_config()
    poll = float(cfg["watcher_poll_seconds"])
    while True:
        try:
            watcher_once()
        except KeyboardInterrupt:
            return 0
        except Exception as exc:
            log(f"watcher loop error: {exc}")
        time.sleep(max(2.0, poll))


def print_status() -> int:
    cfg = load_config()
    rows = []
    for path in sorted(SESSIONS.glob("*.json")):
        st = read_json(path, {})
        age = cold_age_seconds(st)
        rows.append({
            "session_id": st.get("session_id"),
            "cwd": st.get("cwd"),
            "idle_seconds": int(age) if age is not None else None,
            "tokens": st.get("estimated_context_tokens"),
            "bytes": st.get("transcript_size_bytes"),
            "large": is_large_session(st, cfg),
            "handoff_path": st.get("handoff_path"),
            "updated_at": st.get("updated_at"),
        })
    print(json.dumps(rows, indent=2, ensure_ascii=False))
    return 0


def write_default_config() -> int:
    ensure_dirs()
    cfg_path = BASE / "config.json"
    if cfg_path.exists():
        print(f"Config already exists: {cfg_path}")
        return 0
    atomic_write_json(cfg_path, DEFAULT_CONFIG)
    print(f"Wrote {cfg_path}")
    return 0


def print_hook_snippet(script_path: str) -> int:
    script = script_path
    snippet = {
        "hooks": {
            "Stop": [{"hooks": [{"type": "command", "command": script, "args": ["hook-stop"], "timeout": 10}]}],
            "PreCompact": [{"hooks": [{"type": "command", "command": script, "args": ["hook-precompact"], "timeout": 10}]}],
            "SessionEnd": [{"matcher": "clear", "hooks": [{"type": "command", "command": script, "args": ["hook-session-end"], "timeout": 10}]}],
            "SessionStart": [{"matcher": "clear", "hooks": [{"type": "command", "command": script, "args": ["hook-session-start"], "timeout": 10}]}],
            "UserPromptSubmit": [{"hooks": [{"type": "command", "command": script, "args": ["hook-prompt"], "timeout": 5}]}],
        }
    }
    print(json.dumps(snippet, indent=2))
    return 0


def self_test() -> int:
    ensure_dirs()
    fake = {
        "session_id": "test-session",
        "transcript_path": str(BASE / "test-transcript.jsonl"),
        "cwd": os.getcwd(),
        "hook_event_name": "Stop",
        "last_assistant_message": "Done. Next step is to run tests.",
    }
    transcript_lines = [
        {"type": "user", "message": {"role": "user", "content": "Implement a cache guard."}},
        {"type": "assistant", "message": {"role": "assistant", "content": [{"type": "text", "text": "I edited scripts/ccg.py"}], "usage": {"input_tokens": 120000, "cache_read_input_tokens": 0, "cache_creation_input_tokens": 0, "output_tokens": 1000}}},
        {"message": {"role": "assistant", "content": [{"type": "tool_use", "name": "Write", "input": {"file_path": "scripts/ccg.py"}}]}},
    ]
    atomic_write_text(Path(fake["transcript_path"]), "\n".join(json.dumps(x) for x in transcript_lines) + "\n")
    meta = write_handoff(fake, load_config())
    print(f"ok handoff={meta.get('handoff_path')}")
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Claude Cache Guard")
    sub = parser.add_subparsers(dest="cmd", required=True)
    for name in ["hook-stop", "hook-precompact"]:
        sub.add_parser(name)
    sub.add_parser("hook-session-end")
    sub.add_parser("hook-session-start")
    sub.add_parser("hook-prompt")
    sub.add_parser("watch")
    sub.add_parser("watch-once")
    sub.add_parser("status")
    sub.add_parser("init-config")
    p_snip = sub.add_parser("print-hook-snippet")
    p_snip.add_argument("script_path")
    sub.add_parser("self-test")
    args = parser.parse_args(argv)

    try:
        if args.cmd == "hook-stop":
            return hook_stoplike(args.cmd)
        if args.cmd == "hook-precompact":
            return hook_stoplike(args.cmd)
        if args.cmd == "hook-session-end":
            return hook_session_end()
        if args.cmd == "hook-session-start":
            return hook_session_start()
        if args.cmd == "hook-prompt":
            return hook_prompt()
        if args.cmd == "watch":
            return watcher_loop()
        if args.cmd == "watch-once":
            # watcher_once() returns how many toasts it sent; that is not an
            # exit status (1 warning would read as failure, 256 as success).
            watcher_once()
            return 0
        if args.cmd == "status":
            return print_status()
        if args.cmd == "init-config":
            return write_default_config()
        if args.cmd == "print-hook-snippet":
            return print_hook_snippet(args.script_path)
        if args.cmd == "self-test":
            return self_test()
    except Exception as exc:
        log(f"fatal {args.cmd}: {exc}")
        # Hook failure should be non-blocking unless we deliberately emitted a block JSON.
        return 0
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
