#!/usr/bin/env bash
# Headless smoke tests: the project imports cleanly, a full bot match runs from
# countdown to the parents' verdict, and a host + client play a networked match
# that ends with the same result on both machines.
#
# Usage: tools/smoke_test.sh [path/to/godot]      (default: `godot` on PATH)
set -uo pipefail

GODOT="${1:-${GODOT:-godot}}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GAME="$ROOT/game"
OUT="$(mktemp -d)"
FAILED=0

pass() { echo "  PASS  $1"; }
fail() { echo "  FAIL  $1"; FAILED=1; }
no_script_errors() {  # file, label
  if grep -qE "SCRIPT ERROR|Parse Error|Compile Error" "$1"; then
    fail "$2: script errors"; grep -E "SCRIPT ERROR|Parse Error|Compile Error" "$1" | head -5
  else
    pass "$2: no script errors"
  fi
}

echo "== Import"
"$GODOT" --headless --path "$GAME" --import > "$OUT/import.log" 2>&1
no_script_errors "$OUT/import.log" "import"

MAPS="living_room studio farmhouse suburbs"
for MAP in $MAPS; do
  echo "== Practice match on $MAP (3v3 bots, simulated as fast as possible)"
  LOG="$OUT/practice_$MAP.log"
  "$GODOT" --headless --path "$GAME" --fixed-fps 60 -- \
    --practice --map="$MAP" --bots=5 --autostart=1 --autopilot --war=90 --cleanup=30 --quit-after=140 \
    > "$LOG" 2>&1
  no_script_errors "$LOG" "$MAP"
  for step in "map $MAP" "phase WAR" "phase WHISTLE" "phase CLEANUP" "results tidy="; do
    if grep -q "$step" "$LOG"; then pass "$MAP reached '$step'"; else fail "$MAP never reached '$step'"; fi
  done
  if grep -q "] ko " "$LOG"; then pass "$MAP had KOs"; else fail "$MAP had no KOs"; fi
  if grep -q "] knocked " "$LOG"; then pass "$MAP made a mess"; else fail "$MAP: nothing got knocked over"; fi
  if grep -q "score team=" "$LOG"; then pass "$MAP: bots found their way to a base"; else fail "$MAP: nobody scored (bots stuck?)"; fi
done

echo "== Network match (host + client over localhost, real time, ~70s)"
"$GODOT" --headless --path "$GAME" -- --host --name=Host --map=farmhouse --bots=2 --autostart=2 --autopilot \
  --war=30 --cleanup=15 --quit-after=62 > "$OUT/host.log" 2>&1 &
HOST_PID=$!
sleep 3
"$GODOT" --headless --path "$GAME" -- --join=127.0.0.1 --name=Client --char=butler --autopilot \
  --quit-after=58 > "$OUT/client.log" 2>&1
wait $HOST_PID
no_script_errors "$OUT/host.log" "host"
no_script_errors "$OUT/client.log" "client"
if grep -q "map farmhouse" "$OUT/client.log"; then pass "the client loaded the host's map"; else fail "the client didn't load the host's map"; fi
HOST_RESULT="$(grep -o 'results tidy=.*' "$OUT/host.log" | head -1)"
CLIENT_RESULT="$(grep -o 'results tidy=.*' "$OUT/client.log" | head -1)"
if [ -n "$HOST_RESULT" ] && [ "$HOST_RESULT" = "$CLIENT_RESULT" ]; then
  pass "host and client agree: $HOST_RESULT"
else
  fail "host/client results differ or missing: host='$HOST_RESULT' client='$CLIENT_RESULT'"
fi
if grep -qE "\] ko -?[0-9]+ by [0-9]{3,}" "$OUT/host.log"; then
  pass "the client's hits were accepted by the host"
else
  echo "  note  the client landed no KOs this run (bots decide who fights whom)"
fi

echo
if [ "$FAILED" = 0 ]; then echo "All smoke tests passed. Logs: $OUT"; else echo "Some smoke tests FAILED. Logs: $OUT"; fi
exit $FAILED
