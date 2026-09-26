#!/usr/bin/env bash
# Headless smoke tests: the project imports cleanly, every sound the game asks
# for exists, a full bot match runs from countdown to the parents' verdict (with
# its sound cues), and a host + client play a networked match that ends with the
# same result on both machines.
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
  if grep -qE "leaked at exit|still in use at exit|Audio: no (sound|music) called" "$1"; then
    fail "$2: engine warnings"; grep -E "leaked at exit|still in use at exit|Audio: no (sound|music) called" "$1" | head -5
  fi
}

echo "== Import"
"$GODOT" --headless --path "$GAME" --import > "$OUT/import.log" 2>&1
no_script_errors "$OUT/import.log" "import"

echo "== Every sound the scripts and the roster name exists"
MISSING=""
# (Names built at runtime, like "ko_" + voice, are covered by the voice list.)
NAMES="$(grep -rohE '(Audio\.play(_at|_later)?|sound)\("[a-z_]+"' "$GAME/scenes" "$GAME/scripts" | sed -E 's/.*\("//; s/"$//' | grep -v '_$')
  $(grep -ohE '"(sfx|hit_sfx|land_sfx|swing_sfx)": "[a-z_]+"' "$GAME/scripts/core/roster.gd" | sed -E 's/.*: "//; s/"$//')
  $(grep -ohE '"voice": "[a-z]+"' "$GAME/scripts/core/roster.gd" | sed -E 's/.*: "(.*)"/hi_\1 ko_\1/')
  spotless fine grounded"
for S in $(echo $NAMES | tr ' ' '\n' | sort -u); do
  [ -f "$GAME/assets/sounds/$S.wav" ] || [ -f "$GAME/assets/sounds/$S.ogg" ] || MISSING="$MISSING $S"
done
for M in $(grep -rohE 'Audio\.music(_after)?\("[a-z_]+"' "$GAME/scenes" "$GAME/scripts" | sed -E 's/.*\("//; s/"$//' | sort -u); do
  [ -f "$GAME/assets/music/$M.ogg" ] || MISSING="$MISSING music/$M"
done
if [ -z "$MISSING" ]; then pass "all $(echo $NAMES | tr ' ' '\n' | sort -u | wc -l) sounds found"; else fail "missing sounds:$MISSING"; fi

MAPS="living_room studio farmhouse suburbs"
for MAP in $MAPS; do
  echo "== Practice match on $MAP (3v3 bots, simulated as fast as possible)"
  LOG="$OUT/practice_$MAP.log"
  "$GODOT" --headless --path "$GAME" --fixed-fps 60 -- \
    --practice --map="$MAP" --bots=5 --autostart=1 --autopilot --war=90 --cleanup=30 --quit-after=140 --audio-log \
    > "$LOG" 2>&1
  no_script_errors "$LOG" "$MAP"
  for step in "map $MAP" "phase WAR" "phase WHISTLE" "phase CLEANUP" "results tidy="; do
    if grep -q "$step" "$LOG"; then pass "$MAP reached '$step'"; else fail "$MAP never reached '$step'"; fi
  done
  if grep -q "] ko " "$LOG"; then pass "$MAP had KOs"; else fail "$MAP had no KOs"; fi
  if grep -q "] knocked " "$LOG"; then pass "$MAP made a mess"; else fail "$MAP: nothing got knocked over"; fi
  if grep -q "score team=" "$LOG"; then pass "$MAP: bots found their way to a base"; else fail "$MAP: nobody scored (bots stuck?)"; fi
  for cue in "parents_leave" "whistle" "car_horn" "music war" "music cleanup"; do
    grep -q "\[audio\] $cue\$" "$LOG" || MISSED_CUE="$cue"
  done
  if [ -z "${MISSED_CUE:-}" ] && grep -qE "\[audio\] (spotless|fine|grounded)$" "$LOG"; then
    pass "$MAP: phase sounds and music played ($(grep -c '^\[audio\]' "$LOG") sounds in all)"
  else
    fail "$MAP: missing sound cue ${MISSED_CUE:-verdict jingle}"
  fi
  unset MISSED_CUE
done

echo "== Shared screen: four people on fake Joy-Cons and a controller"
"$GODOT" --headless --fixed-fps 60 --path "$GAME" res://tests/couch_test.tscn -- --war=60 --cleanup=5 \
  > "$OUT/couch.log" 2>&1
no_script_errors "$OUT/couch.log" "couch"
grep -E "^  (PASS|FAIL)  couch:" "$OUT/couch.log"
if grep -q "FAIL  couch:" "$OUT/couch.log" || ! grep -q "^\[couch\] [0-9]* passed, 0 failed" "$OUT/couch.log"; then
  FAILED=1
fi

echo "== Close-up moves: every character's, and what each one does"
"$GODOT" --headless --fixed-fps 60 --path "$GAME" res://tests/melee_test.tscn -- --war=120 \
  > "$OUT/melee.log" 2>&1
no_script_errors "$OUT/melee.log" "melee"
grep -E "^  (PASS|FAIL)  melee:" "$OUT/melee.log"
if grep -q "FAIL  melee:" "$OUT/melee.log" || ! grep -q "^\[melee\] [0-9]* passed, 0 failed" "$OUT/melee.log"; then
  FAILED=1
fi

echo "== Network match (host with a guest on its screen + a client, over localhost, real time, ~70s)"
"$GODOT" --headless --path "$GAME" -- --host --name=Host --map=farmhouse --bots=2 --guests=1 --autostart=2 --autopilot \
  --war=30 --cleanup=15 --quit-after=62 > "$OUT/host.log" 2>&1 &
HOST_PID=$!
sleep 3
"$GODOT" --headless --path "$GAME" -- --join=127.0.0.1 --name=Client --char=butler --autopilot \
  --quit-after=58 > "$OUT/client.log" 2>&1
wait $HOST_PID
no_script_errors "$OUT/host.log" "host"
no_script_errors "$OUT/client.log" "client"
if grep -q "map farmhouse" "$OUT/client.log"; then pass "the client loaded the host's map"; else fail "the client didn't load the host's map"; fi
if grep -q "players 5 (2 on this screen)" "$OUT/host.log" && grep -q "players 5 (1 on this screen)" "$OUT/client.log"; then
  pass "host (you + a guest), client and 2 bots all in the match on both machines"
else
  fail "player counts differ: host '$(grep -o 'players [0-9]* ([0-9]* on this screen)' "$OUT/host.log" | head -1)' client '$(grep -o 'players [0-9]* ([0-9]* on this screen)' "$OUT/client.log" | head -1)'"
fi
LOADED="$(grep -o 'everyone loaded after [0-9.]*' "$OUT/host.log" | head -1 | grep -o '[0-9.]*$')"
if [ -n "$LOADED" ] && awk "BEGIN{exit !($LOADED < 3)}"; then
  pass "the match started as soon as the client loaded (${LOADED}s), not after the 8 s timeout"
else
  fail "the match waited for the load timeout (${LOADED:-never}s)"
fi
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
