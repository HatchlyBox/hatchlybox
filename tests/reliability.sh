#!/usr/bin/env bash
# The core loop carries on instead of failing: an AI helper at its usage limit hands the same work to another
# ready one in the same job (and isn't asked again in that job); one that runs out of time with work done carries
# on (twice at most); fallback off stops as before. A web version is checked like a build (web_check).
set -euo pipefail
repo=$(cd "$(dirname "$0")/.." && pwd)
w=$(mktemp -d)
trap 'rm -rf "$w" 2>/dev/null || true' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }
ok() { echo "PASS: $*"; }

mkdir -p "$w/data" "$w/cache" "$w/apps" "$w/ports" "$w/home/.claude" "$w/home/.codex" "$w/fake" "$w/proj"
ln -s "$repo/bin" "$w/data/bin"
# Fake helpers: Claude has reached its limit; Codex does the work; OpenCode is slow the first time.
cat > "$w/fake/claude" <<'EOF'
#!/bin/sh
echo "claude $*" >> "$HOME/calls"; echo "You've hit your usage limit · resets 4am (UTC)" >&2; exit 1
EOF
cat > "$w/fake/codex" <<'EOF'
#!/bin/sh
echo "codex $*" >> "$HOME/calls"
d=""; while [ $# -gt 0 ]; do [ "$1" = -C ] && d=$2; shift; done
echo done > "$d/done.txt"
EOF
cat > "$w/fake/opencode" <<'EOF'
#!/bin/sh
echo "opencode $*" >> "$HOME/calls"
case "$*" in *"ran out of time part-way"*) echo finished > finished.txt; exit 0 ;; esac
echo part > part.txt; sleep 30
EOF
chmod +x "$w/fake/"*
# The engine puts ~/.local/bin ahead of the system folders (where a real helper may be): the fakes go there.
mkdir -p "$w/home/.local/bin"; cp "$w/fake/"* "$w/home/.local/bin/"
echo '{"accessToken": "x"}' > "$w/home/.claude/.credentials.json"; echo '{"tokens": {}}' > "$w/home/.codex/auth.json"
run() {
  echo '{"id": "j1", "phase": "agent"}' > "$w/cache/job.json"; : > "$w/home/calls"; : > "$w/cache/log.txt"
  env -u ANTHROPIC_API_KEY -u OPENAI_API_KEY HOME="$w/home" PATH="$w/fake:$PATH" FAKE_CALLS="$w/home/calls" HATCHLYBOX_HOME=$w/data HATCHLYBOX_CACHE=$w/cache \
    HATCHLYBOX_APPS=$w/apps HATCHLYBOX_PORTS=$w/ports HATCHLYBOX_TEST=1 AGENT_TIMEOUT=12s \
    bash -c 'source "$0"; JOB=$HATCHLYBOX_CACHE/job.json LOG=$HATCHLYBOX_CACHE/log.txt JOB_DEADLINE=$(( $(date +%s) + 600 )) AGENT_RUNS=0; eval "$1"' "$repo/bin/hatchlybox" "$1"
}

# Which helper carries on.
[ "$(run 'agent_fallback " claude "')" = codex ] || fail "after Claude: $(run 'agent_fallback " claude "')"
[ "$(run 'agent_fallback " claude codex "')" = opencode ] || fail "OpenCode last"
rm "$w/home/.codex/auth.json"; [ "$(run 'agent_fallback " claude "')" = opencode ] || fail "Codex not signed in is skipped"
echo '{"tokens": {}}' > "$w/home/.codex/auth.json"
echo '{"fallback": "off"}' > "$w/data/settings.json"; [ -z "$(run 'agent_fallback " claude "')" ] || fail "fallback off"; rm "$w/data/settings.json"
ok "the next ready AI helper (signed in), OpenCode's free models last; none when fallback is off"

# A usage limit: Codex carries on in the same job; the job remembers, so Claude isn't asked again.
r=$(run 'run_agent claude "$HATCHLYBOX_APPS/../proj" "make a habit tracker"; echo "rc=$? used=$AGENT_USED"; run_agent claude "$HATCHLYBOX_APPS/../proj" "fix this"; echo "rc=$? used=$AGENT_USED"')
grep -q "rc=0 used=codex" <<< "$r" || fail "carry on: $r $(cat "$w/cache/log.txt")"
[ "$(grep -c '^claude' "$w/home/calls")" = 1 ] && [ "$(grep -c '^codex' "$w/home/calls")" = 2 ] || fail "calls: $(cat "$w/home/calls")"
grep -q "Another AI helper started this task" "$w/home/calls" && [ -f "$w/proj/done.txt" ] || fail "codex wasn't told it carries on"
[ "$(jq -c .limited "$w/cache/job.json")" = '["claude"]' ] && grep -q "Claude Code reached its usage limit: Codex carries on" "$w/cache/log.txt" || fail "job: $(cat "$w/cache/job.json")"
ok "a usage limit hands the work to the next helper in the same job, and the limited one isn't asked again"

# Fallback off: the limit fails the job as before, with the reset time kept.
echo '{"fallback": "off"}' > "$w/data/settings.json"
r=$(run 'run_agent claude "$HATCHLYBOX_APPS/../proj" "make it"; rc=$?; echo "rc=$rc"; agent_failure claude $rc')
grep -q "rc=1" <<< "$r" && grep -q "Claude Code has reached its usage limit (it resets 4am (UTC))" <<< "$r" || fail "fallback off: $r"
rm "$w/data/settings.json"
ok "with fallback off, a usage limit stops the job and says when it resets"

# Out of time with work done: it carries on and finishes.
rm -f "$w/proj/"*.txt
r=$(run 'run_agent opencode "$HATCHLYBOX_APPS/../proj" "make a big game"; echo "rc=$?"')
grep -q "rc=0" <<< "$r" && [ -f "$w/proj/finished.txt" ] && [ "$(grep -c '^opencode' "$w/home/calls")" = 2 ] || fail "time: $r $(cat "$w/home/calls")"
grep -q "out of time with work done: carrying on (1/2)" "$w/cache/log.txt" || fail "not logged"
ok "out of time with work done: it carries on where it stopped"

# Web check: index.html, files the pages load, scripts that parse.
e=$w/web/export; mkdir -p "$e/js"
out=$(run "web_check '$e'"); grep -q "index.html is missing" <<< "$out" || fail "no index: $out"
printf '<!doctype html><link rel="stylesheet" href="style.css"><script src="js/app.js"></script><img src="img/a.png"><a href="https://x.y">x</a><a href="#top">t</a>\n' > "$e/index.html"
echo 'console.log(1)' > "$e/js/app.js"
out=$(run "web_check '$e'")
grep -q "loads style.css" <<< "$out" && grep -q "loads img/a.png" <<< "$out" && ! grep -q "app.js\|x.y\|#top" <<< "$out" || fail "missing files: $out"
touch "$e/style.css"; mkdir -p "$e/img"; touch "$e/img/a.png"
[ -z "$(run "web_check '$e'")" ] || fail "a good export: $(run "web_check '$e'")"
if PATH="$HOME/.local/share/mise/shims:$PATH" command -v node >/dev/null 2>&1; then
  echo 'function (' > "$e/js/bad.js"; printf 'import x from "./a.js";\nexport const y = 1;\n' > "$e/js/mod.js"
  out=$(run "web_check '$e'"); grep -q "js/bad.js doesn't parse" <<< "$out" && ! grep -q "mod.js" <<< "$out" || fail "scripts: $out"
  ok "web check: index.html, every file the pages load, every script parses (modules as modules)"
else
  ok "web check: index.html and every file the pages load (no Node here: scripts are checked where it is)"
fi
