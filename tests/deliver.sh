#!/usr/bin/env bash
# Delivery to Android on any system: a phone reconnects to its own wireless debugging (127.0.0.1), a computer to the
# phone at the address it announces; pair/connect take a port or host:port; adb is the system's or the SDK's;
# built APKs are offered to the phone's own browser, or by a computer to phones on its Wi-Fi (with a QR code).
set -euo pipefail
repo=$(cd "$(dirname "$0")/.." && pwd)
w=$(mktemp -d)
port=$((18700 + RANDOM % 200))
trap 'pkill -f "Serve.java $port " 2>/dev/null || true; rm -rf "$w"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }
ok() { echo "PASS: $*"; }

# A fake adb: one phone that announces itself on mDNS at 192.168.1.20:37001 and accepts connections there (or,
# on a phone, at its own 127.0.0.1:37001). Every call is logged.
mkdir -p "$w/fake"
cat > "$w/fake/adb" <<'EOF'
#!/bin/sh
echo "$*" >> "$FAKE/calls"
case "$1" in
  devices) echo "List of devices attached"; [ -s "$FAKE/up" ] && printf '%s\tdevice\n' "$(cat "$FAKE/up")"; true ;;
  mdns) echo "List of discovered mdns services"; echo "adb-R5CR10ABC _adb-tls-connect._tcp 192.168.1.20:37001" ;;
  connect) case "$2" in 127.0.0.1:37001|192.168.1.20:37001) echo "$2" > "$FAKE/up"; echo "connected to $2" ;; *) echo "failed to connect to $2"; exit 1 ;; esac ;;
  pair) echo "Successfully paired to $2" ;;
esac
EOF
chmod +x "$w/fake/adb"

# on <platform> <code>: run code inside the engine (test mode) on that platform, the fake adb first on the PATH.
on() {
  rm -rf "$w/data"; mkdir -p "$w/data" "$w/cache"; ln -s "$repo/bin" "$w/data/bin"; cp "$repo/platforms/$1/platform.env" "$w/data/"
  FAKE=$w/fake PATH="$w/fake:$PATH" HATCHLYBOX_HOME=$w/data HATCHLYBOX_CACHE=$w/cache HATCHLYBOX_APPS=$w/apps HATCHLYBOX_TEST=1 \
    SERVE_PORT_TEST=$port bash -c 'source "$0"; SERVE_PORT=$SERVE_PORT_TEST; eval "$1"' "$repo/bin/hatchlybox" "$2"
}
fresh() { rm -f "$w/fake/up" "$w/fake/calls" "$w/cache/adb-port"; }

[ "$(on linux 'echo $(adb_addr 5555) $(adb_addr 192.168.1.5:5555)')" = "127.0.0.1:5555 192.168.1.5:5555" ] || fail "adb_addr"

# A phone finds its own wireless debugging and remembers the port; after a reboot it goes back to it.
fresh; on hatchlybox 'adb_reconnect' || fail "phone didn't connect: $(cat "$w/fake/calls")"
grep -qx "connect 127.0.0.1:37001" "$w/fake/calls" && [ "$(cat "$w/cache/adb-port")" = 37001 ] || fail "phone: $(cat "$w/fake/calls")"
rm -f "$w/fake/up" "$w/fake/calls"; on hatchlybox 'adb_reconnect'
[ "$(head -2 "$w/fake/calls" | tail -1)" = "connect 127.0.0.1:37001" ] || fail "phone after a reboot: $(cat "$w/fake/calls")"
ok "a phone reconnects to its own wireless debugging"

# A computer connects to the phone at the address it announces, and goes back there next time.
for p in linux macos; do
  fresh; on $p 'adb_reconnect' || fail "$p didn't connect: $(cat "$w/fake/calls")"
  grep -qx "connect 192.168.1.20:37001" "$w/fake/calls" && [ "$(cat "$w/cache/adb-port")" = 192.168.1.20:37001 ] || fail "$p: $(cat "$w/fake/calls")"
  rm -f "$w/fake/up" "$w/fake/calls"; on $p 'adb_reconnect'
  [ "$(head -2 "$w/fake/calls" | tail -1)" = "connect 192.168.1.20:37001" ] || fail "$p after a reboot: $(cat "$w/fake/calls")"
done
ok "a computer reconnects to the phone on its network"

# pair and connect: a port is this phone's own, host:port a phone on the network.
fresh
on linux 'HATCHLYBOX_TEST= "$0" pair 192.168.1.20:41000 123456 >/dev/null; HATCHLYBOX_TEST= "$0" pair 41000 654321 >/dev/null; HATCHLYBOX_TEST= "$0" connect 192.168.1.20:37001 >/dev/null'
grep -qx "pair 192.168.1.20:41000 123456" "$w/fake/calls" && grep -qx "pair 127.0.0.1:41000 654321" "$w/fake/calls" \
  && [ "$(cat "$w/cache/adb-port")" = 192.168.1.20:37001 ] || fail "pair/connect: $(cat "$w/fake/calls")"
ok "pair and connect take a port or host:port"

# adb: the system's, else the SDK's platform-tools.
mkdir -p "$w/sdk/platform-tools"; cp "$w/fake/adb" "$w/sdk/platform-tools/adb"
mkdir -p "$w/noadb"; sh=$(type -P bash)
[ "$(PATH=$w/noadb ANDROID_HOME=$w/sdk "$sh" -c 'source "$0"; adb_bin' "$repo/bin/reliability.sh" 2>/dev/null)" = "$w/sdk/platform-tools/adb" ] || fail "SDK adb"
[ "$(PATH="$w/fake:$PATH" ANDROID_HOME=$w/sdk bash -c 'source "$0"; adb_bin' "$repo/bin/reliability.sh" 2>/dev/null)" = "$w/fake/adb" ] || fail "system adb first"
ok "adb from the system, else the SDK's platform-tools"

# Downloads: a phone serves its own browser (127.0.0.1); a computer serves its Wi-Fi (0.0.0.0) and links with its
# address; changing between the two restarts the server; files answer only under the token.
mkdir -p "$w/cache/apks"; echo "an apk" > "$w/cache/apks/demo.apk"
u=$(on hatchlybox 'serve; serve_url demo.apk')
[[ $u == http://127.0.0.1:$port/*/demo.apk ]] || fail "phone link: $u"
[ "$(curl -s "http://127.0.0.1:$port/.version")" = "4 127.0.0.1" ] && [ "$(curl -s "$u")" = "an apk" ] || fail "phone server"
lan=$(bash -c 'source "$0"; lan_ip' "$repo/bin/compat.sh"); lan=${lan:-127.0.0.1}
mkdir -p "$w/cache/apks"; echo "an apk" > "$w/cache/apks/demo.apk"
u=$(HATCHLYBOX_LAN_IP=$lan on linux 'serve; serve_url demo.apk')
[[ $u == "http://$lan:$port/"*/demo.apk ]] || fail "computer link: $u"
[ "$(curl -s "http://127.0.0.1:$port/.version")" = "4 0.0.0.0" ] || fail "computer server: $(curl -s "http://127.0.0.1:$port/.version")"
[ "$(curl -s "$u")" = "an apk" ] || fail "download from $u"
[ "$(curl -s -o /dev/null -w '%{http_code}' "http://$lan:$port/wrong-token/demo.apk")" = 404 ] || fail "file without its token"
ok "downloads: the phone's own browser, or a computer's Wi-Fi (at $lan), only under the token"

# The QR code a person at a computer scans: square rows of 1 and 0.
q=$(on linux 'HATCHLYBOX_TEST= "$0" qr "http://192.168.1.9:8765/token/demo.apk"')
n=$(wc -l <<< "$q"); [ "$n" -ge 21 ] && ! grep -qv "^[01]\{$n\}$" <<< "$q" || fail "qr: $q"
ok "hatchlybox qr gives the download link as a QR code ($n×$n)"
