#!/usr/bin/env bash
# Checks technique recipes by running their own code (a development tool; not shipped).
#   ./kb-check.sh kb/recipes/matcap-3d.md ...      Godot recipes: render them, fail on script/shader errors
#   ./kb-check.sh kb/recipes/compose-*.md          Compose recipes: compile them in the skill-check project
# Recipe code blocks that start with a "// res://file" or "# res://file" line are written to that file;
# a Godot recipe needs res://demo.gd (a scene built in code). Compose blocks are compiled as they are.
#   ./kb-check.sh                                  no recipes: kb-check-blocks.sh, the code blocks in kb/*/*.md
# Shots and logs go to $CACHE/kb-check/<recipe>.png / .log (bin/paths.sh).
set -uo pipefail
cd "$(dirname "$0")"
[ $# -gt 0 ] || exec ./kb-check-blocks.sh
source ../bin/paths.sh
out=$CACHE/kb-check
mkdir -p "$out"
fail=0
compose=()
for md in "$@"; do
  name=$(basename "$md" .md)
  if grep -q '^engine: compose' "$md"; then compose+=("$md"); continue; fi
  t=$(mktemp -d)
  mkdir -p "$t/app/godot"
  cat > "$t/app/godot/project.godot" <<'EOF'
config_version=5

[application]
config/name="kb check"
run/main_scene="res://demo.tscn"

[display]
window/size/viewport_width=720
window/size/viewport_height=1280
window/stretch/mode="canvas_items"
window/stretch/aspect="expand"

[rendering]
renderer/rendering_method="gl_compatibility"
renderer/rendering_method.mobile="gl_compatibility"
EOF
  python3 -I - "$md" "$t/app/godot" <<'PY'
import os, re, sys
md, root = sys.argv[1], sys.argv[2]
for block in re.findall(r"```\w*\n(.*?)```", open(md).read(), re.S):
    m = re.match(r"(?://|#) (res://\S+)\n", block)
    if m:
        p = os.path.join(root, m.group(1)[6:])
        os.makedirs(os.path.dirname(p), exist_ok=True)
        open(p, "w").write(block)
PY
  if [ ! -f "$t/app/godot/demo.gd" ]; then echo "FAIL $name: no res://demo.gd block"; fail=1; rm -rf "$t"; continue; fi
  base=$(sed -n 's/^extends \([A-Za-z0-9]*\).*/\1/p' "$t/app/godot/demo.gd" | head -1)
  printf '[gd_scene load_steps=2 format=3]\n\n[ext_resource type="Script" path="res://demo.gd" id="1"]\n\n[node name="Demo" type="%s"]\nscript = ExtResource("1")\n' "${base:-Node2D}" > "$t/app/godot/demo.tscn"
  (cd "$t/app" && timeout 300 visual render --at 2.5 > "$out/$name.log" 2>&1)
  shot=$(ls "$t"/app/design/renders/*/shot-1.png 2>/dev/null | tail -1)
  [ -n "$shot" ] && cp "$shot" "$out/$name.png"
  cat "$t"/app/design/renders/*/log.txt >> "$out/$name.log" 2>/dev/null
  errs=$(grep -E 'SCRIPT ERROR|SHADER ERROR|Parse Error|^ERROR' "$out/$name.log" | grep -vE 'leaked|still in use|RID allocations|ObjectDB|XCursor|dbus|udev|joypad|wayland|vsync' | head -3)
  if [ -z "$shot" ] || [ -n "$errs" ]; then echo "FAIL $name: ${errs:-no screenshot (see $out/$name.log)}"; fail=1
  else echo "ok   $name -> $out/$name.png"; fi
  rm -rf "$t"
done
if [ ${#compose[@]} -gt 0 ]; then
  w=$CACHE/skillcheck
  [ -f "$w/gradlew" ] || { echo "run ../skills-check.sh once first (it sets up $w)"; exit 1; }
  pkg=$w/app/src/main/java/kbcheck
  rm -rf "$pkg" && mkdir -p "$pkg"
  for md in "${compose[@]}"; do
    n=$(basename "$md" .md | tr -c 'a-zA-Z0-9\n' '_')
    python3 -I - "$md" "$pkg/$n.kt" "$n" <<'PY'
import re, sys
md, dst, n = sys.argv[1:4]
blocks = re.findall(r"```kotlin\n(.*?)```", open(md).read(), re.S)
imports = sorted({l for b in blocks for l in b.splitlines() if l.startswith("import ")})
body = "\n".join("\n".join(l for l in b.splitlines() if not l.startswith("import ")) for b in blocks)
open(dst, "w").write(f"@file:Suppress(\"unused\")\npackage kbcheck.{n}\n\n" + "\n".join(imports) + "\n\n" + body)
PY
  done
  if (cd "$w" && timeout 1200 ./gradlew -q compileReleaseKotlin > "$out/compose.log" 2>&1); then
    echo "ok   compose: ${#compose[@]} recipes compile"
  else
    echo "FAIL compose:"; grep -E '^e: ' "$out/compose.log" | head -20; fail=1
  fi
  rm -rf "$pkg"
fi
exit $fail
