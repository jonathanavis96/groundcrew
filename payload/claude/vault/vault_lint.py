#!/usr/bin/env python3
"""Baseline-aware Obsidian vault linter.

The RULES below are one person's note model and are meant to be reshaped to fit
how you work. The part worth keeping intact is the BASELINE MECHANISM, which is
what makes any set of rules adoptable on a vault that already exists:

    python3 vault_lint.py <vault> --write-baseline lint-baseline.json
    python3 vault_lint.py <vault> --baseline lint-baseline.json

The first call records every finding your vault has today as "known". The second
reports only findings that are NEW relative to it. So you can turn on a strict
rule without having to fix a thousand old notes first — only what you touch from
now on has to be clean. Re-write the baseline deliberately, never casually.

Finding.key() deliberately excludes `detail`, so an edit that shifts a line count
does not re-fire a known warning as new.
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from dataclasses import asdict, dataclass
from pathlib import Path

HEADING_RE=re.compile(r"^(#{1,6})\s+(.+?)\s*$")
TASK_RE=re.compile(r"^\s*[-*]\s+\[([^\]])\]\s+(.+)$")
CREATED_RE=re.compile(r"➕\s+\d{4}-\d{2}-\d{2}")
NON_ACTIONABLE=re.compile(r"\b(optional|later|deferred|awaiting|waiting|pending|not urgent|only if|at go-live|future|consider|blocked)\b",re.IGNORECASE)
APPROVED={"now","next"}
IGNORE_PARTS={".obsidian","_Legacy Snapshot","_Agent_System"}
# Capture inbox: a scratch note where real checkboxes are appended on purpose and
# ticked off by hand, so it is exempt from the task rules by design. Point it at
# whatever your own capture note is called, or set it to "" to disable.
INBOX="Ideas/Quick Capture.md"
# Companion notes hang off a hub and are exempt from the hub rules: an archive or an
# append-only changelog is meant to be long. Matched as a suffix, so the separator
# (" - ", " — " or a plain space) doesn't matter.
COMPANION_SUFFIXES=('tasks','backlog','changelog','technical','reference','status archive','work log','build log')

@dataclass(frozen=True)
class Finding:
    severity:str; path:str; line:int; code:str; message:str; detail:str=''
    # `detail` carries anything that changes as a note is edited (line counts etc.) and is
    # deliberately NOT part of the key. Baseline keys must be stable: when the count lived
    # in `message`, editing an over-budget hub shifted 437 -> 447 and re-fired the SAME
    # known warning as "new" — punishing the very act of updating a stale hub.
    def key(self): return f"{self.severity}|{self.path}|{self.code}|{self.message}"

def probable_hub(path:Path,text:str)->bool:
    if path.parent.name!='Projects': return False
    n=path.stem.lower().replace('#u2014','-').replace('—','-')
    # Match the companion suffix however it was separated — " - Changelog", " — Changelog"
    # and plain "MyProject Changelog" are all the same kind of note. Matching only the
    # " - " form judged `MyProject Changelog.md` as a 700-line "hub" that must shrink,
    # when an append-only changelog is supposed to grow.
    if any(n.endswith(x) for x in COMPANION_SUFFIXES): return False
    return 'project/active' in text or 'status: active' in text or '## Current state' in text or '## Current status' in text

def audit(root:Path):
    out=[]
    for path in sorted(root.rglob('*.md')):
        if any(part in IGNORE_PARTS for part in path.parts): continue
        rel=path.relative_to(root).as_posix(); text=path.read_text(encoding='utf-8',errors='ignore'); lines=text.splitlines(); sec=''
        is_task_note=path.stem.endswith(' - Tasks')
        is_inbox=rel==INBOX
        for no,line in enumerate(lines,1):
            h=HEADING_RE.match(line)
            if h and len(h.group(1))<=2: sec=h.group(2).strip().lower()
            m=TASK_RE.match(line)
            if not m: continue
            status,task=m.groups()
            if status=='~': out.append(Finding('ERROR',rel,no,'undefined-status','Use [/] for In Progress; [~] is not configured.'))
            if status==' ' and not is_inbox:
                if is_task_note and sec not in APPROVED: out.append(Finding('ERROR',rel,no,'task-section',f'Open task in dedicated task note is under {sec or "no heading"}, not Now or Next.'))
                if NON_ACTIONABLE.search(task): out.append(Finding('ERROR',rel,no,'non-actionable','Waiting, optional, deferred or future work must be a plain bullet.'))
                if is_task_note and not CREATED_RE.search(task): out.append(Finding('ERROR',rel,no,'created-date','Managed open task has no created date.'))
            if status.lower()=='x' and is_task_note and sec in APPROVED:
                out.append(Finding('WARN',rel,no,'done-active','Completed task remains in Now/Next; log the outcome and remove it.'))
        if probable_hub(path,text):
            nonblank=sum(1 for x in lines if x.strip())
            if nonblank>80: out.append(Finding('WARN',rel,1,'hub-size','Project hub is over the 80 nonblank-line target.',f'{nonblank} lines'))
            for i,line in enumerate(lines):
                h=HEADING_RE.match(line)
                if not h or len(h.group(1))!=2: continue
                name=h.group(2).strip().lower()
                if name not in ('current state','current status','status'): continue
                end=next((j for j in range(i+1,len(lines)) if lines[j].startswith('## ')),len(lines))
                body=sum(1 for x in lines[i+1:end] if x.strip())
                if body>12: out.append(Finding('ERROR',rel,i+1,'status-size','Current-state section should be at most 8 concise bullets.',f'{body} lines'))
    return out

def main():
    ap=argparse.ArgumentParser(); ap.add_argument('root'); ap.add_argument('--baseline'); ap.add_argument('--write-baseline'); ap.add_argument('--json',action='store_true'); a=ap.parse_args()
    root=Path(a.root).resolve(); findings=audit(root)
    if a.write_baseline:
        Path(a.write_baseline).write_text(json.dumps(sorted(f.key() for f in findings),indent=2)+'\n',encoding='utf-8')
        print(f'Wrote baseline with {len(findings)} findings'); return 0
    baseline=set()
    if a.baseline and Path(a.baseline).exists():
        try: baseline=set(json.loads(Path(a.baseline).read_text(encoding='utf-8')))
        except (ValueError,TypeError) as e:
            # A truncated baseline must not read as "no baseline": that would re-fire every known finding as new.
            print(f'Vault lint: baseline {a.baseline} is unreadable ({e}); fix or re-write it',file=sys.stderr); return 2
    new=[f for f in findings if f.key() not in baseline]
    if a.json: print(json.dumps({'new':[asdict(f) for f in new],'all_count':len(findings)},ensure_ascii=False))
    else:
        print(f'Vault lint: {len(new)} new findings ({len(findings)} total, baseline-aware)')
        for f in new: print(f'{f.severity}: {f.path}:{f.line}: {f.message}' + (f' ({f.detail})' if f.detail else ''))
    return 1 if any(f.severity=='ERROR' for f in new) else 0
if __name__=='__main__': raise SystemExit(main())
