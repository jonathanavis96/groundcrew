#!/usr/bin/env bash
# SessionStart hook: auto-load the caveman skill at intensity $CAVEMAN_LEVEL
# (default: lite) on every session start, so it never has to be invoked by hand.
#
# Strips the skill's YAML frontmatter, pins the intensity, and emits the
# SessionStart additionalContext JSON. The PowerShell twin
# (caveman-autostart.ps1) does exactly the same thing without jq or awk.
set -uo pipefail

LEVEL="${CAVEMAN_LEVEL:-lite}"
SKILL="$HOME/.claude/skills/caveman/SKILL.md"

[ -r "$SKILL" ] || exit 0

BODY=$(awk 'NR==1 && /^---$/ {fm=1; next} fm && /^---$/ {fm=0; next} !fm' "$SKILL")

printf '%s\n\nARGUMENTS: %s\n' "$BODY" "$LEVEL" \
  | jq -Rs '{hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:.}}'
