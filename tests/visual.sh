#!/usr/bin/env bash
# Visual Intelligence on computers (adapter 8): visual device describes the computer and both budgets (the phone's
# for Android and web versions, integrated graphics for computer versions); setup names the packages to install
# when that needs an administrator; render judges each version with its renderer: Compatibility for Android and
# the web, Forward+ for computers (software Vulkan in Xvfb on Linux, Metal in a small window on a Mac, Compatibility
# with a note where there's no Vulkan); phones are unchanged. Godot and Xvfb are fakes: this checks what is asked.
set -euo pipefail
repo=$(cd "$(dirname "$0")/.." && pwd)
w=$(mktemp -d)
trap 'rm -rf "$w" 2>/dev/null || true' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }
ok() { echo "PASS: $*"; }

mkdir -p "$w/data/visual" "$w/cache" "$w/fake" "$w/game/godot"
ln -s "$repo/bin" "$w/data/bin"; ln -s "$repo/visual/bin" "$w/data/visual/bin"; ln -s "$repo/visual/kb" "$w/data/visual/kb"
printf '[application]\nrun/main_scene="res://main.tscn"\n[display]\nwindow/size/viewport_width=1920\nwindow/size/viewport_height=1080\n' > "$w/game/godot/project.godot"
# A fake Godot: records its arguments, saves one screenshot and the stats where capture.gd would.
cat > "$w/fake/godot" <<'G'
#!/bin/bash
printf '%s\n' "$@" > "$GODOT_LOG"
while [ "$1" != -- ]; do shift; done; out=$2
python3 -I -c 'import struct, zlib, sys
w = h = 8; raw = b"".join(b"\x00" + bytes([200, 80, 40]) * w for _ in range(h))
c = lambda t, d: struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xffffffff)
open(sys.argv[1], "wb").write(b"\x89PNG\r\n\x1a\n" + c(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0)) + c(b"IDAT", zlib.compress(raw)) + c(b"IEND", b""))' "$out/shot-1.png"
echo '{"shots": [{"t": 1, "draw_calls": 10, "objects": 5, "nodes": 3, "video_mem_mb": 20, "static_mem_mb": 30}]}' > "$out/stats.json"
G
printf '#!/bin/sh\nexec sleep 60\n' > "$w/fake/Xvfb"; chmod +x "$w/fake/godot" "$w/fake/Xvfb"
v() { (cd "$w/game" && env PATH="$w/fake:$PATH" HATCHLYBOX_HOME="$w/data" HATCHLYBOX_CACHE="$w/cache" GODOT_LOG="$w/godot.log" "$@"); }
plat() { cp "$repo/platforms/$1/platform.env" "$w/data/"; }

plat linux
d=$(v "$repo/visual/bin/visual" device)
grep -q "^computer: " <<< "$d" && grep -q "Forward+" <<< "$d" && grep -q "mid-range phone" <<< "$d" && grep -q "≤ 1500 draw calls" <<< "$d" || fail "computer device: $d"
plat hatchlybox
grep -q "^phone: " <<< "$(v "$repo/visual/bin/visual" device)" || fail "phone device"
ok "device: a computer lists itself, the phone's budgets and the computers'; a phone is as before"

plat linux
# A PATH without Xvfb (this phone has one), with pacman to name.
mkdir -p "$w/bare"; for t in bash env cat sed awk jq grep uname id dirname readlink head; do ln -sf "$(type -P "$t")" "$w/bare/$t"; done
# An Arch system wherever the test runs: a pacman that does nothing.
printf '#!/bin/sh\n' > "$w/bare/pacman"; chmod +x "$w/bare/pacman"
rc=0; out=$(v env PATH="$w/bare" HATCHLYBOX_TEST_UID=1000 bash "$repo/visual/bin/visual" setup 2>&1) || rc=$?
[ $rc = 1 ] && grep -q "^  sudo pacman -S --needed --noconfirm xorg-server-xvfb mesa vulkan-swrast" <<< "$out" || fail "setup without root: $rc $out"
ok "setup on a computer: names the packages for an administrator instead of installing"

r=$(v env VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/lvp_icd.x86_64.json "$repo/visual/bin/visual" render --for linux --at 1)
a=$(cat "$w/godot.log")
grep -qx forward_plus <<< "$a" && grep -qx vulkan <<< "$a" && grep -qx x11 <<< "$a" && grep -qx 1280x720 <<< "$a" || fail "linux forward+: $a"
grep -q "forward_plus for linux" <<< "$r" || fail "render says what it judged: $r"
r=$(v env VK_ICD_FILENAMES= "$repo/visual/bin/visual" render --for windows --at 1)
grep -q "no software Vulkan" <<< "$r" && grep -qx gl_compatibility <<< "$(cat "$w/godot.log")" || fail "no vulkan: $r"
v "$repo/visual/bin/visual" render --at 1 >/dev/null
grep -qx gl_compatibility <<< "$(cat "$w/godot.log")" && grep -qx opengl3 <<< "$(cat "$w/godot.log")" || fail "android default"
ok "render on Linux: Forward+ with software Vulkan for computers, Compatibility for Android, a note without Vulkan"

plat macos
v env HATCHLYBOX_TEST_OS=Darwin "$repo/visual/bin/visual" render --for macos --at 1 >/dev/null
a=$(cat "$w/godot.log")
grep -qx metal <<< "$a" && grep -qx -- --position <<< "$a" && ! grep -qx x11 <<< "$a" || fail "mac: $a"
ok "render on a Mac: its own GPU (Metal) in a small window, no Xvfb"

plat hatchlybox
r=$(v "$repo/visual/bin/visual" render --for linux --at 1 2>&1) || true
grep -q "no software Vulkan" <<< "$r" && grep -qx gl_compatibility <<< "$(cat "$w/godot.log")" || fail "phone --for linux: $r"
ok "a phone judges computer versions with its own renderer, and says so"
