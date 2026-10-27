#!/usr/bin/env bash
# Nearby pairing, no code (Sync.java visible / nearby / ask): a visible device is listed by the others on the Wi-Fi;
# asking it to pair needs its person's yes; then both screens show the same six digits and both people confirm;
# then they're paired and synced, as with a code. A no at either step pairs nothing. Two devices on this machine.
set -euo pipefail
repo=$(cd "$(dirname "$0")/.." && pwd)
w=$(mktemp -d)
trap 'exec 7>&- 8>&- 2>/dev/null; kill $(jobs -p) 2>/dev/null || true; rm -rf "$w" 2>/dev/null || true' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }
ok() { echo "PASS: $*"; }
device() {
  mkdir -p "$w/$1/data" "$w/$1/cache" "$w/$1/apps" "$w/$1/ports"
  ln -s "$repo/bin" "$w/$1/data/bin"; ln -s "$repo/template" "$w/$1/data/template"; ln -s "$repo/creation/AGENTS.md" "$w/$1/data/AGENTS.md"
  cp "$repo/platforms/linux/platform.env" "$w/$1/data/"
}
on() { local d=$1; shift; HATCHLYBOX_HOME=$w/$d/data HATCHLYBOX_CACHE=$w/$d/cache HATCHLYBOX_APPS=$w/$d/apps HATCHLYBOX_PORTS=$w/$d/ports HATCHLYBOX_DEVICE_NAME="${d^^} computer" "$repo/bin/hatchlybox" "$@"; }
waitfor() { for _ in $(seq 120); do grep -q "$2" "$1" 2>/dev/null && return 0; sleep 0.5; done; fail "waited for $2 in $1: $(cat "$1" 2>/dev/null)"; }
device x; device y
export HATCHLYBOX_SYNC_NEAR_UDP=$((40000 + RANDOM % 20000)) HATCHLYBOX_SYNC_FIND=127.0.0.1 HATCHLYBOX_SYNC_LOOK_MS=1500

# X visible; Y lists it.
mkfifo "$w/fx" "$w/fy"
on x sync visible < "$w/fx" > "$w/vis.out" 2>&1 & exec 7> "$w/fx"
waitfor "$w/vis.out" '"state":"visible"'
l=$(on y sync nearby)
at=$(jq -r '.[] | select(.name == "X computer") | .at' <<< "$l")
[ -n "$at" ] && [ "$(jq length <<< "$l")" = 1 ] || fail "nearby: $l"
ok "a visible device is listed by the others on the Wi-Fi"

# Y asks; X's person accepts; both see the same six digits; both confirm: paired and synced.
on y sync ask "$at" --peer "X computer" < "$w/fy" > "$w/ask.out" 2>&1 & exec 8> "$w/fy"
waitfor "$w/vis.out" '"state":"asked"'
grep -q '"device":"Y computer"' "$w/vis.out" || fail "asked by whom: $(cat "$w/vis.out")"
echo yes >&7
waitfor "$w/vis.out" '"state":"confirm"'; waitfor "$w/ask.out" '"state":"confirm"'
s1=$(grep '"state":"confirm"' "$w/vis.out" | jq -r .sas); s2=$(grep '"state":"confirm"' "$w/ask.out" | jq -r .sas)
[[ $s1 =~ ^[0-9]{6}$ ]] && [ "$s1" = "$s2" ] || fail "six digits: $s1 $s2"
echo yes >&7; echo yes >&8
wait %1 %2 || fail "pairing: $(cat "$w/vis.out" "$w/ask.out")"
exec 7>&- 8>&-
grep -q '"state":"done"' "$w/ask.out" && grep -q '"state":"done"' "$w/vis.out" || fail "not synced: $(cat "$w/ask.out")"
[ "$(on y sync devices | jq -r '.[0].name')" = "X computer" ] && [ "$(on x sync devices | jq -r '.[0].name')" = "Y computer" ] || fail "not paired"
ok "asked, accepted, the same six digits confirmed on both: paired and synced"

# A no: when asked, or at the digits on either side, pairs nothing.
for step in asked confirm-x confirm-y; do
  rm -f "$w/x/data/devices.tsv" "$w/y/data/devices.tsv"
  on x sync visible < "$w/fx" > "$w/vis.out" 2>&1 & exec 7> "$w/fx"
  waitfor "$w/vis.out" '"state":"visible"'
  at=127.0.0.1:$(grep '"state":"visible"' "$w/vis.out" | jq -r .port)
  on y sync ask "$at" --peer "X computer" < "$w/fy" > "$w/ask.out" 2>&1 & exec 8> "$w/fy"
  waitfor "$w/vis.out" '"state":"asked"'
  if [ $step = asked ]; then echo no >&7; waitfor "$w/ask.out" "didn't accept"; kill %1 2>/dev/null || true
  else
    echo yes >&7; waitfor "$w/vis.out" '"state":"confirm"'; waitfor "$w/ask.out" '"state":"confirm"'
    if [ $step = confirm-x ]; then echo no >&7; echo yes >&8; else echo yes >&7; echo no >&8; fi
    waitfor "$w/ask.out" '"state":"failed"'
  fi
  wait 2>/dev/null || true; exec 7>&- 8>&-
  [ "$(on y sync devices)" = "[]" ] && [ "$(on x sync devices)" = "[]" ] || fail "paired after a no at $step"
done
ok "a no, when asked or at the digits on either side, pairs nothing"
