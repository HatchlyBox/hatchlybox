#!/usr/bin/env bash
# The platform layer: platform.env sets ports and agent settings, the engine itself never changes.
set -euo pipefail
repo=$(cd "$(dirname "$0")/.." && pwd)
w=$(mktemp -d)
trap 'rm -rf "$w"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }
ok() { echo "PASS: $*"; }
data() { rm -rf "$w/data"; mkdir -p "$w/data"; ln -s "$repo/bin" "$w/data/bin"; [ -z "${1:-}" ] || cp "$repo/platforms/$1/platform.env" "$w/data/"; }
run() { HATCHLYBOX_HOME=$w/data HATCHLYBOX_CACHE=$w/cache HATCHLYBOX_APPS=$w/apps "$repo/bin/hatchlybox" "$@"; }

# Without a platform file: a plain Linux computer's settings.
data
j=$(run platform)
[ "$(jq -r .engine <<< "$j")" = "Hatchlybox Engine" ] && [ "$(jq -r .platform <<< "$j")" = linux ] || fail "default platform: $j"
v=$(HATCHLYBOX_HOME=$w/data HATCHLYBOX_CACHE=$w/cache HATCHLYBOX_TEST=1 bash -c 'source "$0"; echo "$SERVE_PORT|$OPENCODE_ARGS|$ISOLATION|$SERVE_LAN"' "$repo/bin/hatchlybox")
[ "$v" = "8765||required|1" ] || fail "default settings: $v"
ok "no platform.env: a Linux computer's settings"

for p in hatchlybox linux; do
  data $p
  j=$(run platform)
  [ "$(jq -r .platform <<< "$j")" = $p ] && [ "$(jq '.capabilities | length' <<< "$j")" -gt 0 ] || fail "$p: $j"
  v=$(HATCHLYBOX_HOME=$w/data HATCHLYBOX_CACHE=$w/cache HATCHLYBOX_TEST=1 bash -c 'source "$0"; echo "$SERVE_PORT|$OPENCODE_ARGS"' "$repo/bin/hatchlybox")
  case $p in
    linux) [ "$v" = "8765|" ] || fail "linux settings: $v" ;;
    hatchlybox) [ "$v" = "8876|" ] || fail "hatchlybox settings: $v" ;;
  esac
  # What an agent gets from isolate (this kernel has no sandbox: the compatibility branch).
  mkdir -p "$w/proj"
  [ $p = linux ] && echo '{"agentIsolation":"compatible"}' > "$w/data/settings.json"
  e=$(HATCHLYBOX_HOME=$w/data HATCHLYBOX_CACHE=$w/cache "$repo/bin/isolate" agent "$w/proj" env 2>/dev/null)
  grep -qx HATCHLYBOX_MANAGED_AGENT=1 <<< "$e" || fail "$p: managed flag"
  case $p in
    linux) grep -q "ADB_SERVER_SOCKET=tcp:127.0.0.1:5037" <<< "$e" && grep -qx 'OPENCODE_PERMISSION={"\*":"allow"}' <<< "$e" || fail "linux agent env: $e" ;;
    hatchlybox) grep -q "ADB_SERVER_SOCKET=tcp:127.0.0.1:5041" <<< "$e" && grep -qx 'OPENCODE_PERMISSION={"\*":"allow"}' <<< "$e" || fail "hatchlybox agent env: $e" ;;
  esac
  ok "$p: ports, OpenCode and the agent's environment"
done

# Folders (paths.sh): the front end's HATCHLYBOX_* win; otherwise the system's own places (macOS simulated with a
# uname that says Darwin).
dirs() { env -i HOME="$1" PATH="$2" XDG_DATA_HOME="${3:-}" bash -c 'source "$0"; echo "$DATA|$CACHE|$APPS|$PORTS"' "$repo/bin/paths.sh"; }
h="$w/home one"; mkdir -p "$h"
[ "$(dirs "$h" "$PATH")" = "$h/.local/share/hatchlybox|$h/.cache/hatchlybox|$h/Hatchlybox/apps|$h/Hatchlybox/ports" ] || fail "linux dirs: $(dirs "$h" "$PATH")"
[ "$(dirs "$h" "$PATH" "$h/xdg")" = "$h/xdg/hatchlybox|$h/.cache/hatchlybox|$h/Hatchlybox/apps|$h/Hatchlybox/ports" ] || fail "XDG_DATA_HOME"
mkdir -p "$w/darwin"; printf '#!/bin/sh\necho Darwin\n' > "$w/darwin/uname"; chmod +x "$w/darwin/uname"
[ "$(dirs "$h" "$w/darwin:$PATH")" = "$h/Library/Application Support/Hatchlybox|$h/Library/Caches/Hatchlybox|$h/Hatchlybox/apps|$h/Hatchlybox/ports" ] || fail "macOS dirs: $(dirs "$h" "$w/darwin:$PATH")"
[ "$(env -i HOME="$h" PATH="$PATH" HATCHLYBOX_HOME=/x HATCHLYBOX_APPS=/y bash -c 'source "$0"; echo "$DATA|$APPS"' "$repo/bin/paths.sh")" = "/x|/y" ] || fail "front end's folders"
ok "folders: the front end's, else Linux's or macOS's own places"

# The environment section of a project's AGENTS.md comes from the platform.
data hatchlybox; cp "$repo/creation/AGENTS.md" "$repo/platforms/hatchlybox/environment.md" "$w/data/"
e=$(HATCHLYBOX_HOME=$w/data HATCHLYBOX_CACHE=$w/cache HATCHLYBOX_TEST=1 bash -c 'source "$0"; agents_doc /dev/stdout' "$repo/bin/hatchlybox")
grep -q "inside the Hatchlybox app" <<< "$e" && ! grep -q "with internet. .uname -a" <<< "$e" && grep -q "^## Tools already here" <<< "$e" || fail "platform environment"
rm "$w/data/environment.md"
e=$(HATCHLYBOX_HOME=$w/data HATCHLYBOX_CACHE=$w/cache HATCHLYBOX_TEST=1 bash -c 'source "$0"; agents_doc /dev/stdout' "$repo/bin/hatchlybox")
grep -q "You run on the user's device" <<< "$e" || fail "neutral environment"
ok "a project's AGENTS.md says where the agent really is"

# install.sh: a computer's own install.
h2="$w/home two"; mkdir -p "$h2"
# Only that home: the desktop's XDG folders (Omarchy sets them) would put it in the real user's install and app menu.
h2() { env -u XDG_DATA_HOME -u XDG_CACHE_HOME -u XDG_CONFIG_HOME HOME="$h2" "$@"; }
h2 bash "$repo/install.sh" linux > /dev/null
[ "$(h2 "$h2/.local/bin/hatchlybox" platform | jq -r .platform)" = linux ] && [ "$(h2 "$h2/.local/bin/hatchlybox" creations)" = "[]" ] \
  && [ -f "$h2/.local/share/hatchlybox/environment.md" ] || fail "desktop install"
ok "install.sh sets a computer up"

# Job supervision without /proc (macOS, BSD): a worker is known by ps; a live one is never taken for dead.
(
  export HATCHLYBOX_HOME=$repo HATCHLYBOX_CACHE=$w/sup HATCHLYBOX_APPS=$w/sup-apps HATCHLYBOX_TEST=1 HATCHLYBOX_PROC=/nonexistent
  set +e; source "$repo/bin/hatchlybox"; set -e
  list_apps() { :; }
  mkdir -p "$CACHE/jobs/s1"; JOB=$CACHE/jobs/s1/job.json LOG=$CACHE/jobs/s1/log.txt; : > "$LOG"
  sleep 60 & pid=$!
  id=$(process_id "$pid")
  [ -n "$id" ] && [ "$id" = "$(process_id "$pid")" ] && [ "$id" != "$(process_id $$)" ] || fail "ps identity: $id"
  echo "{\"id\":\"s1\",\"kind\":\"app\",\"slug\":\"x\",\"phase\":\"agent\",\"updated\":1,\"pid\":$pid,\"process\":\"$id\"}" > "$JOB"
  cp "$JOB" "$CACHE/job.json"
  worker_alive || fail "live worker not seen"
  recover_stale_job
  [ "$(jq -r .phase "$JOB")" = agent ] && kill -0 "$pid" || fail "health check touched a live job"
  kill "$pid"; wait "$pid" 2>/dev/null || true
  ! worker_alive || fail "finished worker still seen"
)
ok "job supervision without /proc: live workers are known, finished ones aren't"

