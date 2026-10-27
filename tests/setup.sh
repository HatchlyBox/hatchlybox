#!/usr/bin/env bash
# Android building's setup as the front end sees it: setup-state says running (only while its process lives),
# stopped (killed midway), failed (with the log's last lines) or none; doctor names a setup at work or one that
# failed instead of saying "ready"; a second setup says one is already running; a failure is printed in words.
set -euo pipefail
repo=$(cd "$(dirname "$0")/.." && pwd)
w=$(mktemp -d)
trap 'rm -rf "$w"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }
ok() { echo "PASS: $*"; }
export HATCHLYBOX_HOME=$w/data HATCHLYBOX_CACHE=$w/cache HATCHLYBOX_APPS=$w/apps HATCHLYBOX_TEST=1
mkdir -p "$w/data" "$w/cache" "$w/apps"
ln -s "$repo/bin" "$w/data/bin"; cp "$repo/platforms/linux/platform.env" "$w/data/"
set +e
source "$repo/bin/hatchlybox"
set -e

[ "$(setup_state | jq -r .state)" = none ] || fail "never run: $(setup_state)"
step 2 "looking for an Android SDK"
s=$(setup_state)
[ "$(jq -r .state <<< "$s")" = running ] && [ "$(setup_where)" = "step 2 of 5: looking for an Android SDK" ] || fail "running: $s"
setup_running || fail "this process is the setup"
ok "a setup at work: running, with its step"

# The same setup.json from a process that is gone: stopped, not running forever.
jq -c '.pid=999999 | .process="0"' "$SETUP" > "$SETUP.tmp" && mv "$SETUP.tmp" "$SETUP"
[ "$(setup_state | jq -r .state)" = stopped ] && ! setup_running || fail "killed midway: $(setup_state)"
ok "one killed midway: stopped"

printf '%s\n' '== [4/4] setting up the app template' '== gradle assembleRelease' 'Exception in thread "main" java.io.FileNotFoundException: x.lck (Read-only file system)' >> "$SLOG"
out=$( (die "the Hello World test app didn't build") 2>&1 ) && fail "die returns"
[ "$(head -1 <<< "$out")" = "Android building isn't set up: the Hello World test app didn't build" ] && grep -q "hatchlybox setup tries again" <<< "$out" || fail "printed: $out"
s=$(setup_state)
[ "$(jq -r .state <<< "$s")" = failed ] && [ "$(jq -r '.log | length' <<< "$s")" = 1 ] && jq -r '.log[0]' <<< "$s" | grep -q 'Read-only file system' || fail "failed: $s"
ok "a failure: printed in words; setup-state has the log's last lines (not its step headings)"

# hatchlybox itself: doctor and a second setup, against these states.
mkdir -p "$w/data/template" && touch "$w/data/template/gradlew" && chmod +x "$w/data/template/gradlew"
h() { env -u HATCHLYBOX_TEST HATCHLYBOX_HOME="$w/data" HATCHLYBOX_CACHE="$w/cache" HATCHLYBOX_APPS="$w/apps" "$repo/bin/hatchlybox" "$@" 2>&1; }
grep -q "^missing Android building: the last setup didn't finish (the Hello World test app didn't build)" <<< "$(h doctor)" || fail "doctor after a failure: $(h doctor)"
sleep 30 & sleeper=$!
jq -c --argjson p $sleeper --arg id "$(process_id $sleeper)" '.state="running" | .step=2 | .msg="looking for an Android SDK" | .pid=$p | .process=$id' "$SETUP" > "$SETUP.tmp" && mv "$SETUP.tmp" "$SETUP"
d=$(h doctor)
grep -qx "missing Android building: being set up now (step 2 of 5: looking for an Android SDK)" <<< "$d" && ! grep -q "missing Android SDK" <<< "$d" || fail "doctor while running: $d"
rc=0; out=$(h setup) || rc=$?
[ $rc = 1 ] && [ "$out" = "Android building is already being set up (step 2 of 5: looking for an Android SDK): wait for it to finish" ] || fail "second setup: $rc $out"
kill $sleeper 2>/dev/null || true
ok "doctor names a setup at work or one that failed; a second setup says one is running"

# Google's SDK licence: never accepted for the person. Without their yes, setup downloads nothing.
rm -f "$w/cache/setup.json"; mkdir -p "$w/data/template/app"
h license check android-sdk >/dev/null && fail "accepted before anyone did"
mkdir -p "$w/fakebin"; printf '#!/bin/sh\necho "Filesystem 1K-blocks Used Available Use%% Mounted"\necho "x 99999999 0 99999999 0%% /"\n' > "$w/fakebin/df"; chmod +x "$w/fakebin/df"
out=$(PATH="$w/fakebin:$PATH" env -u HATCHLYBOX_TEST HATCHLYBOX_HOME="$w/data" HATCHLYBOX_CACHE="$w/cache" HATCHLYBOX_APPS="$w/apps" HATCHLYBOX_SDK_SEARCH="" ANDROID_HOME= "$repo/bin/hatchlybox" setup 2>&1) && fail "setup went on: $out"
grep -q "License Agreement isn't accepted yet" <<< "$out" || fail "not accepted: $out"
[ ! -e "$w/data/sdk/cmdline-tools" ] || fail "downloaded anyway"
h license accept android-sdk | grep -q "accepted Google's Android SDK License Agreement" && h license check android-sdk >/dev/null && [ "$(jq -r '."android-sdk" | type' "$w/data/accepted.json")" = number ] || fail "accept"
ok "Google's SDK licence: setup waits for the person's yes (hatchlybox license accept android-sdk), then remembers it"
