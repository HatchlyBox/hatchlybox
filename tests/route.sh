#!/usr/bin/env bash
# What an idea becomes (route.sh): web by default, Android when it needs the phone, a Godot game for a real game,
# a named system as named; create auto makes it so (a game: an Android project with the Godot instruction).
set -euo pipefail
repo=$(cd "$(dirname "$0")/.." && pwd)
w=$(mktemp -d)
trap 'rm -rf "$w" 2>/dev/null || true' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }
ok() { echo "PASS: $*"; }
mkdir -p "$w/data"; ln -s "$repo/bin" "$w/data/bin"
in_engine() { HATCHLYBOX_HOME=$w/data HATCHLYBOX_CACHE=$w/cache HATCHLYBOX_APPS=$w/apps HATCHLYBOX_PORTS=$w/ports HATCHLYBOX_TEST=1 bash -c 'source "$0"; eval "$1"' "$repo/bin/hatchlybox" "$1"; }

n=0
while IFS='|' read -r want idea; do
  [ -n "$want" ] || continue
  got=$(in_engine "route_idea '$idea'"); got=${got%% *}
  [ "$got" = "$want" ] || fail "\"$idea\": $got, not $want"
  n=$((n + 1))
done <<'EOF'
web|a habit tracker
web|a recipe app with steps
web|a QR code generator
web|a tool to change the background color of images
web|a tic tac toe game
web|a website for my bakery
web|a budget app for my phone
android|a widget that shows my next meeting
android|remind me to drink water every hour
android|um aplicativo de lembretes
android|scan receipts and total them
android|a step counter
android|an alarm clock that makes me solve a puzzle
game|a 3D racing game with levels
game|a platformer game
game|un juego de estrategia con mapas hexagonales
omarchy|a waybar module that shows CPU
windows|a Windows app to rename files
macos|a menu app for my mac
linux|a GTK app for my linux laptop
EOF
ok "$n ideas, each to web, Android, a Godot game or the system it names"

# On a computer, a program for the computer itself (a plain Linux one: not the desktop's XDG_CONFIG_HOME, where Omarchy may be).
mkdir -p "$w/data2"; ln -s "$repo/bin" "$w/data2/bin"; cp "$repo/platforms/linux/platform.env" "$w/data2/"
mkdir -p "$w/home"; r=$(env -u XDG_CONFIG_HOME HOME=$w/home HATCHLYBOX_HOME=$w/data2 HATCHLYBOX_CACHE=$w/cache HATCHLYBOX_APPS=$w/apps HATCHLYBOX_PORTS=$w/ports HATCHLYBOX_TEST=1 bash -c 'source "$0"; route_idea "a tray icon that shows the weather"' "$repo/bin/hatchlybox")
[ "${r%% *}" = linux ] || fail "computer program: $r"
ok "on a computer, a tray icon or a command-line tool is for that computer"

# create auto: the format chosen (stubbed jobs: what would start).
r=$(in_engine 'can_start() { :; }; list_apps() { :; }; start() { echo "START $1 $2 $4"; }; scaffold() { mkdir -p "$APPS/$1"; }; create_cmd auto claude a habit tracker')
[[ $r == "START port habit-tracker web" ]] || fail "auto web: $r"
r=$(in_engine 'can_start() { :; }; list_apps() { :; }; new_prompt() { echo "$1"; }; start() { echo "START $1 $2 | $4"; }; scaffold() { mkdir -p "$APPS/$1"; }; create_cmd auto claude a 3D racing game with levels')
[[ $r == "START app "*"| A real game, made with Godot (read the godot skill): a 3D racing game with levels" ]] || fail "auto game: $r"
[ "$(in_engine 'route_cmd a widget for the weather' | jq -r .system)" = android ] || fail "hatchlybox route"
ok "create auto starts the chosen kind; a real game as an Android project told to use Godot"
