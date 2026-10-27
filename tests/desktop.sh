#!/usr/bin/env bash
# The desktop front end (hatchlybox desktop, Desk.java): one server per user on 127.0.0.1, reused; signing in with the
# launcher's token sets the cookie; nothing works without it, from another Host (DNS rebinding) or without the
# X-Hatchlybox header (other sites); only the front end's commands run, with their arguments intact (no shell); long
# ones are tasks to poll; web versions are served from their export folder only, sandboxed; stop stops it.
set -euo pipefail
repo=$(cd "$(dirname "$0")/.." && pwd)
w=$(mktemp -d)
cleanup() { h desktop stop >/dev/null 2>&1 || true; rm -rf "$w" 2>/dev/null || true; }
trap cleanup EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }
ok() { echo "PASS: $*"; }

mkdir -p "$w/home" "$w/data" "$w/cache" "$w/apps" "$w/ports/notes/web/export/css" "$w/ports/notes/web/inner"
ln -s "$repo/bin" "$w/data/bin"; ln -s "$repo/desktop" "$w/data/desktop"; cp "$repo/platforms/linux/platform.env" "$w/data/"
echo '<h1>Notes</h1>' > "$w/ports/notes/web/export/index.html"; echo 'body{}' > "$w/ports/notes/web/export/css/a.css"
echo secret > "$w/ports/notes/web/inner/secret.txt"; ln -s ../inner/secret.txt "$w/ports/notes/web/export/link.txt"
echo '{"label":"Notes","created":1,"changed":2,"content":2}' > "$w/ports/notes/web/.port.json"
port=$((18000 + RANDOM % 2000))
h() { env HOME="$w/home" HATCHLYBOX_HOME="$w/data" HATCHLYBOX_CACHE="$w/cache" HATCHLYBOX_APPS="$w/apps" HATCHLYBOX_PORTS="$w/ports" HATCHLYBOX_DESK_PORT=$port HATCHLYBOX_OPENER=true "$repo/bin/hatchlybox" "$@"; }

u=$(h desktop --no-open) || fail "start: $(cat "$w/cache/desktop.log" 2>/dev/null)"
p=$(jq -r .port "$w/cache/desktop.json"); t=$(jq -r .token "$w/cache/desktop.json")
[ "$u" = "http://127.0.0.1:$p/" ] && [ "$(stat -c %a "$w/cache/desktop.json")" = 600 ] || fail "address $u, state $(stat -c %a "$w/cache/desktop.json")"
[ "$(h desktop --no-open)" = "$u" ] && [ "$(jq -r .token "$w/cache/desktop.json")" = "$t" ] || fail "a second start reuses the running one"
ok "one server on 127.0.0.1, reused; its token in a private file"
# After an update (another Desk.java), the running server is replaced: a new one, a new token.
jq '.build = "old"' "$w/cache/desktop.json" > "$w/s" && mv "$w/s" "$w/cache/desktop.json"
old=$(jq -r .pid "$w/cache/desktop.json")
h desktop --no-open > /dev/null || fail "restart after an update"
[ "$(jq -r .token "$w/cache/desktop.json")" != "$t" ] && ! kill -0 "$old" 2>/dev/null || fail "the old server still runs"
t=$(jq -r .token "$w/cache/desktop.json"); p=$(jq -r .port "$w/cache/desktop.json")
ok "an updated Hatchlybox replaces the server that was running"

b=http://127.0.0.1:$p
code() { curl -s -o /dev/null -w '%{http_code}' "$@"; }
[ "$(code "$b/")" = 403 ] && [ "$(code "$b/?t=wrong")" = 403 ] || fail "no token"
c=$(curl -s -D - -o /dev/null "$b/?t=$t")
grep -q "^HTTP/1.1 302" <<< "$c" && grep -qi "^set-cookie: hatchlybox=$t; Path=/; HttpOnly; SameSite=Strict" <<< "$c" || fail "sign in: $c"
C="Cookie: hatchlybox=$t"
c=$(curl -s -D - -o "$w/page" -H "$C" "$b/")
grep -q "^HTTP/1.1 200" <<< "$c" && grep -qi "^content-security-policy: default-src 'self'" <<< "$c" && grep -q '<title>Hatchlybox</title>' "$w/page" || fail "page: $c"
[ "$(code -H "$C" "$b/app.js")" = 200 ] && [ "$(code -H "$C" "$b/../bin/hatchlybox")" = 404 ] || fail "files"
[ "$(code -H "$C" -H "Host: evil.example:$p" "$b/")" = 421 ] || fail "another Host"
ok "sign-in sets the cookie; nothing without it or from another Host"

api() { curl -s -H "$C" -H 'X-Hatchlybox: 1' -H 'Content-Type: application/json' "$@"; }
[ "$(code -H "$C" -H 'Content-Type: application/json' -d '{"args":["version"]}' "$b/api/run")" = 403 ] || fail "header required"
[ "$(api -d '{"args":["version"]}' "$b/api/run" | jq -r .out | tr -d '\n')" = "$(sed -n 's/^VERSION=//p' "$repo/bin/hatchlybox")" ] || fail "version"
[ "$(code -H "$C" -H 'X-Hatchlybox: 1' -d '{"args":["rm","-rf","/"]}' "$b/api/run")" = 400 ] || fail "not allowed"
[ "$(api -d '{"args":["platform"]}' "$b/api/run" | jq -r .out | jq -r .platform)" = linux ] || fail "platform"
r=$(api -d '{"args":["route","a \"3d\" racing game; with $(spaces) & quotes"]}' "$b/api/run" | jq -r .out | jq -r .system)
[ "$r" = game ] || fail "arguments intact: $r"
id=$(api -d '{"args":["sync","devices"]}' "$b/api/run" | jq -r .task)
for _ in $(seq 1 60); do j=$(api "$b/api/task?id=$id"); [ "$(jq -r .done <<< "$j")" = true ] && break; sleep 0.5; done
[ "$(jq -r .done <<< "$j")" = true ] && [ "$(jq -r .code <<< "$j")" = 0 ] && [ "$(jq -r .out <<< "$j" | tr -d '\n')" = "[]" ] || fail "task: $j"
[ "$(api "$b/api/job" | jq -c .job)" = null ] || fail "no job"
ok "the API: only the front end's commands, arguments intact, long ones as tasks"
# A pairing that asks (sync visible): it runs as a task that takes answers; stop ends it. Other tasks take none.
id=$(HATCHLYBOX_SYNC_NEAR_UDP=$((port + 21)) api -d '{"args":["sync","visible"]}' "$b/api/run" | jq -r .task)
for _ in $(seq 1 60); do j=$(api "$b/api/task?id=$id"); grep -q '"state\\":\\"visible' <<< "$j" && break; sleep 0.5; done
grep -q 'visible' <<< "$(jq -r .out <<< "$j")" || fail "visible: $j"
[ "$(code -H "$C" -H 'X-Hatchlybox: 1' -X POST "$b/api/say?id=$id&answer=rm")" = 400 ] || fail "say takes only yes, no, stop"
[ "$(code -H "$C" -H 'X-Hatchlybox: 1' -X POST "$b/api/say?id=$id&answer=stop")" = 200 ] || fail "stop"
for _ in $(seq 1 30); do [ "$(api "$b/api/task?id=$id" | jq -r .done)" = true ] && break; sleep 0.5; done
[ "$(api "$b/api/task?id=$id" | jq -r .done)" = true ] || fail "visible didn't stop"
ok "a pairing runs as a task that takes yes, no or stop"

[ "$(code -H "$C" "$b/web/notes")" = 302 ] || fail "web redirect"
c=$(curl -s -D - -o "$w/web" -H "$C" "$b/web/notes/")
grep -q '<h1>Notes</h1>' "$w/web" && grep -qi "^content-security-policy: sandbox" <<< "$c" || fail "web page: $c"
[ "$(code -H "$C" "$b/web/notes/css/a.css")" = 200 ] || fail "web asset"
[ "$(code -H "$C" --path-as-is "$b/web/notes/../inner/secret.txt")" = 404 ] && [ "$(code -H "$C" "$b/web/notes/link.txt")" = 404 ] \
  && [ "$(code -H "$C" "$b/web/notes/%2e%2e/inner/secret.txt")" = 404 ] && [ "$(code "$b/web/notes/")" = 403 ] || fail "web escapes"
ok "web versions: their export folder only, sandboxed, signed in"

# Icons: the engine keeps each app's newest as <slug>-<time>.png; the page asks for /icon/<slug>.
mkdir -p "$w/cache/icons"; echo old > "$w/cache/icons/notes-100.png"; echo new > "$w/cache/icons/notes-200.png"; echo other > "$w/cache/icons/notes-app-300.png"
[ "$(curl -s -H "$C" "$b/icon/notes")" = new ] && [ "$(code -H "$C" "$b/icon/note")" = 404 ] && [ "$(code -H "$C" --path-as-is "$b/icon/..")" = 404 ] || fail "icons"
ok "icons: each app's newest, by its own name only"

# A command's standard input (a passphrase) and uploads, against a fake engine that says what it got.
printf '#!/bin/sh\nread -r line || line=none\necho "args: $* | input: $line"\n' > "$w/fake-hatchlybox"; chmod +x "$w/fake-hatchlybox"
p2=$((port + 11)); "${JAVA_HOME:+$JAVA_HOME/bin/}java" "$repo/bin/Desk.java" $p2 "$w/fake-hatchlybox" "$repo/desktop" "$w/cache2" "$w/ports" "$w/desk2.json" "$w/backups" > /dev/null 2>&1 &
d2=$!; for _ in $(seq 1 120); do [ -s "$w/desk2.json" ] && break; sleep 0.5; done
b2=http://127.0.0.1:$(jq -r .port "$w/desk2.json"); C2="Cookie: hatchlybox=$(jq -r .token "$w/desk2.json")"
r=$(curl -s -H "$C2" -H 'X-Hatchlybox: 1' -d '{"args":["checks","x"],"input":"my \"pass\" phrase"}' "$b2/api/run" | jq -r .out)
[ "$r" = 'args: checks x | input: my "pass" phrase' ] || fail "input: $r"
r=$(curl -s -H "$C2" -H 'X-Hatchlybox: 1' -d '{"args":["checks","x"]}' "$b2/api/run" | jq -r .out)
[ "$r" = 'args: checks x | input: none' ] || fail "no input: $r"
echo '{"type": "service_account"}' > "$w/key.json"
f=$(curl -s -H "$C2" -H 'X-Hatchlybox: 1' --data-binary @"$w/key.json" "$b2/api/upload?name=../my%20key.json" | jq -r .path)
[[ $f == "$w/cache2/uploads/"*"-.._my_key.json" ]] && cmp -s "$f" "$w/key.json" && [ "$(stat -c %a "$f")" = 600 ] || fail "upload: $f"
[ "$(code -H "$C2" -H 'X-Hatchlybox: 1' -X POST "$b2/api/upload?name=x")" = 400 ] || fail "empty upload"
kill $d2
ok "a passphrase goes to the command's input only; uploads are kept privately"

h desktop stop | grep -q stopped || fail "stop"
sleep 1; curl -s --max-time 2 "$b/.version" >/dev/null && fail "still running" || true
ok "stop"
