#!/usr/bin/env bash
set -euo pipefail
repo=$(cd "$(dirname "$0")/.." && pwd)
w=$(mktemp -d)
trap 'rm -rf "$w"' EXIT
export HATCHLYBOX_HOME=$repo HATCHLYBOX_CACHE=$w/cache HATCHLYBOX_APPS=$w/apps HATCHLYBOX_TEST=1
set +e
source "$repo/bin/hatchlybox"
set -e
DATA=$w/data
mkdir -p "$DATA" "$APPS"
ln -s "$repo/template" "$DATA/template"
ln -s "$repo/starter" "$DATA/starter"
ln -s "$repo/bin" "$DATA/bin"
ln -s "$repo/creation/AGENTS.md" "$DATA/AGENTS.md"
list_apps() { :; }
builds=0
do_build() {
  builds=$((builds+1))
  test "${force_fail:-0}" = 0 || return 1
  test -f "$APPS/$1/.git/HEAD"
  test -f "$APPS/$1/app/src/main/java/com/hatchlybox/hello_world/MainActivity.kt"
  meta "$1" '.outcomes.build="succeeded" | .outcomes.install="unverified"'
}
starter_app
test "$builds" = 1
test ! -L "$APPS/hello-world"
grep -q 'package __PKG__' "$repo/template/app/src/main/java/com/hatchlybox/template/MainActivity.kt"
jq -e '.starter and .status=="ready" and .outcomes.install=="unverified"' "$APPS/hello-world/.hatchlybox.json" >/dev/null
starter_app
test "$builds" = 1
rm -rf "$APPS/hello-world"
starter_app
test ! -d "$APPS/hello-world"
printf 'PASS: first install builds once; deletion survives setup\n'
rm "$DATA/.starter-v1"
mkdir "$APPS/existing"
starter_app
test ! -d "$APPS/hello-world"
test -f "$DATA/.starter-v1"
printf 'PASS: existing installations are untouched\n'
rm "$DATA/.starter-v1"
rmdir "$APPS/existing"
mkdir "$APPS/hello-world"
printf private > "$APPS/hello-world/keep"
starter_app
test "$(cat "$APPS/hello-world/keep")" = private
printf 'PASS: same-name projects are never overwritten\n'
rm "$DATA/.starter-v1"
rm -rf "$APPS/hello-world"
force_fail=1
if starter_app; then echo 'expected build failure' >&2; exit 1; fi
test ! -e "$DATA/.starter-v1"
jq -e '.status=="failed"' "$APPS/hello-world/.hatchlybox.json" >/dev/null
printf '\n// retained edit\n' >> "$APPS/hello-world/app/src/main/java/com/hatchlybox/hello_world/MainActivity.kt"
force_fail=0
starter_app
grep -q 'retained edit' "$APPS/hello-world/app/src/main/java/com/hatchlybox/hello_world/MainActivity.kt"
printf 'PASS: failed starter builds retry without replacing edits\n'
