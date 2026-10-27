#!/usr/bin/env bash
# public-check.sh [engine dir] [app dir]: is everything ready for the repositories to go public? Read-only: it changes
# nothing, here or on GitHub. Checks both repositories (files and their whole history), their issues and pull
# requests with every comment, and the files a public project needs. Words that must never be public (a user name,
# an email, a home network's addresses) are read from a file outside the repositories, one per line:
#   ${PUBLIC_CHECK_WORDS:-~/.config/hatchlybox/private-words}
# Exit 0: nothing found. Exit 1: something to look at (each finding is printed).
set -uo pipefail
engine=${1:-$(cd "$(dirname "$0")/.." && pwd)}
app=${2:-$HOME/apps/hatchlybox}
org=${PUBLIC_CHECK_ORG:-HatchlyBox}
words_file=${PUBLIC_CHECK_WORDS:-$HOME/.config/hatchlybox/private-words}
problems=0
bad() { echo "  ✗ $*"; problems=$((problems + 1)); }
good() { echo "  ✓ $*"; }

words=()
if [ -f "$words_file" ]; then mapfile -t words < <(grep -v '^[[:space:]]*\(#\|$\)' "$words_file"); fi
[ ${#words[@]} -gt 0 ] || echo "(no private words in $words_file: add your user names, emails and network addresses there, one per line)"
# Secrets and old names, as one extended regex; private words are matched as fixed strings on their own.
secrets='AKIA[0-9A-Z]{16}|gh[pousr]_[A-Za-z0-9]{36}|github_pat_[A-Za-z0-9_]{40,}|sk-ant-[A-Za-z0-9_-]{20,}|AIza[0-9A-Za-z_-]{35}|-----BEGIN (RSA |EC |OPENSSH |)PRIVATE KEY|"private_key":|xox[bap]-[0-9A-Za-z-]+|ya29\.[0-9A-Za-z_-]+'
oldnames='apk-maker|apkmaker|agent ?box|omalauncher|\bhatchly\b'

scan_text() { # scan_text <what> < text
  local t; t=$(cat)
  grep -anEi "$secrets" <<< "$t" | grep -vE 'gh\[pousr\]|github_pat_\[|sk-ant-\[|AIza\[|AKIA\[' | head -5 | sed "s|^|$1: secret? |"
  grep -anEi "$oldnames" <<< "$t" | grep -viE 'hatchly box|"hatchly"|oldnames=|\\\.apkmaker\\\.json' | head -5 | sed "s|^|$1: old name: |"
  local w; for w in "${words[@]}"; do grep -anFi -- "$w" <<< "$t" | head -3 | sed "s|^|$1: private word: |"; done
}

for repo in "$engine" "$app"; do
  name=$(basename "$repo")
  echo "== $name ($repo)"
  [ -d "$repo/.git" ] || { bad "not a git repository"; continue; }
  # Files and history.
  hits=$(git -C "$repo" log -p --all --no-color --text 2>/dev/null | grep -aE '^\+' | grep -av '^+++' | tr -d '\000' | scan_text "history" | sort -u)
  [ -z "$hits" ] && good "history: no secrets, old names or private words" || { bad "history:"; sed 's/^/      /' <<< "$hits" | head -20; }
  authors=$(git -C "$repo" log --all --format='%an <%ae>%n%cn <%ce>' | sort -u | grep -vx 'Hatchlybox <hatchlybox@localhost>')
  [ -z "$authors" ] && good "every commit is by Hatchlybox <hatchlybox@localhost>" || bad "other commit authors: $(tr '\n' ' ' <<< "$authors")"
  ever=$(git -C "$repo" log --all --name-only --format= | sort -u | grep -E '(^|/)(NIGHTLY\.md|\.apkmaker\.json|\.hatchlybox\.json|local\.properties|.*\.(jks|keystore|p12|pem|pass))$')
  [ -z "$ever" ] && good "no private files in the history" || bad "private files in the history (gone from the files, still in old commits; rewrite the history or squash before going public): $(tr '\n' ' ' <<< "$ever")"
  # What a public project needs.
  for f in LICENSE README.md CONTRIBUTING.md SECURITY.md .github/pull_request_template.md .github/ISSUE_TEMPLATE/bug.md .github/ISSUE_TEMPLATE/idea.md; do
    [ -f "$repo/$f" ] || bad "missing $f"
  done
  grep -q 'GNU AFFERO GENERAL PUBLIC LICENSE' "$repo/LICENSE" 2>/dev/null && good "LICENSE is the AGPL 3.0" || bad "LICENSE isn't the AGPL 3.0"
  [ -z "$(git -C "$repo" status --porcelain --untracked-files=no)" ] || bad "changes not committed yet"
done
[ -f "$app/app/src/main/assets/legal/PRIVACY.md" ] && [ -f "$app/app/src/main/assets/legal/THIRD-PARTY.md" ] && good "the app has its privacy policy and licences" || bad "the app's PRIVACY.md or THIRD-PARTY.md is missing"
# gradle.properties is in git and shared by every machine: no secrets, no machine's paths, ever.
gp=$(git -C "$app" show HEAD:gradle.properties 2>/dev/null || true)
if [ -z "$gp" ]; then bad "the app has no gradle.properties in git: a fresh copy can't build"
elif grep -vE '^\s*#' <<< "$gp" | grep -qiE 'password|secret|token|api.?key|storeFile|keyAlias|=\s*(/|~|[A-Za-z]:\\)'; then
  bad "gradle.properties has a secret or a machine's path: $(grep -vE '^\s*#' <<< "$gp" | grep -iE 'password|secret|token|api.?key|storeFile|keyAlias|=\s*(/|~|[A-Za-z]:\\)' | head -2 | tr '\n' ' ')"
else good "gradle.properties has only shared settings"; fi
! grep -q 'migrate_names' "$engine/install.sh" && good "the installer has no old-name migration" || bad "install.sh still moves old names (migrate_names)"

# Issues and pull requests, with their comments: everything in them goes public too.
echo "== GitHub ($org)"
if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
  for r in hatchlybox hatchlybox-android; do
    text=$(gh api --paginate "repos/$org/$r/issues?state=all&per_page=100" --jq '.[] | "#\(.number) \(.title)\n\(.body // "")"' 2>/dev/null
           gh api --paginate "repos/$org/$r/issues/comments?per_page=100" --jq '.[] | "comment \(.html_url)\n\(.body // "")"' 2>/dev/null
           gh api --paginate "repos/$org/$r/pulls/comments?per_page=100" --jq '.[] | "review \(.html_url)\n\(.body // "")"' 2>/dev/null)
    n=$(gh api "repos/$org/$r/issues?state=all&per_page=1" --jq length 2>/dev/null || echo "?")
    hits=$(scan_text "$r issues" <<< "$text")
    [ -z "$hits" ] && good "$r: issues, pull requests and comments are clean ($( [ "$n" = 0 ] && echo none yet || echo checked))" || { bad "$r: issues or pull requests:"; sed 's/^/      /' <<< "$hits" | head -20; }
    rel=$(gh release list -R "$org/$r" --limit 100 --json tagName,name --jq '.[] | "\(.tagName) \(.name)"' 2>/dev/null)
    hits=$(for t in $(cut -d' ' -f1 <<< "$rel"); do gh release view "$t" -R "$org/$r" --json body --jq .body; done 2>/dev/null | scan_text "$r releases")
    [ -z "$hits" ] && good "$r: release notes are clean" || { bad "$r: release notes:"; sed 's/^/      /' <<< "$hits"; }
    # 6.3 is the first version with the welcome screen (privacy, Google's SDK licence) and the licence texts.
    old=$(cut -d' ' -f1 <<< "$rel" | grep -E '^v[0-9]' | while read -r t; do
      [ "$(printf '%s\n' v6.3 "$t" | sort -V | head -1)" = "$t" ] && [ "$t" != v6.3 ] && echo "$t"; done)
    [ -z "$old" ] && good "$r: every release has the licence screens" || bad "$r: releases from before 6.3 (no licence screens): $(echo $old)"
  done
else
  bad "gh isn't signed in: issues and pull requests weren't checked"
fi

echo
checklist=${HATCHLYBOX_CHECKLIST:-$HOME/hatchlybox-maintainers/release-checklist.md}
echo "Still yours to decide or do ($checklist, in the private HatchlyBox/maintainers):"
grep -E '^- \*\*(DECIDE|TODO|BLOCKER)' "$checklist" 2>/dev/null | sed -E 's/^- \*\*([A-Z ()a-z]+)\*\* /  - [\1] /' | cut -c1-140
echo
if [ "$problems" = 0 ]; then echo "Ready: nothing found. release/go-public.sh makes a repository public."; exit 0; fi
echo "$problems thing(s) to look at before going public."; exit 1
