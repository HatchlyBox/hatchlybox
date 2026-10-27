#!/usr/bin/env bash
# Checks every code block in the knowledge base with the real engine: each ```gdscript block must parse
# (--check-only) and run for a few frames in a render, and each ```gdshader block must compile on a
# rectangle (canvas_item) or a mesh (spatial). Run it after editing kb/:
#   ./kb-check.sh [entry-name...]
set -uo pipefail
cd "$(dirname "$0")"
source ../bin/paths.sh
w=$CACHE/kbcheck
rm -rf "$w"; mkdir -p "$w/godot/kb"
cat > "$w/godot/project.godot" <<'EOF'
config_version=5

[application]
config/name="kbcheck"
run/main_scene="res://main.tscn"

[display]
window/size/viewport_width=720
window/size/viewport_height=1280

[rendering]
renderer/rendering_method="gl_compatibility"
renderer/rendering_method.mobile="gl_compatibility"
EOF
python3 -I - "$w/godot/kb" "$@" <<'EOF'
import os, re, sys, glob
out, only = sys.argv[1], set(sys.argv[2:])
for f in sorted(glob.glob("kb/*/*.md")):
    name = os.path.basename(f)[:-3].replace("-", "_")
    if only and os.path.basename(f)[:-3] not in only: continue
    for i, m in enumerate(re.finditer(r"```(gdscript|gdshader)\n(.*?)```", open(f).read(), re.S)):
        ext = "gd" if m.group(1) == "gdscript" else "gdshader"
        open(f"{out}/{name}_{i}.{ext}", "w").write(m.group(2))
        # A block that names its file ("// res://x.gdshader" or "# res://x.gd" first) is also saved there.
        first = m.group(2).split("\n", 1)[0]
        named = re.match(r"(?://|#) (res://[\w/.-]+)$", first)
        if named: open(os.path.join(os.path.dirname(out), named.group(1)[6:]), "w").write(m.group(2))
EOF
# A scene that runs every script (nodes of the right base type) and shows every shader.
cat > "$w/godot/main.gd" <<'EOF'
extends Node2D
func _ready() -> void:
	var y := 0.0
	for f in DirAccess.get_files_at("res://kb"):
		var path := "res://kb/" + f
		if f.ends_with(".gdshader"):
			var sh: Shader = load(path)
			var mat := ShaderMaterial.new()
			mat.shader = sh
			if sh.get_mode() == Shader.MODE_SPATIAL:
				var vp := SubViewport.new()
				vp.size = Vector2i(64, 64)
				add_child(vp)
				var cam := Camera3D.new()
				cam.position = Vector3(0, 0, 3)
				vp.add_child(cam)
				var mi := MeshInstance3D.new()
				mi.mesh = BoxMesh.new()
				mi.material_override = mat
				vp.add_child(mi)
			else:
				var r := ColorRect.new()
				r.size = Vector2(64, 64)
				r.position = Vector2(0, y)
				r.material = mat
				add_child(r)
			y += 70.0
			print("shader ", f)
		elif f.ends_with(".gd"):
			var s: Script = load(path)
			if s == null:
				continue
			var base := s.get_instance_base_type()
			if ClassDB.can_instantiate(base) and ClassDB.is_parent_class(base, "Node"):
				var n: Node = s.new()
				add_child(n)
				print("script ", f, " (", base, ")")
EOF
printf '[gd_scene format=3]\n\n[ext_resource type="Script" path="res://main.gd" id="1"]\n\n[node name="Main" type="Node2D"]\nscript = ExtResource("1")\n' > "$w/godot/main.tscn"
cd "$w"
godot --headless --path godot --import > import.txt 2>&1
fail=0
for f in godot/kb/*.gd; do
  godot --headless --path godot --check-only -s "res://kb/${f##*/}" > out.txt 2>&1 || { echo "== $f"; grep -E 'SCRIPT ERROR|ERROR|at: ' out.txt | head -8; fail=1; }
done
visual render --at 1.5 > render.txt 2>&1
grep -E 'SHADER ERROR|SCRIPT ERROR|ERROR:|error\(' design/renders/*/log.txt 2>/dev/null | grep -vE 'leaked|still in use|RID allocations|XCursor|dbus|udev|joypad' | head -30 && fail=1
grep -cE '^(shader|script) ' design/renders/*/log.txt | sed 's/^/blocks run: /'
[ $fail = 0 ] && echo "kb-check: all code blocks parse, compile and run" || { echo "kb-check: failures above (work dir $w)"; exit 1; }
