#!/usr/bin/env bash
# A slow/offline service cannot block navigation or be restarted on every tap.
set -euo pipefail
repo=$(cd "$(dirname "$0")/.." && pwd)
w=$(mktemp -d)
trap 'rm -rf "$w"' EXIT
export CACHE=$w/cache DATA=$w/data
mkdir -p "$DATA/bin" "$CACHE/polls"
cp "$repo/bin/poll.sh" "$DATA/bin/"
cat > "$DATA/bin/hatchlybox" <<'MOCK'
#!/usr/bin/env bash
source "$DATA/bin/poll.sh"
if [ "$1" = _poll ]; then poll_worker "$2"; exit $?; fi
echo called >> "$CACHE/calls"
sleep 2
[ ! -f "$CACHE/fail" ] || exit 1
echo refreshed
MOCK
chmod +x "$DATA/bin/hatchlybox"
source "$repo/bin/poll.sh"
echo cached > "$CACHE/polls/adb.out"
start=$SECONDS
[ "$(poll_cached adb)" = cached ]
[ "$((SECONDS-start))" -lt 2 ]
for _ in $(seq 10); do poll_cached adb >/dev/null; done
for _ in $(seq 50); do [ "$(cat "$CACHE/polls/adb.out")" = refreshed ] && break; sleep .1; done
[ "$(cat "$CACHE/polls/adb.out")" = refreshed ]
[ "$(wc -l < "$CACHE/calls")" = 1 ]
poll_cached adb >/dev/null
[ "$(wc -l < "$CACHE/calls")" = 1 ]
echo 0 > "$CACHE/polls/adb.at"
touch "$CACHE/fail"
poll_cached adb >/dev/null
for _ in $(seq 50); do [ "$(wc -l < "$CACHE/calls")" = 2 ] && break; sleep .1; done
sleep 2.2
[ "$(cat "$CACHE/polls/adb.out")" = refreshed ]
poll_cached adb >/dev/null
[ "$(wc -l < "$CACHE/calls")" = 2 ]
if poll_cached invalid; then exit 1; fi
echo 'PASS: nonblocking cache, single-flight refresh, TTL, offline preservation, task whitelist'
