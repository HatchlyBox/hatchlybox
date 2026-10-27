#!/usr/bin/env bash
# A Godot game on every system (gexport.sh, install_godot): each system's editor; the renderers per system (once, and
# never over the project's own); export presets made again without disturbing the Android one; the Linux export's
# install.sh by here.sh's contract, installed and removed; make <slug> linux on a Godot game is an export job, not
# the agent. HATCHLYBOX_TEST_BUILD=1 also exports a small game for the web and Linux with the real Godot (downloads
# the two templates once, about 80 MB).
set -euo pipefail
repo=$(cd "$(dirname "$0")/.." && pwd)
w=$(mktemp -d)
trap 'rm -rf "$w" 2>/dev/null || true' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }
ok() { echo "PASS: $*"; }

mkdir -p "$w/data" "$w/cache" "$w/apps" "$w/ports" "$w/home"
ln -s "$repo/bin" "$w/data/bin"; cp "$repo/platforms/linux/platform.env" "$w/data/"
# A real install (its Godot and SDK) for the optional real builds: HATCHLYBOX_TEST_INSTALL, else the usual place.
inst=${HATCHLYBOX_TEST_INSTALL:-$HOME/.local/share/hatchlybox}
in_engine() { HATCHLYBOX_HOME=$w/data HATCHLYBOX_CACHE=$w/cache HATCHLYBOX_APPS=$w/apps HATCHLYBOX_PORTS=$w/ports HATCHLYBOX_TEST=1 \
  bash -c 'source "$0"; LOG=$HATCHLYBOX_CACHE/log.txt; eval "$1"' "$repo/bin/hatchlybox" "$1"; }

# Each system's editor.
as() { local d=$w/uname-$1-$2; mkdir -p "$d"; printf '#!/bin/sh\ncase "$1" in -s) echo %s ;; -m) echo %s ;; esac\n' "$1" "$2" > "$d/uname"; chmod +x "$d/uname"
       PATH="$d:$PATH" in_engine "$3"; }
[[ $(as Linux aarch64 godot_editor) == "Godot_v"*"_linux.arm64.zip 256 "* ]] || fail "ARM Linux editor"
[[ $(as Linux x86_64 godot_editor) == *"_linux.x86_64.zip 512 9aa00f7a"* ]] || fail "x86_64 Linux editor"
[[ $(as Darwin arm64 godot_editor) == *"_macos.universal.zip 512 38aa16e5"* ]] || fail "Mac editor"
[ -z "$(as Linux riscv64 godot_editor)" ] || fail "no editor for RISC-V"
ok "Godot's editor for ARM Linux, x86_64 Linux and macOS (pinned by the release's SHA-512 sums)"
# Godot's own folders: a Mac's in Application Support, Linux's (and the phones') XDG folders.
[ "$(as Darwin arm64 'echo "$GODOT_TEMPLATES|$GODOT_CONFIG"')" = "$HOME/Library/Application Support/Godot/export_templates/4.7.2.stable|$HOME/Library/Application Support/Godot" ] || fail "Mac's Godot folders"
[ "$(as Linux x86_64 'echo "$GODOT_TEMPLATES|$GODOT_CONFIG"' | sed "s|$HOME|~|g")" = "~/.local/share/godot/export_templates/4.7.2.stable|~/.config/godot" ] || fail "Linux's Godot folders"
ok "Godot's templates and settings where each system's Godot looks for them"

# Renderers: Forward+ for computers, the game's own for phones, Compatibility for the web; once only.
g=$w/apps/hex/godot; mkdir -p "$g"
printf '[application]\n\nconfig/name="Hex"\n\n[rendering]\n\nrenderer/rendering_method="gl_compatibility"\n' > "$g/project.godot"
in_engine "godot_renderers '$g'"
[ "$(grep '^renderer/' "$g/project.godot" | tr '\n' '|')" = 'renderer/rendering_method="forward_plus"|renderer/rendering_method.mobile="gl_compatibility"|renderer/rendering_method.web="gl_compatibility"|' ] || fail "renderers: $(cat "$g/project.godot")"
cp "$g/project.godot" "$w/once"; in_engine "godot_renderers '$g'"; cmp -s "$g/project.godot" "$w/once" || fail "applied twice"
printf '[application]\n\nconfig/name="Two"\n' > "$w/p2.godot"; mkdir -p "$w/p2"; mv "$w/p2.godot" "$w/p2/project.godot"
in_engine "godot_renderers '$w/p2'"; grep -q 'rendering_method.mobile="gl_compatibility"' "$w/p2/project.godot" && grep -q '^\[rendering\]' "$w/p2/project.godot" || fail "no rendering section"
printf '[rendering]\n\nrenderer/rendering_method="forward_plus"\nrenderer/rendering_method.mobile="mobile"\n' > "$w/p2/project.godot"; cp "$w/p2/project.godot" "$w/own"
in_engine "godot_renderers '$w/p2'"; cmp -s "$w/p2/project.godot" "$w/own" || fail "changed a project's own renderers"
ok "renderers: Forward+ on computers, the game's own on phones, Compatibility on the web; once, never over the project's own"

# Presets: made again each time, numbered in order, the Android one untouched.
printf '[preset.0]\n\nname="Android"\nplatform="Android"\nexport_path="a.apk"\n\n[preset.0.options]\n\npackage/unique_name="com.x.hex"\n' > "$g/export_presets.cfg"
in_engine "godot_preset_for '$g' linux /tmp/out/hex.x86_64 com.x.hex; godot_preset_for '$g' web /tmp/out/index.html com.x.hex; godot_preset_for '$g' linux /tmp/out2/hex.x86_64 com.x.hex"
[ "$(grep -c '^\[preset\.[0-9]*\]$' "$g/export_presets.cfg")" = 3 ] && grep -q 'export_path="/tmp/out2/hex.x86_64"' "$g/export_presets.cfg" && ! grep -q 'export_path="/tmp/out/hex.x86_64"' "$g/export_presets.cfg" || fail "presets: $(cat "$g/export_presets.cfg")"
[ "$(grep -o '^\[preset\.[0-9]*\]' "$g/export_presets.cfg" | tr -d '\n')" = '[preset.0][preset.1][preset.2]' ] && grep -q 'package/unique_name="com.x.hex"' "$g/export_presets.cfg" \
  && grep -q 'variant/thread_support=false' "$g/export_presets.cfg" && grep -q 'binary_format/embed_pck=true' "$g/export_presets.cfg" || fail "preset contents: $(cat "$g/export_presets.cfg")"
ok "export presets: one per system, made again cleanly, the Android preset kept"

# The Linux export's install.sh, by here.sh's contract: installed for the user, then removed.
echo '{"slug": "hex", "pkg": "com.x.hex", "label": "Hex", "status": "ready", "created": 1, "updated": 1, "history": [], "content": 700}' > "$w/apps/hex/.hatchlybox.json"
mkdir -p "$w/ports/hex/linux/export"; printf '#!/bin/sh\necho hex\n' > "$w/ports/hex/linux/export/hex.x86_64"
in_engine "godot_export_files hex linux '$w/ports/hex/linux/export'"
echo '{"label": "Hex", "created": 1, "changed": 2, "content": 700, "made": "godot-export"}' > "$w/ports/hex/linux/.port.json"
h() { env -u XDG_DATA_HOME -u XDG_CONFIG_HOME HOME="$w/home" HATCHLYBOX_HOME="$w/data" HATCHLYBOX_CACHE="$w/cache" HATCHLYBOX_APPS="$w/apps" HATCHLYBOX_PORTS="$w/ports" "$repo/bin/hatchlybox" "$@"; }
h here install hex linux >/dev/null || fail "install: $(tail -5 "$w/cache/here.log")"
[ -x "$w/home/.local/share/hatchlybox-games/hex/hex" ] && [ -L "$w/home/.local/bin/hex" ] && grep -q '^Name=Hex$' "$w/home/.local/share/applications/hatchlybox-hex.desktop" || fail "installed files"
[ "$("$w/home/.local/bin/hex")" = hex ] || fail "it doesn't run"
h here uninstall hex linux >/dev/null && [ ! -e "$w/home/.local/share/hatchlybox-games/hex" ] && [ ! -e "$w/home/.local/bin/hex" ] || fail "uninstall"
ok "the Linux export installs with one tap (launcher, icon, command) and uninstalls cleanly"

# make on a Godot game: an export job (no agent); with a request, still the agent's.
mkdir -p "$w/apps/hex/godot"; touch "$w/apps/hex/godot/project.godot"
r=$(in_engine 'can_start() { :; }; start() { echo "START $1 $2 [$3] $4"; }; make_cmd hex linux claude')
[ "$r" = "START gexport hex [] linux" ] || fail "make linux: $r"
r=$(in_engine 'can_start() { :; }; start() { echo "START $1 $2 [$3] $4"; }; make_cmd hex linux claude add a pause menu' 2>&1 | grep START)
[ "$r" = "START port hex [claude] linux" ] || fail "make linux with a request: $r"
ok "make <game> linux|web|macos|windows exports it with Godot; a change request goes to the agent"

if [ "${HATCHLYBOX_TEST_BUILD:-}" = 1 ]; then
  ln -s "$inst/godot" "$w/data/godot"; cp "$inst/sdk.path" "$w/data/" 2>/dev/null || true
  d=$w/apps/tiny; mkdir -p "$d/godot"
  echo '{"pkg": "com.hatchlybox.tiny", "label": "Tiny", "content": 10}' > "$d/.hatchlybox.json"
  printf '[application]\n\nconfig/name="Tiny"\nrun/main_scene="res://main.tscn"\n\n[rendering]\n\nrenderer/rendering_method="gl_compatibility"\n' > "$d/godot/project.godot"
  printf '[gd_scene format=3]\n\n[node name="Main" type="Node2D"]\n' > "$d/godot/main.tscn"
  git init -q "$d"; git -C "$d" -c user.name=t -c user.email=t@t commit -qm init --allow-empty
  for s in web linux; do
    in_engine "JOB=\$HATCHLYBOX_CACHE/job.json; echo '{}' > \$JOB; godot_export_work tiny $s" > "$w/out-$s" 2>&1 || fail "$s export: $(tail -20 "$w/cache/log.txt")"
  done
  [ -f "$w/ports/tiny/web/export/index.html" ] && ls "$w/ports/tiny/web/export" | grep -q '\.wasm$' || fail "web export: $(ls "$w/ports/tiny/web/export")"
  f=$(ls "$w/ports/tiny/linux/export" | grep -E '\.(x86_64|arm64)$')
  [ -n "$f" ] && [ "$(stat -c %s "$w/ports/tiny/linux/export/$f")" -gt 1000000 ] && [ -f "$w/ports/tiny/linux/export/install.sh" ] || fail "linux export: $(ls -la "$w/ports/tiny/linux/export")"
  [ "$(jq -r '[.made, .content] | join(" ")' "$w/ports/tiny/linux/.port.json")" = "godot-export 10" ] || fail ".port.json"
  ok "the real Godot exports a game for the web ($(du -sk "$w/ports/tiny/web/export" | cut -f1) KB) and Linux ($f, $(( $(stat -c %s "$w/ports/tiny/linux/export/$f") / 1048576 )) MB)"
fi
