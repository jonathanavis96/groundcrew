#!/usr/bin/env bash
set -euo pipefail

# WSL2 -> Windows Obsidian bridge for mcp-obsidian.
#
# Two facts make this necessary:
#   1. mcp-obsidian hardcodes host='127.0.0.1' and ignores OBSIDIAN_HOST.
#   2. Under WSL2's default NAT networking, 127.0.0.1 inside WSL is WSL's own
#      loopback, not Windows'. Windows is reachable only at the gateway IP.
#
# So this script runs a TCP forwarder that listens on 127.0.0.1:27124 inside
# WSL and relays to <windows-gateway>:27124, then starts mcp-obsidian.
#
# REQUIRED on the Windows side, or the forwarder connects to nothing:
#   - Obsidian's Local REST API plugin must bind to all interfaces, not just
#     loopback: set "bindingHost": "0.0.0.0" in
#     <vault>/.obsidian/plugins/obsidian-local-rest-api/data.json and restart
#     Obsidian. The plugin's default (127.0.0.1) is unreachable from WSL.
#   - Windows Firewall must allow inbound TCP 27124 (a "Private" or "Any"
#     profile rule; the WSL virtual adapter often counts as Public).
#
# If "curl -k https://<gateway>:27124/" from WSL fails, fix the two items
# above first. The forwarder cannot help until that works.

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GATEWAY="$(ip route show default 2>/dev/null | awk '/default/ {print $3; exit}')"
if [[ -z "${GATEWAY:-}" ]]; then
    echo "mcp-obsidian-wrapper: could not resolve Windows host gateway from 'ip route'" >&2
    exit 1
fi

FORWARDER_TARGET_HOST="$GATEWAY" \
FORWARDER_LISTEN_PORT=27124 \
FORWARDER_TARGET_PORT=27124 \
    python3 "$HERE/mcp-obsidian-forwarder.py" >&2 &
FWD_PID=$!
MCP_PID=""

# Kill both children on exit. mcp-obsidian runs as a child (not exec) so this
# trap still fires when it exits and the forwarder never outlives the session
# or keeps port 27124 bound for a later run against a stale gateway.
# shellcheck disable=SC2317  # invoked via trap
cleanup() {
    if [[ -n "$MCP_PID" ]]; then kill "$MCP_PID" 2>/dev/null || true; fi
    kill "$FWD_PID" 2>/dev/null || true
    wait "$FWD_PID" 2>/dev/null || true
}
trap cleanup EXIT
trap 'cleanup; exit 143' INT TERM

# Wait for the listener to bind before mcp-obsidian fires off requests.
for _ in 1 2 3 4 5 6 7 8 9 10; do
    if (exec 3<>/dev/tcp/127.0.0.1/27124) 2>/dev/null; then
        break
    fi
    sleep 0.1
done

export OBSIDIAN_HOST="127.0.0.1"
uvx --from mcp-obsidian mcp-obsidian &
MCP_PID=$!
STATUS=0
wait "$MCP_PID" || STATUS=$?
MCP_PID=""
exit "$STATUS"
