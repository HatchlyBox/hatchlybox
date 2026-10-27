#!/usr/bin/env bash
# The AI helpers for the front end (agents.sh): agents status says for each one whether it's installed and signed in
# (from the helper itself) and lists only the models it offers (Claude: its --model aliases; Codex: its models
# cache, hidden ones left out; OpenCode: opencode models); agents login opens a terminal window running the helper's
# own login by its full path (Omarchy's xdg-terminal-exec takes the command as it is, others after -e), and says in
# words what to do when the helper or a terminal is missing. The helpers and terminals are fakes.
set -euo pipefail
repo=$(cd "$(dirname "$0")/.." && pwd)
w=$(mktemp -d)
trap 'rm -rf "$w"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }
ok() { echo "PASS: $*"; }

mkdir -p "$w/home/.codex" "$w/data" "$w/cache" "$w/fake" "$w/base"
ln -s "$repo/bin" "$w/data/bin"; cp "$repo/platforms/linux/platform.env" "$w/data/"
echo '{"codexModel":"gpt-old"}' > "$w/data/settings.json"
# Only the tools hatchlybox needs, so no real helper or terminal on this machine is found.
for t in bash sh env jq sed awk grep cat date mkdir rm mv cp ln head tail tr cut sort uniq wc dirname basename readlink realpath timeout setsid flock stat sha256sum curl git unzip mktemp printf sleep chmod touch ls id uname getconf; do
  p=$(type -P "$t") && ln -sf "$p" "$w/base/$t"
done
cat > "$w/fake/claude" <<'F'
#!/bin/sh
case "$1 $2" in
  "auth status") echo '{"loggedIn": true, "authMethod": "claude.ai"}' ;;
  "--help "*) printf '%s\n' 'Usage: claude [options]' '  --fallback-model <model>   e.g. '"'"'nope'"'"'' "  --model <model>            Model for the session. Provide an alias (e.g." "                             'fable', 'opus', or 'sonnet') or a full name." "  -n, --name <name>          e.g. 'not-a-model'" ;;
esac
F
cat > "$w/fake/codex" <<'F'
#!/bin/sh
[ "$1 $2" = "login status" ] && { echo "Not logged in"; exit 1; }
F
cat > "$w/fake/opencode" <<'F'
#!/bin/sh
case "$1 $2" in
  "auth list") echo '[{"id":"anthropic"}]' ;;
  "models --standalone") printf '%s\n' 'opencode/big-pickle' 'ollama/qwen3:8b' 'Some log line' ;;
esac
F
chmod +x "$w/fake/"*
echo '{"fetched_at":"2026-10-01T00:00:00Z","models":[{"slug":"gpt-6-codex","display_name":"GPT-6 Codex","visibility":"list"},{"slug":"internal","visibility":"hide"}]}' > "$w/home/.codex/models_cache.json"
h() { env -i HOME="$w/home" PATH="$1" HATCHLYBOX_HOME="$w/data" HATCHLYBOX_CACHE="$w/cache" "${@:3}" "$repo/bin/hatchlybox" agents $2; }

s=$(h "$w/fake:$w/base" status)
jq -e 'map(.id) == ["claude","codex","opencode"] and all(.installed)' <<< "$s" >/dev/null || fail "status: $s"
jq -e '.[0].signedIn == true and ([.[0].models[].id] == ["fable","opus","sonnet"])' <<< "$s" >/dev/null || fail "claude: $(jq -c '.[0]' <<< "$s")"
jq -e '.[1].signedIn == false and .[1].models == [{"id":"gpt-6-codex","name":"GPT-6 Codex"}] and .[1].model == "gpt-old"' <<< "$s" >/dev/null || fail "codex: $(jq -c '.[1]' <<< "$s")"
jq -e '.[2].signedIn == true and ([.[2].models[].id] == ["opencode/big-pickle","ollama/qwen3:8b"]) and .[2].login == "opencode auth login"' <<< "$s" >/dev/null || fail "opencode: $(jq -c '.[2]' <<< "$s")"
[ "$(h "$w/fake:$w/base" "")" = "claude codex opencode " ] || fail "plain agents"
# Claude signed out: its JSON says so, though it exits 1.
sed -i 's|"auth status") echo .*|"auth status") echo '"'"'{"loggedIn": false}'"'"'; exit 1 ;;|' "$w/fake/claude"
[ "$(h "$w/fake:$w/base" status | jq -c '.[0].signedIn')" = false ] || fail "claude signed out: $(sed -n 3p "$w/fake/claude")"
ok "status: installed, signed in and the models each helper offers"

s=$(h "$w/base" status)
# hatchlybox adds /usr/local/bin to a short PATH: a helper this machine really has there is installed.
real=$(for a in claude codex opencode; do [ ! -x "/usr/local/bin/$a" ] || echo "$a"; done | jq -Rsc 'split("\n") | map(select(. != ""))')
jq -e --argjson real "$real" 'map(select(.id as $i | $real | index($i) | not)) | all(.installed == false and .signedIn == false and .models == [])' <<< "$s" >/dev/null || fail "none installed: $s"
rc=0; out=$(h "$w/base" "login claude" 2>&1) || rc=$?
[ $rc = 1 ] && [ "$out" = "Claude Code isn't installed on this computer: install it first, then sign in" ] || fail "login without claude: $rc $out"
ok "nothing installed: all false; signing in says to install first"

# Omarchy: xdg-terminal-exec runs the command as it is; the script runs the helper by its full path.
printf '#!/bin/sh\nprintf "%%s\\n" "$*" > "%s/term.args"\n' "$w" > "$w/fake/xdg-terminal-exec"; chmod +x "$w/fake/xdg-terminal-exec"
out=$(h "$w/fake:$w/base" "login codex")
sleep 1
[ "$(jq -r .terminal <<< "$out")" = xdg-terminal-exec ] && [ "$(cat "$w/term.args")" = "bash $w/cache/login-codex.sh" ] || fail "xdg-terminal-exec: $out $(cat "$w/term.args" 2>/dev/null)"
grep -qx "$w/fake/codex login" "$w/cache/login-codex.sh" && grep -q "Signing in to Codex" "$w/cache/login-codex.sh" && bash -n "$w/cache/login-codex.sh" || fail "login script: $(cat "$w/cache/login-codex.sh")"
rm -f "$w/fake/xdg-terminal-exec" "$w/term.args"
# Another desktop: $TERMINAL takes it after -e.
printf '#!/bin/sh\nprintf "%%s\\n" "$*" > "%s/term.args"\n' "$w" > "$w/fake/alacritty"; chmod +x "$w/fake/alacritty"
out=$(h "$w/fake:$w/base" "login claude" TERMINAL=alacritty); sleep 1
[ "$(cat "$w/term.args")" = "-e bash $w/cache/login-claude.sh" ] && grep -qx "$w/fake/claude auth login" "$w/cache/login-claude.sh" || fail "\$TERMINAL: $(cat "$w/term.args" 2>/dev/null)"
rm -f "$w/fake/alacritty"
rc=0; out=$(h "$w/fake:$w/base" "login opencode" 2>&1) || rc=$?
[ $rc = 1 ] && [ "$out" = "couldn't open a terminal window: open one yourself and run opencode auth login" ] || fail "no terminal: $rc $out"
ok "login: a terminal window runs the helper's own login (xdg-terminal-exec, \$TERMINAL), or says what to run"
