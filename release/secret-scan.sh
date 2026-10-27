#!/usr/bin/env bash
# secret-scan.sh <repo>: likely secrets and personal data anywhere in the repo's history (added lines only).
cd "$1" || exit 1
git log -p --all --no-color --text 2>/dev/null | grep -E '^\+' | grep -v '^+++' | grep -naE \
 'AKIA[0-9A-Z]{16}|ghp_[A-Za-z0-9]{30,}|github_pat_|gho_[A-Za-z0-9]{20,}|sk-ant-[A-Za-z0-9_-]{10,}|sk-[A-Za-z0-9]{32,}|AIza[0-9A-Za-z_-]{30,}|-----BEGIN (RSA |EC |OPENSSH |)PRIVATE KEY|"private_key"|xox[bap]-|ya29\.|storePassword *= *"?[^"$ ]{4,}|keyPassword|@gmail\.com|/root/|/home/[a-z]+/|192\.168\.[0-9]+\.[0-9]+|10\.0\.[0-9]+\.[0-9]+' \
 | grep -vE 'example|EXAMPLE|placeholder|<[a-z ]+>|\$\{?[A-Z_]+' | cut -c1-200 | sort | uniq -c | sort -rn | head -60
echo "--- files ever committed that look like keys"
git log --all --name-only --format= | sort -u | grep -iE '\.(jks|keystore|p12|pem|key|enc)$|service.?account|credentials|\.env$|auth\.json|local\.properties' | head
