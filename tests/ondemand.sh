#!/usr/bin/env bash
# Android on demand (computers): a computer starts without Android building: doctor doesn't ask for it, Godot needs
# no Android template, and anything Android-only stops with exit 75 and words saying how to set it up (a game is
# made and exported for the computer instead); once setup was asked for, doctor follows it. The phone is unchanged.
# Also: create for another system in the person's own words (custom:<words>), and the terminal steps.
set -euo pipefail
repo=$(cd "$(dirname "$0")/.." && pwd)
w=$(mktemp -d)
trap 'rm -rf "$w" 2>/dev/null || true' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }
ok() { echo "PASS: $*"; }

mkdir -p "$w/home" "$w/data" "$w/cache" "$w/apps" "$w/ports" "$w/fake"
ln -s "$repo/bin" "$w/data/bin"; cp "$repo/platforms/linux/platform.env" "$w/data/"
printf '#!/bin/sh\nexit 0\n' > "$w/fake/opencode"; chmod +x "$w/fake/opencode"
echo '{"agentIsolation":"compatible"}' > "$w/data/settings.json"
h() { env HOME="$w/home" PATH="$w/fake:$PATH" HATCHLYBOX_HOME="$w/data" HATCHLYBOX_CACHE="$w/cache" HATCHLYBOX_APPS="$w/apps" HATCHLYBOX_PORTS="$w/ports" \
  ANDROID_HOME="$w/nosdk" "$repo/bin/hatchlybox" "$@"; }
in_engine() { env HOME="$w/home" PATH="$w/fake:$PATH" HATCHLYBOX_HOME="$w/data" HATCHLYBOX_CACHE="$w/cache" HATCHLYBOX_APPS="$w/apps" HATCHLYBOX_PORTS="$w/ports" \
  HATCHLYBOX_TEST=1 bash -c 'source "$0"; LOG=$HATCHLYBOX_CACHE/log.txt; eval "$1"' "$repo/bin/hatchlybox" "$1"; }

d=$(h doctor || true)
! grep -qiE "android|adb|gradle" <<< "$d" || fail "a fresh computer's doctor asks for Android: $d"
[ "$(h setup-state | jq -c '{state, ready}')" = '{"state":"none","ready":false}' ] || fail "setup-state: $(h setup-state)"
ok "a fresh computer: doctor doesn't ask for Android; setup-state says none, not ready"

rc=0; out=$(h create android opencode a step counter 2>&1) || rc=$?
[ $rc = 75 ] && grep -q "Android apps need a one-time setup on this computer first" <<< "$out" || fail "create android: $rc $out"
for c in "wrap x" "native x opencode" "build x"; do
  mkdir -p "$w/apps/x"; echo '{"slug":"x","pkg":"com.x.x"}' > "$w/apps/x/.hatchlybox.json"
  rc=0; h $c >/dev/null 2>&1 || rc=$?; [ $rc = 75 ] || fail "$c: $rc"
done
ok "Android-only steps stop with exit 75 and say how to set Android building up"

mkdir -p "$w/data/godot/4.7.2"; printf '#!/bin/sh\n' > "$w/data/godot/4.7.2/godot"; chmod +x "$w/data/godot/4.7.2/godot"; touch "$w/data/godot/.ready-4.7.2"
in_engine 'godot_ok' || fail "Godot needs no Android template on a computer without Android"
echo '{"state":"failed","msg":"x"}' > "$w/cache/setup.json"
! in_engine 'godot_ok' || fail "once Android is wanted, the template is needed"
d=$(h doctor || true)
grep -q "missing Android SDK" <<< "$d" && grep -q "the last setup didn't finish" <<< "$d" || fail "doctor after setup was asked for: $d"
rm "$w/cache/setup.json"
ok "Godot without its Android template; doctor follows Android once setup was asked for"

cp "$repo/platforms/hatchlybox/platform.env" "$w/data/"
in_engine 'need_android' || fail "the phone is never stopped"
cp "$repo/platforms/linux/platform.env" "$w/data/"
ok "the phone is unchanged"

echo '{"slug":"x","pkg":"com.x.x","label":"Dash","status":"exported","exportedFor":"linux","created":1,"updated":1,"history":[]}' > "$w/apps/x/.hatchlybox.json"
[ "$(h list | jq -r '.[] | select(.slug == "x") | .state.word')" = "not built for android" ] || fail "exported state: $(h list)"
ok "a game made on a computer without Android: its Android version says so"

out=$(in_engine 'start() { echo "start $*"; }; create_cmd "custom:a TV remote for my ESP32" opencode "a remote with big buttons"' 2>&1) || true
p=$(ls -d "$w/ports"/*/remote-esp32 2>/dev/null | head -1 || true)
[ -n "$p" ] && [ "$(jq -r .description "$p/.port.json")" = "a TV remote for my ESP32" ] && grep -q "start port" <<< "$out" || fail "custom: $out $(ls -R "$w/ports" | head)"
ok "create for another system in the person's own words"

printf '#!/bin/sh\necho "$@" > "%s/term"\n' "$w" > "$w/fake/term"; chmod +x "$w/fake/term"
[ "$(HATCHLYBOX_TERMINAL=$w/fake/term h terminal lock | jq -r .terminal)" = "$w/fake/term" ] && grep -q "lock" "$w/cache/terminal-lock.sh" || fail "terminal lock"
rc=0; h terminal rm >/dev/null 2>&1 || rc=$?; [ $rc = 1 ] || fail "terminal takes only its own steps"
ok "terminal: the passphrase and login steps in a terminal window, nothing else"

# A computer's words for an Android version (for the phone); a Hello World from before becomes the showcase (Neon Run,
# its own icon and chiptune), saved in its history, unless it was changed since.
d=$w/apps/hello-world; j=$d/app/src/main/java/com/hatchlybox/hello_world
mkdir -p "$d/app/src/main/res/drawable" "$d/app/src/main/res/values" "$j"
cp "$repo/template/app/src/main/res/drawable/ic_fg.xml" "$d/app/src/main/res/drawable/"; cp "$repo/template/app/src/main/res/values/colors.xml" "$d/app/src/main/res/values/"
# The Hello World from before: any file the engine is told is that one (STARTER_OLD_SHA).
printf 'package com.hatchlybox.hello_world\n// the greeting from before\n' > "$j/MainActivity.kt"; old=$(sha256sum "$j/MainActivity.kt" | cut -c1-64)
ln -s "$repo/template" "$w/data/template"; ln -s "$repo/starter" "$w/data/starter"
echo '{"slug":"hello-world","pkg":"com.hatchlybox.hello_world","label":"Hello World","starter":true,"status":"ready","apk":"/x.apk","created":1,"updated":1,"history":[]}' > "$d/.hatchlybox.json"
git -C "$d" init -q && git -C "$d" add -A app && git -C "$d" -c user.name=t -c user.email=t@t commit -qm start
in_engine "STARTER_OLD_SHA=$old; missing_icons; list_apps" >/dev/null 2>&1 || true
cmp -s "$j/MainActivity.kt" "$repo/starter/MainActivity.kt" && cmp -s "$d/app/src/main/res/drawable/ic_fg.xml" "$repo/starter/res/drawable/ic_fg.xml" \
  && [ -f "$d/app/src/main/res/raw/pixel_dawn.wav" ] || fail "Hello World isn't the showcase"
git -C "$d" log --format=%s | grep -q "Hello World is Neon Run, the showcase" || fail "the showcase isn't saved in its history"
ls "$w/cache/icons"/hello-world-*.png >/dev/null 2>&1 || fail "no list icon drawn: $(cat "$w/cache/icons.log" 2>/dev/null)"
# Changed by the person since: left as it is.
printf 'package com.hatchlybox.hello_world\n// the greeting from before\n// mine\n' > "$j/MainActivity.kt"; cp "$j/MainActivity.kt" "$w/mine.kt"
in_engine "STARTER_OLD_SHA=$old; missing_icons" >/dev/null 2>&1 || true; cmp -s "$j/MainActivity.kt" "$w/mine.kt" || fail "a changed Hello World was replaced"
echo '{"slug":"x","pkg":"com.x.x","label":"X","status":"ready","apk":"/x.apk","artifacts":{"apk":{"sha256":"a"}},"created":1,"updated":1,"history":[]}' > "$w/apps/x/.hatchlybox.json"
[ "$(h list | jq -r '.[] | select(.slug == "x") | .state.word')" = "ready for your phone" ] || fail "a computer's words: $(h list | jq -c '.[] | select(.slug == "x") | .state')"
ok "a computer says an Android version is for the phone; an untouched Hello World becomes the showcase, a changed one stays"

# Every app its own icon: the template's placeholder goes back to the agent once, before the build; a game doesn't.
a=$w/apps/plain; mkdir -p "$a/app/src/main/res/drawable"; cp "$repo/template/app/src/main/res/drawable/ic_fg.xml" "$a/app/src/main/res/drawable/"
out=$(in_engine 'job() { :; }; run_agent() { echo "agent: $3"; }; own_icon plain opencode')
grep -q "placeholder launcher icon" <<< "$out" || fail "placeholder icon not sent back: $out"
echo '<vector/>' > "$a/app/src/main/res/drawable/ic_fg.xml"
[ -z "$(in_engine 'job() { :; }; run_agent() { echo "agent: $3"; }; own_icon plain opencode')" ] || fail "an own icon was sent back"
ok "every app gets its own icon: the template's placeholder goes back to the AI helper once"
