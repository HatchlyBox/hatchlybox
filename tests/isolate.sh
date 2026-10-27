#!/usr/bin/env bash
# Isolating agents and builds (adapter 7): phones run without a sandbox unless one is required; computers require
# one by default and say how to get it; with bubblewrap the agent sees only its project (read-write), its own login
# and program (wherever the home folder has it), never other creations, keys or the user's files; on macOS the
# sandbox-exec profile allows writes only to the project and the agent's folders and hides secrets and other
# creations. bwrap and sandbox-exec are fakes here (this phone can't run either), so this checks what is asked of
# them, not the kernel's enforcement.
set -euo pipefail
repo=$(cd "$(dirname "$0")/.." && pwd)
w=$(mktemp -d)
trap 'rm -rf "$w" 2>/dev/null || true' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }
ok() { echo "PASS: $*"; }

mkdir -p "$w/home/.ssh" "$w/data/keys" "$w/cache" "$w/apps/game/.git" "$w/apps/other" "$w/ports" "$w/fake" "$w/nosandbox"
ln -s "$repo/bin" "$w/data/bin"
echo secret > "$w/home/.ssh/id_ed25519"; echo '{}' > "$w/apps/game/.hatchlybox.json"
# The user's agents: Claude's native install behind ~/.local/bin, Codex from npm's own prefix.
mkdir -p "$w/home/.local/share/claude/versions" "$w/home/.local/bin" "$w/home/.npm-global/lib/node_modules/@openai/codex/bin" "$w/home/.npm-global/bin"
printf '#!/bin/sh\necho claude\n' > "$w/home/.local/share/claude/versions/2.1.0"; chmod +x "$w/home/.local/share/claude/versions/2.1.0"
ln -s "$w/home/.local/share/claude/versions/2.1.0" "$w/home/.local/bin/claude"
printf '#!/bin/sh\necho codex\n' > "$w/home/.npm-global/lib/node_modules/@openai/codex/bin/codex.js"; chmod +x "$w/home/.npm-global/lib/node_modules/@openai/codex/bin/codex.js"
ln -s ../lib/node_modules/@openai/codex/bin/codex.js "$w/home/.npm-global/bin/codex"
mkdir -p "$w/home/.claude"; echo '{}' > "$w/home/.claude/.credentials.json"
# This phone's /usr/bin/bwrap is proot's stub: a PATH without any sandbox for the "none" cases.
for t in sh bash env jq ls sort date flock true realpath readlink dirname mktemp rm cat mkdir grep sed printf test uname cut type tr awk head; do
  p=$(type -P "$t") && ln -sf "$p" "$w/nosandbox/$t"
done
iso() { env HOME="$w/home" HATCHLYBOX_HOME="$w/data" HATCHLYBOX_CACHE="$w/cache" HATCHLYBOX_APPS="$w/apps" HATCHLYBOX_PORTS="$w/ports" HATCHLYBOX_BACKUPS="$w/backups" "$@"; }
plat() { cp "$repo/platforms/$1/platform.env" "$w/data/"; rm -f "$w/data/settings.json"; }

# A phone: no sandbox, runs as before.
plat hatchlybox
out=$(iso PATH="$w/nosandbox" "$repo/bin/isolate" build "$w/apps/game" sh -c 'echo ran $HATCHLYBOX_SANDBOX' 2>&1) || fail "phone: $out"
grep -q "ran 1" <<< "$out" && grep -q "compatibility mode" <<< "$out" || fail "phone run: $out"
echo '{"agentIsolation":"required"}' > "$w/data/settings.json"
rc=0; out=$(iso PATH="$w/nosandbox" "$repo/bin/isolate" build "$w/apps/game" true 2>&1) || rc=$?
[ $rc = 126 ] && grep -q "hatchlybox set agentIsolation compatible" <<< "$out" || fail "phone required: $rc $out"
ok "phone: runs without a sandbox; agentIsolation=required refuses"

# A Linux computer without bubblewrap: refused, with what to install; doctor and isolation say so.
plat linux
rc=0; out=$(iso PATH="$w/nosandbox" "$repo/bin/isolate" agent "$w/apps/game" claude -p hi 2>&1) || rc=$?
[ $rc = 126 ] && grep -qi "bubblewrap" <<< "$out" || fail "linux without bwrap: $rc $out"
[ "$(iso PATH="$w/nosandbox" "$repo/bin/hatchlybox" isolation 2>/dev/null)" = blocked ] || fail "isolation: blocked"
d=$(iso PATH="$w/nosandbox" "$repo/bin/hatchlybox" doctor 2>/dev/null || true)
grep -q "^missing sandbox: install bubblewrap" <<< "$d" || fail "doctor names bubblewrap: $d"
echo '{"agentIsolation":"compatible"}' > "$w/data/settings.json"
iso PATH="$w/nosandbox" "$repo/bin/isolate" build "$w/apps/game" true 2>/dev/null || fail "linux compatible by choice"
ok "linux: a sandbox is required by default; the refusal says what to install; compatible by choice"

# A fake bubblewrap that enforces the probe and records each run.
cat > "$w/fake/bwrap" <<'B'
#!/bin/bash
for a in "$@"; do [ "$a" = --tmpfs ] && t=1; done
if [ "${*: -3:1}" = "!" ] && [ -n "${t:-}" ]; then exit 0; fi
printf '%s\n' "$@" > "$BWRAP_LOG"; while [ "$1" != -- ]; do shift; done; shift; exec "$@"
B
chmod +x "$w/fake/bwrap"
rm -f "$w/data/settings.json"
P="$w/home/.local/bin:$w/home/.npm-global/bin:$w/fake:$PATH"
[ "$(iso PATH="$P" "$repo/bin/sandbox-check" --kind)" = bwrap ] || fail "kind bwrap"
a=$(iso PATH="$P" HATCHLYBOX_ISOLATE_SHOW=1 "$repo/bin/isolate" agent "$w/apps/game" claude -p hi)
pair() { awk -v a="$1" -v b="$2" -v c="$3" 'p2 == a && p1 == b && $0 == c {f = 1} {p2 = p1; p1 = $0} END {exit !f}' <<< "$a"; }
pair --bind "$w/apps/game" "$w/apps/game" || fail "project read-write"
pair --ro-bind "$w/apps/game/.git" "$w/apps/game/.git" && pair --ro-bind "$w/apps/game/.hatchlybox.json" "$w/apps/game/.hatchlybox.json" || fail "history read-only"
grep -qx -- "--tmpfs" <<< "$a" && pair --tmpfs "$w/home" --bind || fail "home replaced"
pair --ro-bind "$w/home/.local/share/claude" "$w/home/.local/share/claude" || fail "claude's install: $a"
pair --symlink "$w/home/.local/share/claude/versions/2.1.0" "$w/home/.local/bin/claude" || fail "claude on the PATH"
pair --ro-bind "$w/home/.npm-global/lib/node_modules/@openai/codex" "$w/home/.npm-global/lib/node_modules/@openai/codex" || fail "codex's package"
pair --ro-bind "$w/home/.claude/.credentials.json" "$w/home/.claude/.credentials.json" || fail "claude's login"
grep -qE "^$w/(home/\.ssh|data/keys|apps/other)" <<< "$a" && fail "secrets or another creation exposed" || true
grep -qx "/mnt" <<< "$a" && fail "Windows drives exposed" || true
! grep -qx "$w/home/.local/bin" <<< "$(awk 'p == "--ro-bind" {print} {p = $0}' <<< "$a")" || fail "all of ~/.local/bin exposed"
ok "bwrap: the project, its history read-only, the agent's own login and program; no keys, secrets or other creations"
# Links left in the sandbox's home from before (a moved install) are cleared, so bwrap can make them again.
mkdir -p "$w/cache/agent-home/.local/bin"; ln -sfn /old/place/godot "$w/cache/agent-home/.local/bin/godot"; ln -sfn /old/claude "$w/cache/agent-home/.local/bin/claude"
iso PATH="$P" HATCHLYBOX_ISOLATE_SHOW=1 "$repo/bin/isolate" agent "$w/apps/game" claude -p hi >/dev/null
[ ! -L "$w/cache/agent-home/.local/bin/godot" ] && [ ! -L "$w/cache/agent-home/.local/bin/claude" ] || fail "stale links stay"
ok "links left in the sandbox's home from before are cleared"
# Making a version from another one: the same creation's versions are readable (before the project, which stays
# writable), another creation's are not.
mkdir -p "$w/ports/game/linux" "$w/ports/other/linux"
a=$(iso PATH="$P" HATCHLYBOX_ISOLATE_SHOW=1 "$repo/bin/isolate" agent "$w/ports/game/linux" claude -p hi)
pair --ro-bind "$w/apps/game" "$w/apps/game" && pair --ro-bind "$w/ports/game" "$w/ports/game" && pair --bind "$w/ports/game/linux" "$w/ports/game/linux" || fail "siblings: $a"
[ "$(grep -nx -- "$w/ports/game" <<< "$a" | head -1 | cut -d: -f1)" -lt "$(grep -nx -- "$w/ports/game/linux" <<< "$a" | head -1 | cut -d: -f1)" ] || fail "the project isn't mounted over its siblings"
! grep -q "$w/ports/other\|$w/apps/other" <<< "$a" || fail "another creation is visible"
ok "a version is made with the same creation's other versions readable, never another creation's"
out=$(iso PATH="$P" BWRAP_LOG="$w/bw.log" "$repo/bin/isolate" build "$w/apps/game" sh -c 'echo built $HATCHLYBOX_MANAGED_AGENT')
# (The fake doesn't apply --setenv: what it was asked to set is in its log.)
[ "${out% *}" = built ] && grep -qx -- --die-with-parent "$w/bw.log" && a=$(cat "$w/bw.log") && pair --setenv HATCHLYBOX_MANAGED_AGENT 0 || fail "bwrap run: $out"
ok "bwrap: runs the command inside"

# Gradle's wrapper locks beside its distribution: the user's unpacked ones are copied into the sandbox's own Gradle
# home (writable there), not bound read-only; one still downloading isn't copied.
dist=wrapper/dists/gradle-8.11.1-bin/abc
mkdir -p "$w/home/.gradle/$dist/gradle-8.11.1/bin" "$w/home/.gradle/wrapper/dists/gradle-9-bin/def"
touch "$w/home/.gradle/$dist/gradle-8.11.1-bin.zip.ok" "$w/home/.gradle/$dist/gradle-8.11.1-bin.zip.lck" "$w/home/.gradle/wrapper/dists/gradle-9-bin/def/x.zip.part"
a=$(iso PATH="$P" HATCHLYBOX_ISOLATE_SHOW=1 "$repo/bin/isolate" build "$w/apps/game" true)
[ -f "$w/cache/gradle-home/$dist/gradle-8.11.1-bin.zip.ok" ] && [ -d "$w/cache/gradle-home/$dist/gradle-8.11.1/bin" ] || fail "distribution copied"
[ ! -e "$w/cache/gradle-home/wrapper/dists/gradle-9-bin/def" ] || fail "an unfinished download copied"
pair --bind "$w/cache/gradle-home" "$w/home/.gradle" && ! grep -qx "$w/home/.gradle/wrapper" <<< "$a" || fail "the wrapper bound from the user's home: $a"
ok "bwrap: Gradle's distributions are the sandbox's own copies (its wrapper can lock), never the user's"

# macOS: sandbox-exec's profile. The fake refuses the probe's read like the real one would.
cat > "$w/fake/sandbox-exec" <<'S'
#!/bin/bash
[ "$1" = -p ] || exit 2
case $2 in *"(deny file-read* (literal"*) [ "$3" = /bin/cat ] && exit 1 ;; esac
shift 2; exec "$@"
S
chmod +x "$w/fake/sandbox-exec"; plat macos
[ "$(iso PATH="$P" HATCHLYBOX_TEST_OS=Darwin "$repo/bin/sandbox-check" --kind)" = seatbelt ] || fail "kind seatbelt"
sb=$(iso PATH="$P" HATCHLYBOX_TEST_OS=Darwin HATCHLYBOX_ISOLATE_SHOW=1 "$repo/bin/isolate" agent "$w/apps/game" claude -p hi)
python3 -I -c 'import sys; s=sys.argv[1]; d=0
for ch in s:
    d += (ch == "(") - (ch == ")"); assert d >= 0
assert d == 0' "$sb" || fail "profile parentheses: $sb"
grep -q "(deny file-write\*)" <<< "$sb" && grep -q "(subpath \"$w/apps/game\")" <<< "$sb" || fail "writes only to the project"
grep -q "(deny file-read\* (subpath \"$w/apps\")" <<< "$sb" && grep -q "(subpath \"$w/data/skills\")" <<< "$sb" || fail "other creations and the engine's keys"
grep -q "(subpath \"$w/home/.ssh\")" <<< "$sb" && grep -q "Library/Mail" <<< "$sb" || fail "the user's secrets"
grep -q "(literal \"$w/apps/game/.hatchlybox.json\")" <<< "$sb" || fail "identity read-only"
grep -q "keys" <<< "$(grep -o "(subpath \"$w/data/[^\"]*\")" <<< "$sb")" && fail "keys readable" || true
out=$(iso PATH="$P" HATCHLYBOX_TEST_OS=Darwin "$repo/bin/isolate" build "$w/apps/game" sh -c 'echo mac $HATCHLYBOX_SANDBOX $GRADLE_USER_HOME')
[ "$out" = "mac 1 $w/cache/gradle-home" ] || fail "mac run: $out"
ok "macOS: writes only to the project and the agent's folders; no keys, secrets or other creations"
