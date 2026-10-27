#!/usr/bin/env bash
# Copies Hatchlybox Engine into the Hatchlybox Android app's private engine (app/src/main/assets/maker),
# with the app's platform file (platforms/hatchlybox/platform.env). The engine itself is the same
# everywhere: nothing in it is changed on the way.
#   ./sync-hatchlybox.sh [app folder, default ~/apps/hatchlybox]
set -euo pipefail
cd "$(dirname "$0")"
dest=${1:-$HOME/apps/hatchlybox}/app/src/main/assets/maker
[ -d "$dest/bin" ] || { echo "no engine at $dest" >&2; exit 1; }
rm -rf "$dest/bin" && cp -r bin "$dest/bin"
cp creation/AGENTS.md "$dest/AGENTS.md"
cp platforms/hatchlybox/platform.env platforms/hatchlybox/environment.md "$dest/"
# The app's template, without this machine's SDK path.
rm -rf "$dest/template" && cp -r template "$dest/template" && rm -f "$dest/template/local.properties"
# The visual skill's tools and library.
rm -rf "$dest/visual" && mkdir -p "$dest/visual" && cp -r visual/bin visual/kb visual/gl.list "$dest/visual/"
rm -rf "$dest/skills" && cp -r skills "$dest/skills"
rm -rf "$dest/starter" && cp -r starter "$dest/starter"
# The app copies the engine again when this changes (MakerModel.syncEngine).
echo "hatchlybox-$(sed -n 's/^VERSION=//p' bin/hatchlybox)-$(cat bin/* creation/AGENTS.md platforms/hatchlybox/* visual/bin/* visual/kb/*/* | sha256sum | cut -c1-8)" > "$dest/VERSION"
# Hatchlybox Nightly (package com.hatchlybox.nightly) has its own ports, sync link scheme and version mark, so it
# never meets stable's on a phone that has both.
if grep -q 'applicationId = "com.hatchlybox.nightly"' "$dest/../../../../build.gradle.kts" 2>/dev/null; then
  sed -i 's/^SERVE_PORT=8876$/SERVE_PORT=8877/; s/^ADB_PORT=5041$/ADB_PORT=5042/' "$dest/platform.env"
  sed -i 's/^KEY_PORT=8766$/KEY_PORT=8878/' "$dest/bin/hatchlybox"
  sed -i 's|hatchlybox://sync/|hatchlybox-nightly://sync/|g' "$dest/bin/Sync.java"
  sed -i 's/$/-nightly/' "$dest/VERSION"
  grep -q '^SERVE_PORT=8877$' "$dest/platform.env" && grep -q '^ADB_PORT=5042$' "$dest/platform.env" && grep -q '^KEY_PORT=8878$' "$dest/bin/hatchlybox" \
    && ! grep -q 'hatchlybox://sync/' "$dest/bin/Sync.java" || { echo "the nightly's identity wasn't applied" >&2; exit 1; }
fi
echo "Hatchlybox Engine $(cat "$dest/VERSION") copied to $dest"
