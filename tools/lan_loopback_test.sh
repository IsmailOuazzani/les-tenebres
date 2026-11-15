#!/usr/bin/env bash
# Headless two-process LAN replication test over 127.0.0.1.
#
# Launches a real listen server (scripts/_debug_net_host.gd) and a real
# client (scripts/_debug_net_client.gd) as two separate Godot processes
# talking over ENetMultiplayerPeer on port 7000, then asserts that the
# authoritative world replicated correctly. Invoked by `task test:lan`.
#
# This is the closest thing to a real two-player session that can be run
# without a window: it exercises peer connection, the synchronized-load
# handshake, MultiplayerSpawner spawn packets and MultiplayerSynchronizer
# state for real. It does NOT exercise input, rendering or player-to-player
# visibility -- those still need two windowed instances.
set -uo pipefail

GODOT="${GODOT_BIN:-/Applications/Godot.app/Contents/MacOS/Godot}"
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_DIR="$PROJECT_DIR/logs"

if [ ! -x "$GODOT" ]; then
	echo "error: Godot not found at '$GODOT'. Set GODOT_BIN." >&2
	exit 1
fi

mkdir -p "$LOG_DIR"
HOST_LOG="$LOG_DIR/lan-host.log"
CLIENT_LOG="$LOG_DIR/lan-client.log"

echo "== starting listen server (logs -> $HOST_LOG)"
"$GODOT" --path "$PROJECT_DIR" --headless --script res://scripts/_debug_net_host.gd \
	>"$HOST_LOG" 2>&1 &
HOST_PID=$!

# Give the server time to bind the port before the client dials in.
sleep 3

echo "== starting client (logs -> $CLIENT_LOG)"
"$GODOT" --path "$PROJECT_DIR" --headless --script res://scripts/_debug_net_client.gd \
	>"$CLIENT_LOG" 2>&1
CLIENT_STATUS=$?

wait "$HOST_PID"
HOST_STATUS=$?

echo
echo "===== HOST ====="
grep -E '^\[host\]' "$HOST_LOG" || true
echo
echo "===== CLIENT ====="
grep -E '^\[client\]' "$CLIENT_LOG" || true
echo
echo "host exit=$HOST_STATUS client exit=$CLIENT_STATUS"

if [ "$HOST_STATUS" -ne 0 ] || [ "$CLIENT_STATUS" -ne 0 ]; then
	echo "LAN loopback test FAILED (see $HOST_LOG and $CLIENT_LOG)" >&2
	exit 1
fi
echo "LAN loopback test PASSED"
