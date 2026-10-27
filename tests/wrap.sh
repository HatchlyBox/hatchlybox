#!/usr/bin/env bash
# A web version as an Android app (wrap.sh): the wrapper project from the web export (its files, label, icon), the
# Android version marked wrapped and up to date with the web version, a change to the app sent to its web
# version, make android wrapping again, and native: the same project and package, made a Kotlin app from the web
# version. HATCHLYBOX_TEST_BUILD=1 also builds the wrapper with Gradle (minutes) and checks the APK.
set -euo pipefail
repo=$(cd "$(dirname "$0")/.." && pwd)
w=$(mktemp -d)
trap 'rm -rf "$w" 2>/dev/null || true' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }
ok() { echo "PASS: $*"; }

mkdir -p "$w/data" "$w/cache" "$w/apps" "$w/ports"
ln -s "$repo/bin" "$w/data/bin"; cp -r "$repo/template" "$w/data/template"; cp "$repo/creation/AGENTS.md" "$w/data/"
# A real install (its Godot and SDK) for the optional real builds: HATCHLYBOX_TEST_INSTALL, else the usual place.
inst=${HATCHLYBOX_TEST_INSTALL:-$HOME/.local/share/hatchlybox}
if [ "${HATCHLYBOX_TEST_BUILD:-}" = 1 ]; then
  cp "$inst/template/local.properties" "$inst/template/gradle.properties" "$w/data/template/"
  cp "$inst/template/gradle/wrapper/gradle-wrapper.jar" "$w/data/template/gradle/wrapper/" 2>/dev/null || true
  cp "$inst/sdk.path" "$w/data/"
fi
in_engine() { HATCHLYBOX_HOME=$w/data HATCHLYBOX_CACHE=$w/cache HATCHLYBOX_APPS=$w/apps HATCHLYBOX_PORTS=$w/ports HATCHLYBOX_TEST=1 \
  bash -c 'source "$0"; LOG=$HATCHLYBOX_CACHE/log.txt; eval "$1"' "$repo/bin/hatchlybox" "$1"; }

# A finished web version: index.html, a module script, an icon named by its manifest.
d=$w/ports/tip-jar/web; mkdir -p "$d/export/js" "$d/export/img"
echo '{"label": "Tip Jar", "created": 100, "changed": 500, "content": 500}' > "$d/.port.json"
printf '<!doctype html><title>Tip Jar</title><script type="module" src="js/app.js"></script><p id="o">tips</p>\n' > "$d/export/index.html"
echo 'document.getElementById("o").textContent = localStorage.getItem("t") || "0";' > "$d/export/js/app.js"
python3 -I -c 'import zlib,struct,sys
def c(t,d): return struct.pack(">I",len(d))+t+d+struct.pack(">I",zlib.crc32(t+d)&0xffffffff)
open(sys.argv[1],"wb").write(b"\x89PNG\r\n\x1a\n"+c(b"IHDR",struct.pack(">IIBBBBB",2,2,8,2,0,0,0))+c(b"IDAT",zlib.compress(b"\x00"+b"\xff\x00\x00"*2+b"\x00"+b"\x00\xff\x00"*2))+c(b"IEND",b""))' "$d/export/img/logo.png"
echo '{"icons": [{"src": "img/logo.png", "sizes": "512x512"}]}' > "$d/export/manifest.json"

out=$(in_engine 'wrap_project tip-jar' 2>&1) || fail "wrap_project: $out"
p=$w/apps/tip-jar; pkg=$(jq -r .pkg "$p/.hatchlybox.json")
[ -f "$p/app/src/main/assets/web/index.html" ] && [ -f "$p/app/src/main/assets/web/js/app.js" ] || fail "web files"
grep -q "class MainActivity : Activity()" "$p/app/src/main/java/${pkg//.//}/MainActivity.kt" && grep -q "package $pkg" "$p/app/src/main/java/${pkg//.//}/MainActivity.kt" || fail "activity"
! grep -q compose "$p/app/build.gradle.kts" && grep -q "applicationId = \"$pkg\"" "$p/app/build.gradle.kts" || fail "gradle file"
grep -q '>Tip Jar<' "$p/app/src/main/res/values/strings.xml" || fail "label"
cmp -s "$d/export/img/logo.png" "$p/app/src/main/res/drawable-nodpi/ic_web.png" && grep -q ic_launcher_fg "$p/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml" || fail "icon from the manifest"
[ ! -e "$p/webshell" ] || fail "the wrapper's own files copied into the project"
[ "$(jq -c '[.wrapped.from, .wrapped.content, .content]' "$p/.hatchlybox.json")" = '["web",500,500]' ] || fail "metadata: $(cat "$p/.hatchlybox.json")"
[ -z "$(git -C "$p" status --porcelain)" ] || fail "not committed"
ok "the wrapper: the web files, the label, its icon, marked wrapped and up to date with the web version"

# Up to date, then not: the web version changed. Wrapping again refreshes the files only.
in_engine 'list_apps' >/dev/null 2>&1
j=$(in_engine 'cat "$CACHE/creations.json"')
[ "$(jq -r '.[] | select(.slug == "tip-jar") | [.systems.android.wrapped, (.systems.android.older // "none")] | join(" ")' <<< "$j")" = "true none" ] || fail "creations: $j"
echo '{"label": "Tip Jar", "created": 100, "changed": 900, "content": 900}' > "$d/.port.json"; echo 'console.log(2)' > "$d/export/js/app.js"
in_engine 'wrap_project tip-jar' >/dev/null 2>&1
grep -q 'console.log(2)' "$p/app/src/main/assets/web/js/app.js" && [ "$(jq -r .content "$p/.hatchlybox.json")" = 900 ] && [ "$(jq -r .pkg "$p/.hatchlybox.json")" = "$pkg" ] || fail "refresh"
ok "wrapping again takes the new web version and keeps the package"

# A full Android version isn't wrapped over; without a web version there's nothing to wrap.
mkdir -p "$w/apps/native-one"; echo '{"pkg": "com.x.y"}' > "$w/apps/native-one/.hatchlybox.json"; mkdir -p "$w/ports/native-one/web/export"; echo x > "$w/ports/native-one/web/export/index.html"
out=$(in_engine 'wrap_project native-one' 2>&1 || true); grep -q "already has a full Android version" <<< "$out" || fail "over a native app: $out"
out=$(in_engine 'wrap_project nothing-here' 2>&1 || true); grep -q "no finished web version" <<< "$out" || fail "nothing to wrap: $out"
ok "it never replaces a full Android version, and needs a finished web version"

if [ "${HATCHLYBOX_TEST_BUILD:-}" = 1 ]; then
  in_engine 'do_build tip-jar' > "$w/build.out" 2>&1 || fail "gradle build: $(tail -30 "$w/cache/log.txt")"
  apk=$w/cache/apks/tip-jar.apk
  b=$(in_engine "\"\$(bt aapt2)\" dump badging '$apk'")
  grep -q "package: name='$pkg'" <<< "$b" && grep -q "application-label:'Tip Jar'" <<< "$b" || fail "apk: $b"
  unzip -l "$apk" | grep -q 'assets/web/js/app.js' || fail "web files not in the APK"
  ok "Gradle builds it: $(du -k "$apk" | cut -f1) KB, package $pkg, the web files inside"
fi

# native: the same folder and package, the usual Kotlin template, no longer wrapped (the agent's job isn't started here).
in_engine 'can_start() { :; }; start() { echo "START $1 $2 $3"; }; native_cmd tip-jar claude' > "$w/native.out" 2>&1 || fail "native: $(cat "$w/native.out")"
grep -q "START app tip-jar claude" "$w/native.out" || fail "no agent job: $(cat "$w/native.out")"
[ "$(jq -r .pkg "$p/.hatchlybox.json")" = "$pkg" ] && [ "$(jq -r '.wrapped // "gone"' "$p/.hatchlybox.json")" = gone ] || fail "metadata after native"
grep -q compose "$p/app/build.gradle.kts" && [ ! -d "$p/app/src/main/assets/web" ] && grep -q "applicationId = \"$pkg\"" "$p/app/build.gradle.kts" || fail "native project"
ok "native: the same project and package become the Kotlin app, made from the web version"
