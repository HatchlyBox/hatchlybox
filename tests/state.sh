#!/usr/bin/env bash
# Each app's status (apps.json .state) from its metadata: one word and the actions that fit it.
set -euo pipefail
repo=$(cd "$(dirname "$0")/.." && pwd)
w=$(mktemp -d)
trap 'rm -rf "$w"' EXIT
export HATCHLYBOX_HOME=$repo HATCHLYBOX_CACHE=$w/cache HATCHLYBOX_APPS=$w/apps HATCHLYBOX_TEST=1
set +e
source "$repo/bin/hatchlybox"
set -e
skills_index() { :; }
fail() { echo "FAIL: $*" >&2; exit 1; }
mkdir -p "$CACHE"
n=0
app() { n=$((n + 1)); mkdir -p "$APPS/$1"; jq -c --arg s "$1" --argjson u "$n" '. + {slug: $s, updated: $u}' <<< "$2" > "$APPS/$1/.hatchlybox.json"; }
built='"apk": "x", "artifacts": {"apk": {"sha256": "N"}}'
app stopped '{"status": "building"}'
app failed '{"status": "failed"}'
app review '{"status": "ready", '"$built"', "pending": {"built": true}}'
app change-failed '{"status": "ready", '"$built"', "pending": {"built": false}}'
app rebuild '{"status": "ready", "apk": "x", "outcomes": {"install": "stale"}}'
app live '{"status": "ready", '"$built"', "play": {"tracks": {"production": {}}}}'
app testers '{"status": "ready", '"$built"', "play": {"tracks": {"internal": {}}}}'
app blocked '{"status": "ready", '"$built"', "outcomes": {"install": "signature-conflict"}}'
app downloaded '{"status": "ready", '"$built"', "downloaded": 5, "outcomes": {"install": "download-offered"}}'
app redownloaded '{"status": "installed", '"$built"', "installedArtifact": {"sha256": "O"}, "outcomes": {"install": "download-offered"}}'
app crashed '{"status": "installed", '"$built"', "installedArtifact": {"sha256": "N"}, "outcomes": {"install": "verified", "runtime": "crashed"}}'
app update '{"status": "built", '"$built"', "installedArtifact": {"sha256": "O"}, "outcomes": {"install": "unverified"}}'
app installed '{"status": "installed", '"$built"', "installedArtifact": {"sha256": "N"}, "outcomes": {"install": "confirmed"}}'
app legacy '{"status": "ready", "apk": "x", "downloaded": 5}'
app ready '{"status": "built", '"$built"', "outcomes": {"install": "unverified"}}'
# Edited in a terminal after its build; one built since its last edit stays as it was.
app changed '{"status": "installed", "apk": "x", "artifacts": {"apk": {"sha256": "N", "at": 1}}, "installedArtifact": {"sha256": "N"}}'
echo 'class A' > "$APPS/changed/A.kt"
app unchanged '{"status": "installed", "apk": "x", "artifacts": {"apk": {"sha256": "N", "at": 4000000000}}, "installedArtifact": {"sha256": "N"}}'
echo 'class A' > "$APPS/unchanged/A.kt"
list_apps_impl
got=$(jq -r '.[] | "\(.slug)=\(.state.key)"' "$CACHE/apps.json")
for s in stopped failed review change-failed rebuild live testers blocked downloaded crashed update installed ready changed; do
  grep -qx "$s=$s" <<< "$got" || fail "$s: $(grep "^$s=" <<< "$got")"
done
grep -qx 'redownloaded=downloaded' <<< "$got" || fail 'browser reinstall should wait for the user'
grep -qx 'legacy=installed' <<< "$got" || fail 'pre-2.17.5 downloads stay installed'
grep -qx 'unchanged=installed' <<< "$got" || fail 'unchanged code needs no rebuild'
[ "$(jq -c '.[] | select(.slug == "changed") | .state.actions' "$CACHE/apps.json")" = '["rebuild","open"]' ] || fail 'changed actions'
jq -e 'all(.[]; (.state.word | length) > 0 and (.state.detail | length) > 0 and (.state.actions | length) > 0 and .next.state != null)' "$CACHE/apps.json" >/dev/null \
  || fail 'every state needs a word, a detail, actions and the old .next'
[ "$(jq -c '.[] | select(.slug == "downloaded") | .state.actions' "$CACHE/apps.json")" = '["confirm","install","open"]' ] || fail 'downloaded actions'
echo "PASS: app states and their actions"
