#!/usr/bin/env bash
# Sync between two devices (two engines with their own folders, on this machine): ids, what's sent, merging
# (new, behind, both changed), versions for other systems, and the Wi-Fi transport with its code.
set -euo pipefail
repo=$(cd "$(dirname "$0")/.." && pwd)
w=$(mktemp -d)
# A background job may already have ended (kill fails) and proot link files can make rm fail: neither is the result.
trap 'kill $(jobs -p) 2>/dev/null || true; rm -rf "$w" 2>/dev/null || true' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }
ok() { echo "PASS: $*"; }

device() {
  mkdir -p "$w/$1/data" "$w/$1/cache" "$w/$1/apps" "$w/$1/ports"
  ln -s "$repo/bin" "$w/$1/data/bin"; ln -s "$repo/template" "$w/$1/data/template"; ln -s "$repo/creation/AGENTS.md" "$w/$1/data/AGENTS.md"
  cp "$repo/platforms/hatchlybox/platform.env" "$w/$1/data/"
}
# on <device> <hatchlybox args...>
on() { local d=$1; shift; HATCHLYBOX_HOME=$w/$d/data HATCHLYBOX_CACHE=$w/$d/cache HATCHLYBOX_APPS=$w/$d/apps HATCHLYBOX_PORTS=$w/$d/ports HATCHLYBOX_DEVICE_NAME="${d^^} phone" "$repo/bin/hatchlybox" "$@"; }
# sync <from> <to>: <to> gets what <from> has for it (one direction of a sync).
sync() { on "$2" sync manifest > "$w/m.json"; on "$1" sync pack "$w/m.json" "$w/p.tar"; on "$2" sync apply "$w/p.tar"; }
g() { git -C "$1" -c user.name=t -c user.email=t@t "${@:2}"; }
device a; device b

# A has an Android app (built, installed) and a Linux version of another creation.
n=$w/a/apps/notes; mkdir -p "$n"; echo one > "$n/Main.kt"; g "$n" init -q -b main
# As every app's repo is: Hatchlybox's .gitignore committed (hygiene).
( HATCHLYBOX_HOME=$w/a/data HATCHLYBOX_CACHE=$w/a/cache HATCHLYBOX_APPS=$w/a/apps HATCHLYBOX_PORTS=$w/a/ports HATCHLYBOX_TEST=1; set +eu; source "$repo/bin/hatchlybox"; hygiene "$n" )
g "$n" add -A; g "$n" commit -qm one
mkdir -p "$w/a/cache/apks"; echo apk > "$w/a/cache/apks/notes.apk"
echo "{\"slug\":\"notes\",\"label\":\"Notes\",\"pkg\":\"com.hatchlybox.notes\",\"status\":\"installed\",\"apk\":\"$w/a/cache/apks/notes.apk\",\"created\":10,\"updated\":20,\"history\":[{\"t\":10,\"prompt\":\"notes\"}],\"artifacts\":{\"apk\":{\"sha256\":\"a\",\"at\":9999999999}},\"installedArtifact\":{\"sha256\":\"a\"},\"outcomes\":{\"install\":\"verified\"},\"github\":{\"repo\":\"x/notes\"}}" > "$n/.hatchlybox.json"
mkdir -p "$w/a/ports/timer/linux/export"; echo bin > "$w/a/ports/timer/linux/export/timer"
echo '{"target":"linux","agent":"codex","label":"Timer","created":45,"changed":50,"content":50}' > "$w/a/ports/timer/linux/.port.json"

# Ids.
d1=$(on a sync id | jq -r .id); d2=$(on a sync id | jq -r .id)
[[ $d1 =~ ^[0-9a-f]{16}$ ]] && [ "$d1" = "$d2" ] && [ "$(on a sync id | jq -r .name)" = "A phone" ] || fail "device id: $d1 $d2"
j=$(on a creations)
nid=$(jq -r '.[] | select(.slug == "notes") | .id' <<< "$j"); tid=$(jq -r '.[] | select(.slug == "timer") | .id' <<< "$j")
[[ $nid =~ ^[0-9a-f]{16}$ ]] && [[ $tid =~ ^[0-9a-f]{16}$ ]] && [ "$nid" != "$tid" ] \
  && [ "$(jq -r .id "$n/.hatchlybox.json")" = "$nid" ] && [ "$(jq -r .id "$w/a/ports/timer/linux/.port.json")" = "$tid" ] || fail "creation ids: $j"
[ "$(on a creations | jq -r '.[] | select(.slug == "notes") | .id')" = "$nid" ] || fail "ids change"
ok "every device and creation has a lasting id, in the library and every version's metadata"

# First sync: B gets both; it can't build Android, so the APK comes too. Device details stay behind.
r=$(sync a b)
[ "$(jq -c ".added | sort" <<< "$r")" = '["Notes","Timer"]' ] && [ "$(jq -r .from <<< "$r")" = "A phone" ] || fail "first sync: $r"
[ "$(g "$w/b/apps/notes" rev-parse HEAD)" = "$(g "$n" rev-parse HEAD)" ] && [ "$(g "$w/b/apps/notes" branch --show-current)" = main ] || fail "android version"
bm=$w/b/apps/notes/.hatchlybox.json
[ "$(jq -r .id "$bm")" = "$nid" ] && [ "$(jq -r .pkg "$bm")" = com.hatchlybox.notes ] && [ "$(jq -c '.github // .installedArtifact // .outcomes // "none"' "$bm")" = '"none"' ] \
  && [ "$(cat "$w/b/cache/apks/notes.apk")" = apk ] && [ "$(jq -r .apk "$bm")" = "$w/b/cache/apks/notes.apk" ] || fail "android metadata: $(cat "$bm")"
[ "$(cat "$w/b/ports/timer/linux/export/timer")" = bin ] && [ "$(jq -r .id "$w/b/ports/timer/linux/.port.json")" = "$tid" ] || fail "linux version"
[ "$(on b creations | jq -c '[.[] | {slug, id}] | sort_by(.slug)')" = "[{\"slug\":\"notes\",\"id\":\"$nid\"},{\"slug\":\"timer\",\"id\":\"$tid\"}]" ] || fail "b's library"
ok "a new device gets every creation with its ids; an APK only for a device that can't build Android; no install, GitHub or Play state"

# Nothing new: nothing sent either way.
on b sync manifest > "$w/m.json"; on a sync pack "$w/m.json" "$w/p.tar"
[ -z "$(tar -tf "$w/p.tar" | grep creation.json || true)" ] || fail "sent again: $(tar -tf "$w/p.tar")"
r=$(sync b a); [ "$(jq -c '.added + .updated + .conflicts' <<< "$r")" = '[]' ] || fail "back to a: $r"
ok "in sync: nothing is sent"

# A changes notes: B, behind, gets only the new commit and moves forward; its build is out of date.
echo two > "$n/Main.kt"; g "$n" commit -qam two
jq -c '.history += [{"t":30,"prompt":"two"}] | .label = "Notes 2"' "$n/.hatchlybox.json" > "$n/m" && mv "$n/m" "$n/.hatchlybox.json"
on b sync manifest > "$w/m.json"; on a sync pack "$w/m.json" "$w/p.tar"
mkdir -p "$w/x"; tar -C "$w/x" -xf "$w/p.tar"
[ "$(git bundle list-heads "$w/x/$nid/android.bundle" | wc -l)" = 1 ] && git -C "$n" bundle verify "$w/x/$nid/android.bundle" 2>&1 | grep -q "requires" || fail "a whole bundle where the change would do"
r=$(on b sync apply "$w/p.tar")
[ "$(jq -c .updated <<< "$r")" = '["Notes 2"]' ] && [ "$(g "$w/b/apps/notes" rev-parse HEAD)" = "$(g "$n" rev-parse HEAD)" ] \
  && [ "$(jq -r .label "$bm")" = "Notes 2" ] && [ "$(jq -c '[.history[].t]' "$bm")" = '[10,30]' ] && [ "$(jq -r .outcomes.build "$bm")" = needs-rebuild ] || fail "behind: $r $(cat "$bm")"
[ "$(on b list | jq -r '.[] | select(.slug == "notes") | .state.key')" = rebuild ] || fail "b's build should be out of date"
ok "a device behind gets only what changed and moves forward, needing a rebuild"

# Both change notes: B keeps its own, A's waits on a branch, and the user picks.
echo a3 > "$n/Main.kt"; g "$n" commit -qam a3
echo b3 > "$w/b/apps/notes/Main.kt"   # not committed yet: the sync saves it first
r=$(sync a b)
[ "$(jq -c .conflicts <<< "$r")" = '["Notes 2"]' ] && [ "$(cat "$w/b/apps/notes/Main.kt")" = b3 ] || fail "both changed: $r"
br=$(jq -r .sync.conflict.branch "$bm")
[[ $br == sync/phone-* ]] && [ "$(jq -r .sync.conflict.device "$bm")" = "A phone" ] && [ "$(g "$w/b/apps/notes" rev-parse "$br")" = "$(g "$n" rev-parse HEAD)" ] || fail "conflict: $(cat "$bm")"
[ "$(on b creations | jq -r '.[] | select(.slug == "notes") | .conflict.device')" = "A phone" ] || fail "conflict in the library"
on b sync resolve notes theirs | grep -q "the other device's" || fail resolve
[ "$(cat "$w/b/apps/notes/Main.kt")" = a3 ] && [ "$(jq -c '.sync.conflict // "none"' "$bm")" = '"none"' ] \
  && g "$w/b/apps/notes" branch --list 'sync/kept-*' | grep -q kept && ! g "$w/b/apps/notes" rev-parse -q --verify "$br" >/dev/null || fail "theirs: $(cat "$bm")"
kept=$(g "$w/b/apps/notes" branch --list 'sync/kept-*' | tr -d ' *')
[ "$(g "$w/b/apps/notes" show "$kept:Main.kt")" = b3 ] || fail "b's own version kept"
ok "changed on both devices: both kept, the user picks, and the other stays on a branch"

# B makes Linux timer newer: it goes to A, and A's old one is kept aside. A's creation named like B's new one is renamed.
echo new > "$w/b/ports/timer/linux/export/timer"; jq -c '.changed = 70 | .content = 70' "$w/b/ports/timer/linux/.port.json" > "$w/t" && mv "$w/t" "$w/b/ports/timer/linux/.port.json"
mkdir -p "$w/b/ports/sketch/web/export"; echo '{"target":"web","label":"Sketch","created":80,"changed":81,"content":81}' > "$w/b/ports/sketch/web/.port.json"
mkdir -p "$w/a/ports/sketch/windows"; echo '{"target":"windows","label":"Sketch A","created":82,"changed":83,"content":83}' > "$w/a/ports/sketch/windows/.port.json"
r=$(sync b a)
[ "$(cat "$w/a/ports/timer/linux/export/timer")" = new ] && ls "$w/a/cache/sync-old" | grep -q '^timer-linux-' || fail "newer port: $r"
[ -f "$w/a/ports/sketch-2/web/.port.json" ] && [ "$(jq -r .label "$w/a/ports/sketch/windows/.port.json")" = "Sketch A" ] || fail "rename: $r $(ls "$w/a/ports")"
ok "a newer version for another system replaces the older (kept aside); a different creation with the same name is renamed"

# A change waiting on a device: that app isn't touched until it's kept or undone.
echo '{"pending":{"branch":"change/1","base":"main","t":1}}' | jq -c --slurpfile m "$bm" '$m[0] + .' > "$w/t" && mv "$w/t" "$bm"
echo a4 > "$n/Main.kt"; g "$n" commit -qam a4
r=$(sync a b)
[ "$(jq -r '.skipped[0]' <<< "$r")" = "Notes 2 (a change waits here: keep or undo it, then sync again)" ] && [ "$(cat "$w/b/apps/notes/Main.kt")" = a3 ] || fail "pending: $r"
jq -c 'del(.pending)' "$bm" > "$w/t" && mv "$w/t" "$bm"
ok "an app with a change waiting is left alone"

# Over the network: the code finds the device and becomes the key; a wrong code gets nothing.
udp=$((40000 + RANDOM % 20000))
export HATCHLYBOX_SYNC_UDP=$udp HATCHLYBOX_SYNC_FIND=127.0.0.1
HATCHLYBOX_SYNC_CODE=7-violet-orbit on a sync send > "$w/send.out" 2>&1 &
for _ in $(seq 60); do grep -q waiting "$w/send.out" 2>/dev/null && break; sleep 1; done
grep -q '"code":"7-violet-orbit"' "$w/send.out" || fail "send: $(cat "$w/send.out")"
on b sync receive "7 Violet orbit" > "$w/recv.out" 2>&1 || fail "receive: $(cat "$w/recv.out")"
wait
done_line=$(grep '"state":"done"' "$w/recv.out") || fail "no done: $(cat "$w/recv.out")"
[ "$(jq -c .result.updated <<< "$done_line")" = '["Notes 2"]' ] && [ "$(cat "$w/b/apps/notes/Main.kt")" = a4 ] \
  && grep -q '"state":"connected","device":"A phone"' "$w/recv.out" && grep -q '"state":"done"' "$w/send.out" || fail "over the network: $(cat "$w/recv.out") / $(cat "$w/send.out")"
ok "over the network: the code finds the other device, and both end up with everything"
HATCHLYBOX_SYNC_CODE=8-violet-orbit on a sync send > "$w/send.out" 2>&1 &
for _ in $(seq 60); do grep -q waiting "$w/send.out" 2>/dev/null && break; sleep 1; done
! on b sync receive 8-violet-orchid > "$w/recv.out" 2>&1 || fail "a wrong code worked"
wait || true
grep -q "didn't match" "$w/recv.out" && grep -q "didn't match" "$w/send.out" || fail "wrong code: $(cat "$w/recv.out") / $(cat "$w/send.out")"
on b sync receive 8-violet-orbit > "$w/recv.out" 2>&1 && fail "the code still worked after a wrong guess"
ok "a wrong code fails on both sides, and the code is gone after one wrong guess"

# The first sync paired them: each keeps the same key for the other, and a link to scan came with the code.
grep '"state":"waiting"' "$w/send.out" > /dev/null || true
[ "$(on a sync devices | jq -r '.[0].name')" = "B phone" ] && [ "$(on b sync devices | jq -r '.[0].name')" = "A phone" ] \
  && [ "$(cut -f2 "$w/a/data/devices.tsv")" = "$(cut -f2 "$w/b/data/devices.tsv")" ] && [ "$(stat -c %a "$w/a/data/devices.tsv")" = 600 ] || fail "paired: $(on a sync devices)"
[ "$(on a sync devices | jq -r '.[0].last')" -gt 0 ] || fail "last synced"
ok "a code pairs the two devices: each keeps the same key for the other, private to it"
HATCHLYBOX_SYNC_CODE=9-owl-moss on a sync send > "$w/send.out" 2>&1 &
for _ in $(seq 60); do grep -q waiting "$w/send.out" 2>/dev/null && break; sleep 1; done
link=$(grep '"state":"waiting"' "$w/send.out" | jq -r .link); qr=$(grep '"state":"waiting"' "$w/send.out" | jq -r '.qr | length')
[[ $link == hatchlybox://sync/9-owl-moss* ]] && [ "$qr" -ge 21 ] || fail "link and QR: $link $qr"
# The link scanned (its ?at= is the address): straight there, no broadcast needed.
HATCHLYBOX_SYNC_FIND=127.0.0.9 on b sync receive "${link/\?at=*/?at=127.0.0.1:$(grep '"state":"waiting"' "$w/send.out" | jq -r .port)}" > "$w/recv.out" 2>&1 || fail "link: $(cat "$w/recv.out")"
wait
ok "the code comes with a link and its QR code; the link goes straight to the device"

# Paired devices sync by themselves: each serves, calls the other at start and when something changes.
export HATCHLYBOX_SYNC_EVERY=3600
p1=$((udp + 1)); p2=$((udp + 2))
HATCHLYBOX_SYNC_CALL_UDP=$p1 HATCHLYBOX_SYNC_CALL_TO=$p2 on a sync serve > "$w/serve-a.out" 2>&1 &
sa=$!
echo a5 > "$n/Main.kt"; g "$n" commit -qam a5
HATCHLYBOX_SYNC_CALL_UDP=$p2 HATCHLYBOX_SYNC_CALL_TO=$p1 on b sync serve > "$w/serve-b.out" 2>&1 &
sb=$!
for _ in $(seq 90); do [ "$(cat "$w/b/apps/notes/Main.kt")" = a5 ] && grep -q '"state":"synced"' "$w/serve-b.out" && break; sleep 1; done
[ "$(cat "$w/b/apps/notes/Main.kt")" = a5 ] || fail "by itself: $(cat "$w/serve-a.out" "$w/serve-b.out") a=$(on a sync id) b=$(on b sync id) $(cut -f1,3 "$w/a/data/devices.tsv" "$w/b/data/devices.tsv") b's notes: $(cat "$w/b/apps/notes/Main.kt") $(jq -c '.pending, .sync' "$bm")"
grep -q '"state":"synced","device":"A phone"' "$w/serve-b.out" || fail "b's serve: $(cat "$w/serve-b.out")"
ok "paired devices sync by themselves when both are on"
mkdir -p "$w/a/ports/clock/web/export"; echo '{"target":"web","label":"Clock","created":90,"changed":91,"content":91}' > "$w/a/ports/clock/web/.port.json"
on a sync now
for _ in $(seq 60); do [ -f "$w/b/ports/clock/web/.port.json" ] && break; sleep 1; done
[ -f "$w/b/ports/clock/web/.port.json" ] || fail "after a change: $(tail -3 "$w/serve-a.out")"
ok "something new on one: the other has it within seconds"
kill $sa $sb; wait $sa $sb 2>/dev/null || true

# Different networks: the relay meets them. With a code (the relay gives the number), then paired.
rp=$((udp + 3))
java "$repo/bin/Relay.java" $rp > "$w/relay.out" 2>&1 &
rl=$!
for _ in $(seq 60); do grep -q "relay on port" "$w/relay.out" && break; sleep 1; done
export HATCHLYBOX_RELAY=127.0.0.1:$rp
mkdir -p "$w/c/data"
device c
mkdir -p "$w/a/ports/dice/linux/export"; echo '{"target":"linux","label":"Dice","created":95,"changed":96,"content":96}' > "$w/a/ports/dice/linux/.port.json"
HATCHLYBOX_SYNC_UDP=$((udp + 4)) on a sync send > "$w/send.out" 2>&1 &
for _ in $(seq 60); do grep -q waiting "$w/send.out" 2>/dev/null && break; sleep 1; done
code=$(grep '"state":"waiting"' "$w/send.out" | jq -r .code)
[[ $code =~ ^[0-9]{1,4}-[a-z]+-[a-z]+$ ]] || fail "relay code: $(cat "$w/send.out")"
# Nobody answers on "this Wi-Fi": the relay it is.
HATCHLYBOX_SYNC_UDP=$((udp + 5)) HATCHLYBOX_SYNC_FIND=127.0.0.9 on c sync receive "$code" > "$w/recv.out" 2>&1 || fail "through the relay: $(cat "$w/recv.out")"
wait $(jobs -p | grep -v "^$rl$") 2>/dev/null || true
[ -f "$w/c/ports/dice/linux/.port.json" ] && [ "$(on c sync devices | jq -r '.[0].name')" = "A phone" ] || fail "c: $(cat "$w/recv.out")"
ok "on different networks the relay meets them, with a code"
jq -c '.changed = 97 | .content = 97' "$w/a/ports/dice/linux/.port.json" > "$w/t" && mv "$w/t" "$w/a/ports/dice/linux/.port.json"
HATCHLYBOX_SYNC_FIND=127.0.0.9 HATCHLYBOX_SYNC_CALL_UDP=$((udp + 6)) on c sync serve > "$w/serve-c.out" 2>&1 &
sc=$!
sleep 4
HATCHLYBOX_SYNC_FIND=127.0.0.9 HATCHLYBOX_SYNC_CALL_UDP=$((udp + 7)) on a sync serve > "$w/serve-a.out" 2>&1 &
sa=$!
for _ in $(seq 60); do [ "$(jq -r .content "$w/c/ports/dice/linux/.port.json")" = 97 ] && break; sleep 1; done
[ "$(jq -r .content "$w/c/ports/dice/linux/.port.json")" = 97 ] && [ ! -e "$w/c/ports/dice-2" ] || fail "paired through the relay: $(cat "$w/serve-a.out" "$w/serve-c.out")"
ok "paired devices on different networks sync through the relay, which sees only encrypted bytes"
kill $sa $sc $rl; wait 2>/dev/null || true

# Forgotten: it's no longer answered.
on a sync forget "$(on a sync devices | jq -r '.[] | select(.name == "B phone") | .id')" | grep -q forgot
[ "$(on a sync devices | jq -r '[.[].name] | join(",")')" = "C phone" ] || fail "forget: $(on a sync devices)"
ok "a device can be forgotten"

# The phone app writes its own description to device.json: the sync id is kept apart, and made again if lost.
device z
echo '{"model":"Pixel 9","soc":"Tensor","width":1080}' > "$w/z/data/device.json"
zid=$(on z sync id | jq -r .id)
[[ $zid =~ ^[0-9a-f]{16}$ ]] && [ "$(on z sync id | jq -r .id)" = "$zid" ] && [ "$(jq -r .model "$w/z/data/device.json")" = "Pixel 9" ] || fail "sync id beside device.json: $zid"
on z sync manifest | jq -e --arg i "$zid" '.device.id == $i' >/dev/null || fail "the manifest says who it is"
echo '{}' > "$w/z/data/sync-device.json"; [[ $(on z sync id | jq -r .id) =~ ^[0-9a-f]{16}$ ]] || fail "a lost id is made again"
ok "the sync id is kept apart from the phone's device.json, and made again if lost"
