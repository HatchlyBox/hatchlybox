#!/usr/bin/env bash
# Hatchlybox on Windows (in WSL): a Windows version installs on the Windows side (%LOCALAPPDATA%\Programs\Hatchlybox and
# a Start menu shortcut made through PowerShell), opens, and uninstalls without leaving anything; the Godot export's
# install.sh follows that contract; Windows programs route to this computer; agents need a sandbox by default.
# powershell.exe and wslpath are fakes (this isn't Windows): this checks what is asked of them.
set -euo pipefail
repo=$(cd "$(dirname "$0")/.." && pwd)
w=$(mktemp -d)
trap 'rm -rf "$w" 2>/dev/null || true' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }
ok() { echo "PASS: $*"; }

mkdir -p "$w/data" "$w/cache" "$w/apps/dash" "$w/ports/dash/windows/export" "$w/home" "$w/win/local" "$w/win/roam" "$w/fake"
ln -s "$repo/bin" "$w/data/bin"; cp "$repo/platforms/windows/platform.env" "$w/data/"
# wslpath -w: Windows paths look like these in the fake; powershell.exe makes the shortcut file it was asked for.
printf '#!/bin/sh\n[ "$1" = -w ] && shift; echo "$1"\n' > "$w/fake/wslpath"
cat > "$w/fake/powershell.exe" <<'P'
#!/bin/bash
echo "$*" >> "$PS_LOG"
l=$(python3 -I -c 'import re, sys; m = re.search(r"CreateShortcut\(\x27((?:[^\x27]|\x27\x27)*)\x27\)", sys.argv[1]); print(m.group(1).replace("\x27\x27", "\x27") if m else "")' "$*")
[ -z "$l" ] || touch "$l"
P
chmod +x "$w/fake/"*
h() { env -u XDG_DATA_HOME -u XDG_CONFIG_HOME PATH="$w/fake:$PATH" PS_LOG="$w/ps.log" HOME="$w/home" HATCHLYBOX_HOME="$w/data" HATCHLYBOX_CACHE="$w/cache" \
  HATCHLYBOX_APPS="$w/apps" HATCHLYBOX_PORTS="$w/ports" HATCHLYBOX_WIN_LOCALAPPDATA="$w/win/local" HATCHLYBOX_WIN_APPDATA="$w/win/roam" "$repo/bin/hatchlybox" "$@"; }
in_engine() { env PATH="$w/fake:$PATH" HATCHLYBOX_HOME=$w/data HATCHLYBOX_CACHE=$w/cache HATCHLYBOX_APPS=$w/apps HATCHLYBOX_PORTS=$w/ports HATCHLYBOX_TEST=1 \
  bash -c 'source "$0"; LOG=$HATCHLYBOX_CACHE/log.txt; eval "$1"' "$repo/bin/hatchlybox" "$1"; }

# A Godot game's Windows export, with the install.sh gexport.sh writes.
echo '{"slug": "dash", "pkg": "com.x.dash", "label": "Dash O'"'"'Clock", "status": "ready", "created": 1, "updated": 1, "history": [], "content": 700}' > "$w/apps/dash/.hatchlybox.json"
printf '#!/bin/sh\ntouch "%s/ran"\n' "$w" > "$w/ports/dash/windows/export/Dash OClock.exe"; chmod +x "$w/ports/dash/windows/export/Dash OClock.exe"
in_engine "godot_export_files dash windows '$w/ports/dash/windows/export'"
echo '{"label": "Dash O'"'"'Clock", "created": 1, "changed": 2, "content": 700, "made": "godot-export"}' > "$w/ports/dash/windows/.port.json"
word() { h creations | jq -r '.[] | select(.slug == "dash") | .systems.windows.word'; }
[ "$(word)" = "ready to install" ] || fail "before: $(word)"
h here install dash windows >/dev/null || fail "install: $(tail -5 "$w/cache/here.log")"
apps="$w/win/local/Programs/Hatchlybox" menu="$w/win/roam/Microsoft/Windows/Start Menu/Programs/Hatchlybox"
[ -x "$apps/dash/Dash OClock.exe" ] && [ -f "$menu/Dash O'Clock.lnk" ] || fail "installed files: $(find "$w/win")"
grep -q "CreateShortcut('$menu/Dash O''Clock.lnk')" "$w/ps.log" && grep -q "TargetPath = '$apps/dash/Dash OClock.exe'" "$w/ps.log" || fail "shortcut: $(cat "$w/ps.log")"
[ "$(word)" = installed ] || fail "after: $(word)"
ok "a Windows version installs on the Windows side: its folder and a Start menu shortcut (quotes intact)"
h here open dash windows >/dev/null; sleep 1; [ -f "$w/ran" ] || fail "open"
h here uninstall dash windows >/dev/null
[ ! -e "$apps/dash" ] && [ ! -e "$menu/Dash O'Clock.lnk" ] && [ -d "$apps" ] || fail "uninstall: $(find "$w/win")"
ok "it opens, and uninstalling removes its folder and shortcut (and nothing else)"

[ "$(h route a system tray app that shows the CPU | jq -r .system)" = windows ] || fail "route"
[ "$(h route a todo list | jq -r .system)" = web ] || fail "route default"
grep -qx 'ISOLATION=required' "$w/data/platform.env" && grep -qx 'INSTALLS="windows"' "$w/data/platform.env" || fail "platform"
ok "Windows programs route here; web stays the default; a sandbox is required"
