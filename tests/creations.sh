#!/usr/bin/env bash
# One creation for every system: the index (each creation once, a system per version, "here", older
# versions), and making versions (new, from the newest version, changes) with a stand-in agent.
set -euo pipefail
repo=$(cd "$(dirname "$0")/.." && pwd)
w=$(mktemp -d)
trap 'rm -rf "$w"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }
ok() { echo "PASS: $*"; }
mkdir -p "$w/data" "$w/apps/notes" "$w/apps/timer" "$w/ports/timer/linux/export" "$w/ports/timer/web/export" "$w/ports/tiny-paint/windows" "$w/ports/broken/linux"
ln -s "$repo/bin" "$w/data/bin"; ln -s "$repo/template" "$w/data/template"; ln -s "$repo/creation/AGENTS.md" "$w/data/AGENTS.md"; cp "$repo/platforms/hatchlybox/platform.env" "$w/data/"
echo '{"slug":"notes","label":"Notes","pkg":"com.hatchlybox.notes","status":"installed","apk":"x","created":10,"updated":20,"artifacts":{"apk":{"sha256":"a","at":15}},"installedArtifact":{"sha256":"a"},"outcomes":{"install":"verified"}}' > "$w/apps/notes/.hatchlybox.json"
# Timer: made for Android (content 30), its Linux version changed later on request (50), its web version a copy of Android (30).
echo '{"slug":"timer","label":"Timer","pkg":"com.hatchlybox.timer","status":"failed","created":30,"updated":40,"content":30}' > "$w/apps/timer/.hatchlybox.json"
echo '{"target":"linux","agent":"codex","created":45,"changed":50,"content":50}' > "$w/ports/timer/linux/.port.json"
echo '{"target":"web","agent":"codex","created":46,"changed":47,"content":30}' > "$w/ports/timer/web/.port.json"
echo '{"target":"windows","agent":"claude","created":60,"idea":"a tiny paint app","label":"Tiny Paint"}' > "$w/ports/tiny-paint/windows/.port.json"
echo 'not json' > "$w/ports/broken/linux/.port.json"
mkdir -p "$w/cache"; echo '{"kind":"port","slug":"tiny-paint","arg":"windows","phase":"agent"}' > "$w/cache/job.json"
j=$(HATCHLYBOX_HOME=$w/data HATCHLYBOX_CACHE=$w/cache HATCHLYBOX_APPS=$w/apps HATCHLYBOX_PORTS=$w/ports "$repo/bin/hatchlybox" creations)
c() { jq -c --arg s "$1" '.[] | select(.slug == $s)' <<< "$j"; }
[ "$(jq length <<< "$j")" = 4 ] || fail "4 creations: $j"
[ "$(c notes | jq -c '.systems | keys')" = '["android"]' ] && [ "$(c notes | jq -r .systems.android.state)" = installed ] \
  && [ "$(c notes | jq -r .systems.android.here)" = true ] || fail "android only: $(c notes)"
ok "an Android app is one creation, installable here"
[ "$(c timer | jq -c '.systems | keys')" = '["android","linux","web"]' ] && [ "$(c timer | jq -r .systems.linux.word)" = "ready to export" ] \
  && [ "$(c timer | jq -r .systems.linux.here)" = false ] && [ "$(c timer | jq -r .systems.web.here)" = true ] \
  && [ "$(c timer | jq -r .systems.web.word)" = "ready to open" ] || fail "three systems: $(c timer)"
ok "its other versions join the same creation: web runs here, Linux exports"
[ "$(c timer | jq -r .systems.android.older)" = linux ] && [ "$(c timer | jq -r .systems.web.older)" = linux ] \
  && [ "$(c timer | jq -r '.systems.linux.older // "none"')" = none ] || fail "older versions: $(c timer)"
ok "versions behind one changed later are older than it; a copy is never newer than its source"
[ "$(c tiny-paint | jq -c '.systems | keys')" = '["windows"]' ] && [ "$(c tiny-paint | jq -r .label)" = "Tiny Paint" ] \
  && [ "$(c tiny-paint | jq -r .systems.windows.word)" = "being made" ] && [ "$(c broken | jq -r .systems.linux.word)" = "not finished" ] || fail "port only: $(c tiny-paint) $(c broken)"
ok "a creation made only for another system: being made while its job runs, else not finished"
[ "$(jq -c '[.[].updated] == ([.[].updated] | sort | reverse)' <<< "$j")" = true ] || fail "newest first: $(jq -c '[.[].updated]' <<< "$j")"
ok "unreadable metadata doesn't break the index; newest first"

# Making versions, with a stand-in agent: the engine sourced, the worker's steps called directly.
(
  export HATCHLYBOX_HOME=$w/data HATCHLYBOX_CACHE=$w/mk HATCHLYBOX_APPS=$w/apps HATCHLYBOX_PORTS=$w/ports2 HATCHLYBOX_TEST=1
  set +e; source "$repo/bin/hatchlybox"; set -e
  list_apps() { :; }; can_start() { :; }
  started=(); start() { started=("$@"); }
  JOB=$CACHE/job.json LOG=$CACHE/log.txt; mkdir -p "$CACHE"; echo '{}' > "$JOB"; : > "$LOG"
  prompts=$w/prompts; : > "$prompts"
  run_agent() { printf '%s\n====\n' "$3" >> "$prompts"; mkdir -p "$2/export"; [ -f "$2/export/install.sh" ] || echo true > "$2/export/install.sh"; [ -z "${FAIL_AGENT:-}" ] || return 1; }
  create_cmd windows claude "a tiny paint app with layers"
  [ "${started[*]}" = "port tiny-paint-layers claude windows" ] || fail "create started: ${started[*]}"
  [ "$(jq -r .idea "$PORTS/tiny-paint-layers/windows/.port.json")" = "a tiny paint app with layers" ] || fail "port metadata"
  port_work tiny-paint-layers claude windows
  grep -q "Make a new app from scratch: a tiny paint app with layers" "$prompts" || fail "new prompt: $(cat "$prompts")"
  [ "$(jq -r .phase "$JOB")" = done ] && [ "$(version_time tiny-paint-layers windows)" -gt 0 ] || fail "made: $(cat "$JOB")"
  ok "a creation can start on any system"
  t0=$(version_time tiny-paint-layers windows); : > "$prompts"
  make_cmd tiny-paint-layers linux codex
  port_work tiny-paint-layers codex linux
  grep -q "Its Windows version is in $PORTS/tiny-paint-layers/windows" "$prompts" || fail "from prompt: $(cat "$prompts")"
  [ "$(version_time tiny-paint-layers linux)" = "$t0" ] || fail "a copy keeps its source's time"
  ok "another system's version is made from the newest one, and isn't newer than it"
  sleep 1; : > "$prompts"
  make_cmd tiny-paint-layers linux codex add a dark mode
  port_work tiny-paint-layers codex linux
  grep -q "Change this Linux version of .* add a dark mode" "$prompts" || fail "change prompt: $(cat "$prompts")"
  [ "$(version_time tiny-paint-layers linux)" -gt "$t0" ] && [ "$(newest_version tiny-paint-layers)" = linux ] || fail "a change is new"
  : > "$prompts"; make_cmd tiny-paint-layers windows claude; port_work tiny-paint-layers claude windows
  grep -q "Bring this Windows version .* up to date with its newer Linux version" "$prompts" || fail "update prompt: $(cat "$prompts")"
  [ "$(version_time tiny-paint-layers windows)" = "$(version_time tiny-paint-layers linux)" ] || fail "brought up to date"
  ok "a change makes a version the newest; the others are brought up to date from it"
  FAIL_AGENT=1 make_cmd tiny-paint-layers web opencode
  FAIL_AGENT=1 port_work tiny-paint-layers opencode web || true
  [ "$(jq -r .phase "$JOB")" = failed ] && [ "$(jq -r '.changed // "none"' "$PORTS/tiny-paint-layers/web/.port.json")" = none ] || fail "failed agent"
  ok "a failed version stays unfinished"
  make_cmd tiny-paint-layers android claude
  [ "${started[0]}" = app ] && [ "$(jq -r .from "$APPS/tiny-paint-layers/.hatchlybox.json")" = linux ] \
    && [ "$(jq -r .pkg "$APPS/tiny-paint-layers/.hatchlybox.json")" = com.hatchlybox.tiny_paint_layers ] \
    && [ "$HATCHLYBOX_CONTENT" = "$(version_time tiny-paint-layers linux)" ] || fail "android from: $(cat "$APPS/tiny-paint-layers/.hatchlybox.json")"
  grep -q "Make the Android version of this app" <<< "${started[3]}" || fail "android prompt"
  ok "an Android version is scaffolded and made from the newest version"
  # A version's job stopped by the system carries on too, by making it again from its folder.
  mkdir -p "$CACHE/jobs/p1"
  echo '{"id":"p1","kind":"port","slug":"tiny-paint-layers","arg":"linux","agent":"codex","phase":"interrupted","started":1,"updated":1,"pid":0}' > "$CACHE/jobs/p1/job.json"
  cp "$CACHE/jobs/p1/job.json" "$CACHE/job.json"; JOB=$CACHE/job.json; : > "$CACHE/jobs/p1/log.txt"
  HATCHLYBOX_SELF=true recover_stale_job
  [ "$(jq -r .msg "$CACHE/jobs/p1/job.json")" = "stopped before it finished; carrying on (1/3)" ] || fail "port resume: $(cat "$CACHE/jobs/p1/job.json")"
  ok "a stopped version's job carries on"
)
