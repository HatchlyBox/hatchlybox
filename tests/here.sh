#!/usr/bin/env bash
# Installing a version on this computer (here.sh): install.sh runs for the user with the folders it may use and
# lists what it made; the library says ready to install, installed, update ready; an update removes what the old
# version had and the new one doesn't; open runs hatchlybox.json's command; uninstall runs uninstall.sh and removes
# the listed paths, never anything outside the user's app folders; sudo and other systems are refused.
set -euo pipefail
repo=$(cd "$(dirname "$0")/.." && pwd)
w=$(mktemp -d)
trap 'rm -rf "$w" 2>/dev/null || true' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }
ok() { echo "PASS: $*"; }

mkdir -p "$w/home" "$w/data" "$w/cache" "$w/apps" "$w/ports"
ln -s "$repo/bin" "$w/data/bin"; cp "$repo/platforms/linux/platform.env" "$w/data/"
h() { env -u XDG_DATA_HOME -u XDG_CONFIG_HOME HOME="$w/home" HATCHLYBOX_HOME="$w/data" HATCHLYBOX_CACHE="$w/cache" HATCHLYBOX_APPS="$w/apps" HATCHLYBOX_PORTS="$w/ports" "$repo/bin/hatchlybox" "$@"; }
word() { h creations | jq -r --arg s "$1" --arg y "${2:-linux}" '.[] | select(.slug == $s) | .systems[$y].word'; }

# version <slug> <content time> <install.sh body>: a finished Linux version whose export installs with that script.
version() {
  local d=$w/ports/$1/linux
  mkdir -p "$d/export"
  # As an agent's change does: the metadata is updated, not replaced (what's installed stays recorded).
  jq -c --arg l "${1^}" --argjson t "$2" '. + {label: $l, created: 1000, changed: $t, content: $t}' "$d/.port.json" 2>/dev/null > "$d/.m" || echo '{}' | jq -c --arg l "${1^}" --argjson t "$2" '{label: $l, created: 1000, changed: $t, content: $t}' > "$d/.m"
  mv "$d/.m" "$d/.port.json"
  printf '%s\n' "$3" > "$d/export/install.sh"
  echo '{"run": "touch \"$HATCHLYBOX_SHARE/opened\""}' > "$d/export/hatchlybox.json"
}

version notes 2000 'set -e
mkdir -p "$HATCHLYBOX_BIN" "$HATCHLYBOX_SHARE/notes" "$HATCHLYBOX_SHARE/applications"
echo "#!/bin/sh" > "$HATCHLYBOX_BIN/notes"; echo v1 > "$HATCHLYBOX_SHARE/notes/data"; echo "[Desktop Entry]" > "$HATCHLYBOX_SHARE/applications/notes.desktop"
printf "%s\n" "$HATCHLYBOX_BIN/notes" "$HATCHLYBOX_SHARE/notes" "$HATCHLYBOX_SHARE/applications/notes.desktop" >> "$HATCHLYBOX_MANIFEST"'
[ "$(word notes)" = "ready to install" ] || fail "before: $(word notes)"
[ "$(h creations | jq -r '.[] | select(.slug == "notes") | .systems.linux.here')" = true ] || fail "linux is here on a Linux computer"
h here install notes linux | grep -q "installed Notes" || fail "install"
[ -f "$w/home/.local/bin/notes" ] && [ "$(cat "$w/home/.local/share/notes/data")" = v1 ] && [ -f "$w/home/.local/share/applications/notes.desktop" ] || fail "files"
[ "$(word notes)" = installed ] || fail "after: $(word notes)"
ok "install: the script runs for the user with its folders; the library says installed"

# A newer version: update ready; installing it removes what only the old one had.
version notes 3000 'set -e
mkdir -p "$HATCHLYBOX_BIN" "$HATCHLYBOX_SHARE/notes"
echo "#!/bin/sh" > "$HATCHLYBOX_BIN/notes"; echo v2 > "$HATCHLYBOX_SHARE/notes/data"
printf "%s\n" "$HATCHLYBOX_BIN/notes" "$HATCHLYBOX_SHARE/notes" >> "$HATCHLYBOX_MANIFEST"'
[ "$(word notes)" = "update ready" ] || fail "update: $(word notes)"
h here install notes linux >/dev/null
[ "$(cat "$w/home/.local/share/notes/data")" = v2 ] && [ ! -e "$w/home/.local/share/applications/notes.desktop" ] && [ "$(word notes)" = installed ] || fail "after the update"
ok "an update installs over it and removes what the old version had and the new one doesn't"

h here open notes linux | grep -q opened && for _ in 1 2 3 4 5 6 7 8 9 10; do [ -f "$w/home/.local/share/opened" ] && break; sleep 0.3; done
[ -f "$w/home/.local/share/opened" ] || fail "open"
ok "open runs its hatchlybox.json command"

# Uninstall: uninstall.sh first, then the listed paths, but never outside the app folders (even if listed).
echo keep > "$w/home/.bashrc"; mkdir -p "$w/home/.config"; echo "bind = SUPER, N, exec, notes" > "$w/home/.config/keys.conf"
version notes 4000 'set -e
mkdir -p "$HATCHLYBOX_BIN"; echo "#!/bin/sh" > "$HATCHLYBOX_BIN/notes"
echo "bind = SUPER, M, exec, notes" >> "$HATCHLYBOX_CONFIG/keys.conf"
printf "%s\n" "$HATCHLYBOX_BIN/notes" "$HOME/.bashrc" "$HATCHLYBOX_BIN" "/etc/hostname" "$HATCHLYBOX_BIN/../../.bashrc" >> "$HATCHLYBOX_MANIFEST"'
printf '%s\n' 'sed -i "/SUPER, M, exec, notes/d" "$HATCHLYBOX_CONFIG/keys.conf"' > "$w/ports/notes/linux/export/uninstall.sh"
h here install notes linux >/dev/null
h here uninstall notes linux | grep -q uninstalled || fail "uninstall"
[ ! -e "$w/home/.local/bin/notes" ] && [ -d "$w/home/.local/bin" ] && [ "$(cat "$w/home/.bashrc")" = keep ] || fail "removed the wrong things"
[ "$(cat "$w/home/.config/keys.conf")" = "bind = SUPER, N, exec, notes" ] || fail "uninstall.sh didn't undo its line: $(cat "$w/home/.config/keys.conf")"
grep -q "left alone (outside your app folders): $w/home/.bashrc" "$w/cache/here.log" || fail "not logged"
[ "$(word notes)" = "ready to install" ] || fail "after uninstall: $(word notes)"
ok "uninstall: its uninstall.sh, then its files; ~/.bashrc, /etc and the folders themselves left alone"

# Refused: sudo, a failing script (and what it made is undone), another system, no install script.
version admin 2000 'sudo cp app /usr/bin/app'
out=$(h here install admin linux 2>&1 || true); grep -q "administrator rights" <<< "$out" || fail "sudo: $out"
version broken 2000 'mkdir -p "$HATCHLYBOX_BIN"; echo x > "$HATCHLYBOX_BIN/broken"; echo "$HATCHLYBOX_BIN/broken" >> "$HATCHLYBOX_MANIFEST"; exit 3'
out=$(h here install broken linux 2>&1 || true); grep -q "failed (code 3)" <<< "$out" && [ ! -e "$w/home/.local/bin/broken" ] || fail "a failed install: $out"
mkdir -p "$w/ports/mac-app/macos/export"; echo '{"changed": 1, "content": 1}' > "$w/ports/mac-app/macos/.port.json"; echo true > "$w/ports/mac-app/macos/export/install.sh"
out=$(h here install mac-app macos 2>&1 || true); grep -q "macOS versions don't install on" <<< "$out" || fail "another system: $out"
rm "$w/ports/notes/linux/export/install.sh"
out=$(h here install notes linux 2>&1 || true); grep -q "no install.sh" <<< "$out" || fail "no script: $out"
[ "$(word notes)" = "ready to export" ] || fail "without a script: $(word notes)"
ok "refused: sudo, another system's version, no install script; a failed install leaves nothing behind"

# Omarchy versions install where Omarchy is.
mkdir -p "$w/home/.config/omarchy"
[ "$(h platform | jq -r '.installs | join(" ")')" = "linux omarchy" ] || fail "omarchy: $(h platform)"
ok "a Linux computer with Omarchy installs Omarchy versions too"

# Removing a version: uninstalled first, kept in the trash; the Android version isn't removed this way.
version gone 5000 'set -e
mkdir -p "$HATCHLYBOX_BIN"; echo x > "$HATCHLYBOX_BIN/gone"; echo "$HATCHLYBOX_BIN/gone" >> "$HATCHLYBOX_MANIFEST"'
h here install gone linux >/dev/null && [ -f "$w/home/.local/bin/gone" ] || fail "install before remove"
h remove gone linux | grep -q "removed the Linux version" || fail "remove"
[ ! -e "$w/ports/gone" ] && [ ! -e "$w/home/.local/bin/gone" ] && ls -d "$w/data/trash/gone"/linux-* >/dev/null || fail "remove: $(ls -R "$w/data/trash" 2>&1 | head)"
rc=0; h remove gone android >/dev/null 2>&1 || rc=$?; [ $rc != 0 ] || fail "remove android"
# The install check an agent's version gets before the job ends.
mkdir -p "$w/chk"; printf 'sudo cp x /usr/bin\n' > "$w/chk/install.sh"
p=$(env HATCHLYBOX_HOME="$w/data" HATCHLYBOX_CACHE="$w/cache" HATCHLYBOX_TEST=1 bash -c 'source "$0"; install_problems "$1"' "$repo/bin/hatchlybox" "$w/chk")
grep -q "administrator rights" <<< "$p" || fail "install check: $p"
ok "remove: a version uninstalled and kept in the trash; install scripts checked for the contract"
