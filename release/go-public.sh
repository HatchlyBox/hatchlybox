#!/usr/bin/env bash
# go-public.sh <hatchlybox|hatchlybox-android>: makes HatchlyBox/<name> public, once release/public-check.sh finds nothing. It asks you
# to type the repository's name first: going public can't be taken back (copies made while it's public stay).
# Then, with the repository public, it turns on what's free for public repositories:
#  - main (and nightly) protected: changes only through pull requests, no force-pushes, no deleting the branch
#  - private vulnerability reporting (SECURITY.md points people there)
set -euo pipefail
org=${PUBLIC_CHECK_ORG:-HatchlyBox}
name=${1:-}
case $name in hatchlybox|hatchlybox-android) ;; *) echo "usage: go-public.sh hatchlybox|hatchlybox-android" >&2; exit 2 ;; esac
repo=$org/$name

bash "$(dirname "$0")/public-check.sh" || { echo; echo "Not made public: fix what public-check.sh found first." >&2; exit 1; }
echo
echo "$repo becomes PUBLIC: anyone can see its code, history, issues and releases, and copy them."
read -rp "Type $name to go ahead: " typed
[ "$typed" = "$name" ] || { echo "Not made public."; exit 1; }

gh repo edit "$repo" --visibility public --accept-visibility-change-consequences
gh api -X PUT "repos/$repo/private-vulnerability-reporting" >/dev/null && echo "private vulnerability reporting: on"
for b in main nightly; do
  gh api "repos/$repo/branches/$b" >/dev/null 2>&1 || continue
  # GitHub locks the repository for a moment while it changes visibility: wait that out.
  for try in $(seq 1 20); do
    out=$(gh api -X PUT "repos/$repo/branches/$b/protection" --input - 2>&1 <<'EOF'
{"required_status_checks": null, "enforce_admins": false,
 "required_pull_request_reviews": {"required_approving_review_count": 0, "dismiss_stale_reviews": true},
 "restrictions": null, "allow_force_pushes": false, "allow_deletions": false}
EOF
) && break
    grep -q locked <<< "$out" && [ "$try" -lt 20 ] || { echo "$out" >&2; exit 1; }
    sleep 15
  done
  echo "$b: protected (pull requests only, no force-push, no deleting)"
done
echo "$repo is public: https://github.com/$repo"
