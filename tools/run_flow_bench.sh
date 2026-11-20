#!/bin/sh
# Runs tests/perf/flow_bench.gd with the player's save folder backed up and restored around it.
#   GODOT=<godot exe> sh tools/run_flow_bench.sh <out.jsonl> [preset 0..3]
set -u
OUT=$1; PRESET=${2:-2}
DATA="$APPDATA/Godot/app_userdata/TECTICA"
SAVE=$(mktemp -d)
cp -a "$DATA/." "$SAVE/"
"$GODOT" --path . -s res://tests/perf/flow_bench.gd -- "$OUT" "$PRESET" > "$OUT.log" 2>&1
rc=$?
rm -rf "$DATA" && mkdir -p "$DATA" && cp -a "$SAVE/." "$DATA/" && rm -rf "$SAVE"
grep -h "SCRIPT ERROR" -A3 "$OUT.log" | head -20
echo "bench rc=$rc"
