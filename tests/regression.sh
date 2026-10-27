#!/usr/bin/env bash
# Regression tests use disposable projects, state and cryptographic keys only.
set -euo pipefail
repo=$(cd "$(dirname "$0")/.." && pwd)
w=$(mktemp -d)
trap 'rm -rf "$w"' EXIT
export HATCHLYBOX_HOME=$repo HATCHLYBOX_CACHE=$w/cache HATCHLYBOX_APPS=$w/apps HATCHLYBOX_TEST=1
# These test the Android steps (builds, installs, keys) without an SDK: Android counts as set up.
export HATCHLYBOX_TEST_ANDROID=1
# A resumed job would rerun "$0", this whole suite, from inside it: endlessly.
export HATCHLYBOX_SELF=true
set +e
source "$repo/bin/hatchlybox"
set -e
list_apps() { :; }
fail() { echo "FAIL: $*" >&2; exit 1; }
ok() { echo "PASS: $*"; }
# Atomic JSON transactions do not lose independent increments.
echo '{"n":0}' > "$w/counter.json"
for _ in $(seq 20); do json_edit "$w/counter.json" '.n += 1' & done
wait
[ "$(jq .n "$w/counter.json")" = 20 ] || fail 'JSON concurrent updates'
ok 'JSON concurrent updates'
# Startup verification returns unavailable when logcat fails, not success.
(
 adb() { return 1; }
 HATCHLYBOX_STARTUP_DELAY=0
 set +e; crash_check com.example; rc=$?; set -e
 [ "$rc" = 4 ] || fail 'unavailable crash buffer'
)
ok 'unavailable crash buffer is not startup success'
# Propagate all reinstall outcomes, preserving the original reviewed bug.
for result in 2 3 4 1; do
 (
  job() { :; }; meta() { :; }; run_agent() { return 0; }; build_fixing() { return 0; }; save() { return 0; }
  crash_check() { echo 'Process: com.example,'; return 3; }
  do_install() { return "$result"; }
  mkdir -p "$APPS/demo"; echo '{"pkg":"com.example"}' > "$APPS/demo/.hatchlybox.json"
  set +e; crash_fix demo mock; rc=$?; set -e
  [ "$rc" = "$result" ] || fail "reinstall $result was suppressed as $rc"
 )
done
ok 'crash repair preserves reinstall outcomes'
# Final GitHub synchronization happens after runtime repair, even browser fallback.
(
 events=$w/events
 job() { echo "job:$1" >> "$events"; }; meta() { :; }; install_skills() { :; }; run_agent() { return 0; }
 validate_project() { return 0; }; build_fixing() { return 0; }; note_skills() { :; }; save() { return 0; }
 do_install() { return 0; }; crash_fix() { echo repair >> "$events"; return 2; }
 artifact_record() { :; }; record_checks() { :; }
 sync_final() { echo sync >> "$events"; }; pending() { return 1; }
 work demo mock request || fail "work result"
 [ "$(sed -n '/^repair/,$p' "$events")" = $'repair\nsync\njob:ready' ] || fail 'final synchronization order'
)
ok 'repaired source synchronized before final result'
# Content identity catches manual edits and ignores build products.
mkdir -p "$APPS/demo/app/build"; echo source > "$APPS/demo/Main.kt"
a=$(source_id demo)
echo output > "$APPS/demo/app/build/output"
[ "$a" = "$(source_id demo)" ] || fail 'build output changed source identity'
echo changed >> "$APPS/demo/Main.kt"
[ "$a" != "$(source_id demo)" ] || fail 'manual change not detected'
ok 'source fingerprint detects manual edits'
# PID reuse cannot validate a different process.
echo "{\"pid\":$$,\"process\":\"wrong\"}" > "$JOB"
if worker_alive; then fail 'PID identity ignored'; fi
ok 'process identity rejects reused PID'
# An unenforced bwrap stub must never pass as a sandbox. Required mode refuses it.
if "$repo/bin/sandbox-check"; then
  HATCHLYBOX_CACHE=$w/isolation ANDROID_HOME=/opt/android-sdk "$repo/bin/isolate" build "$APPS/demo" bash -c 'test ! -e "$HOME/.config/gh/hosts.yml"'
else
  fake=$w/required; mkdir -p "$fake/bin"
  cp "$repo/bin/isolate" "$repo/bin/sandbox-check" "$fake/bin/"
  echo '{"agentIsolation":"required"}' > "$fake/settings.json"
  if HATCHLYBOX_HOME=$fake HATCHLYBOX_CACHE=$w/isolation "$fake/bin/isolate" build "$APPS/demo" true; then fail 'required isolation silently bypassed'; fi
fi
ok 'sandbox enforcement probe and fail-closed required mode'
# Interrupted legacy activation restores a complete original vault.
DATA=$w/data; VAULT=$DATA/vault; mkdir -p "$DATA/vault.previous"
echo old > "$DATA/vault.previous/key"
: > "$DATA/.vault-activating"
recover_vault
[ "$(cat "$VAULT/key")" = old ] || fail 'vault recovery'
ok 'legacy vault activation recovery'
# Rotation succeeds as a complete pointer switch; old passphrase remains valid on backup only.
(
 VP=old-test-passphrase
 printf hatchlybox-vault > "$w/check"
 vault_enc "$w/check" check
 printf 'fake publishing secret' > "$w/secret"
 vault_enc "$w/secret" key
 new_pass() { VP=new-test-passphrase; }
 rotate_vault
 [ -L "$VAULT" ] || fail 'vault not activated atomically'
 VP=new-test-passphrase; vault_check || fail 'new passphrase'
 [ "$(vault_dec key -)" = 'fake publishing secret' ] || fail 'rotated key bytes'
 VAULT=$DATA/vault.previous VP=old-test-passphrase; vault_check || fail 'previous vault corrupted'
)
ok 'transactional vault rotation and retained recovery copy'
# Inject encryption failure: active vault stays readable with the old passphrase.
(
 VAULT=$DATA/vault VP=new-test-passphrase
 new_pass() { VP=third-test-passphrase; }
 vault_put() { return 1; }
 if rotate_vault; then fail 'failed rotation succeeded'; fi
 VAULT=$DATA/vault VP=new-test-passphrase
 vault_check || fail 'failed rotation damaged active vault'
)
ok 'failed rotation preserves active vault'
(
  mkdir -p "$w/backup-source" "$w/backup-keys" "$w/artifacts"
  echo '{"slug":"demo","pkg":"com.example"}' > "$w/backup-source/.hatchlybox.json"
  echo 'source bytes' > "$w/backup-source/Main.kt"
  ln -s /etc/passwd "$w/backup-source/external-link"
  java -Xmx96m "$repo/bin/Backup.java" create "$w/test.zip" project "$w/backup-source" keys "$w/backup-keys" artifacts "$w/artifacts"
  java -Xmx96m "$repo/bin/Backup.java" extract "$w/test.zip" "$w/unpacked"
  cmp "$w/backup-source/Main.kt" "$w/unpacked/project/Main.kt"
  [ ! -e "$w/unpacked/project/external-link" ] || fail 'backup followed external symlink'
)
ok 'portable backup roundtrip excludes external links'
(
  DATA=$repo
  KEYS=$w/signing; mkdir -p "$KEYS"
  printf test-signing-passphrase > "$KEYS/demo.pass"
  KS_PASS=$(cat "$KEYS/demo.pass") keytool -genkeypair -keystore "$KEYS/demo.p12" -storetype PKCS12 -storepass:env KS_PASS -keypass:env KS_PASS -alias upload -keyalg RSA -keysize 2048 -validity 1 -dname 'CN=Test, O=Hatchlybox' >/dev/null 2>&1
  mkdir -p "$APPS/demo/app/build/outputs/bundle/release"
  echo content > "$w/content.txt"
  (cd "$w" && jar --create --file "$APPS/demo/app/build/outputs/bundle/release/app-release.aab" content.txt)
  validate_project() { return 0; }; do_bundle_check() { return 0; }; pmeta() { :; }; artifact_record() { :; }
  PLAY_VC=1 PLAY_VN=1.0
  do_bundle demo || fail 'separate bundle signing'
  [ "$(bundle_certificate "$CACHE/apks/demo.aab")" = "$(key_certificate demo)" ] || fail 'certificate identity'
  jarsigner -verify "$CACHE/apks/demo.aab" >/dev/null 2>&1 || fail 'signed bundle verification'
)
ok 'bundle signing verifies expected certificate and signature'

(
  CACHE=$w/artifact-cache; mkdir -p "$CACHE/apks"
  printf '{"slug":"demo","pkg":"com.example"}' > "$APPS/demo/.hatchlybox.json"
  printf apk-bytes > "$CACHE/apks/demo.apk"
  artifact_record demo apk "$CACHE/apks/demo.apk" fixture-cert
  artifact_ok demo apk "$CACHE/apks/demo.apk" || fail 'fresh artifact rejected'
  printf 'manual edit' >> "$APPS/demo/Main.kt"
  if artifact_ok demo apk "$CACHE/apks/demo.apk"; then fail 'stale artifact accepted'; fi
)
ok 'artifact receipt rejects source changed outside the agent'
(
  c=$w/worker-cache; a=$w/worker-apps
  mkdir -p "$a/demo/app" "$c"
  printf '{"slug":"demo","pkg":"com.example","label":"Demo","updated":1,"history":[]}' > "$a/demo/.hatchlybox.json"
  printf 'namespace = "com.example"\napplicationId = "com.example"\nisMinifyEnabled = false\n' > "$a/demo/app/build.gradle.kts"
  printf '#!/usr/bin/env bash\nsleep 2\necho simulated-compiler-failure >&2\nexit 1\n' > "$a/demo/gradlew"
  chmod +x "$a/demo/gradlew"
  HATCHLYBOX_TEST=0 HATCHLYBOX_HOME=$repo HATCHLYBOX_CACHE=$c HATCHLYBOX_APPS=$a "$repo/bin/hatchlybox" build demo
  if HATCHLYBOX_TEST=0 HATCHLYBOX_HOME=$repo HATCHLYBOX_CACHE=$c HATCHLYBOX_APPS=$a "$repo/bin/hatchlybox" build demo 2>/dev/null; then fail 'second worker admitted'; fi
  for _ in $(seq 100); do
    phase=$(jq -r '.phase' "$c/job.json")
    [ "$phase" != queued ] && [ "$phase" != building ] && break
    sleep .1
  done
  [ "$phase" = failed ] || fail "worker result not retained: $phase"
  id=$(jq -r .id "$c/job.json")
  [ -f "$c/jobs/$id/job.json" ] && grep -q simulated-compiler-failure "$c/jobs/$id/log.txt" || fail 'per-job history missing'
)
ok 'job admission serializes workers and retains failure history'

(
  CACHE=$w/stale; JOB=$CACHE/job.json; LOG=$CACHE/log.txt; mkdir -p "$CACHE/jobs"
  echo '{"phase":"agent","slug":"demo","started":1,"updated":1,"pid":0}' > "$JOB"
  echo old-log > "$LOG"
  recover_stale_job
  [ "$(jq -r .phase "$CACHE/job.json")" = failed ] || fail 'dead legacy worker stayed active'
  [ -f "$CACHE/jobs/legacy-1/log.txt" ] || fail 'legacy history missing'
)
ok 'stale legacy worker is archived and made retryable'
(
  # A worker stopped by a signal is "interrupted", not failed, and the health check carries it on.
  CACHE=$w/interrupt; APPS=$w/interrupt-apps; mkdir -p "$CACHE/jobs/j1" "$APPS/demo"
  echo '{"slug":"demo"}' > "$APPS/demo/.hatchlybox.json"
  JOB_ID=j1; echo '{"id":"j1","kind":"app","phase":"agent","slug":"demo","agent":"claude","started":1,"updated":1,"pid":0}' > "$CACHE/jobs/j1/job.json"
  cp "$CACHE/jobs/j1/job.json" "$CACHE/job.json"; : > "$CACHE/jobs/j1/log.txt"
  stopped() { kill -TERM "$BASHPID"; sleep 5; }
  ( worker_run stopped ) || true
  JOB=$CACHE/job.json
  [ "$(jq -r .phase "$JOB")" = interrupted ] || fail "stopped worker not interrupted: $(jq -c . "$JOB")"
  # Within 30 seconds of being stopped (Cancel may still be on its way) it waits.
  recover_stale_job
  [ "$(jq -r .phase "$JOB")" = interrupted ] || fail 'interrupted job resumed too soon'
  # (In a subshell $$ is this test, so the recorded pid looks alive: clear it, as a real worker's would be dead.)
  json_edit "$CACHE/jobs/j1/job.json" '.updated=1 | .pid=0'; cp "$CACHE/jobs/j1/job.json" "$JOB"
  recover_stale_job
  [ "$(jq -r .msg "$JOB")" = "stopped before it finished; carrying on (1/3)" ] || fail "interrupted job not resumed: $(jq -c . "$JOB")"
)
ok 'a worker stopped by a signal carries on after the health check'
(
  # A usage limit is said in words, with when it resets, and kept for the front end.
  CACHE=$w/limit; mkdir -p "$CACHE"; JOB=$CACHE/job.json; LOG=$CACHE/log.txt
  echo '{"phase":"agent"}' > "$JOB"
  printf '== claude: prompt\nYou'"'"'ve hit your session limit · resets 4am (UTC)\nagent failed with exit 1; see its output above\n' > "$LOG"
  AGENT_LOG_FROM=1
  m=$(agent_failure claude 1)
  [[ $m == "Claude Code has reached its usage limit (it resets 4am (UTC))"* ]] || fail "limit message: $m"
  [ "$(jq -r .limit.agent "$JOB")" = claude ] && [ "$(jq -r .limit.resets "$JOB")" = "resets 4am (UTC)" ] || fail "limit not kept: $(jq -c . "$JOB")"
  printf '== codex: prompt\nerror: something else broke\n' > "$LOG"; echo '{"phase":"agent"}' > "$JOB"
  m=$(agent_failure codex 1)
  [[ $m == "Codex stopped with an error (1)"* ]] && [ "$(jq -r '.limit // empty' "$JOB")" = "" ] || fail "plain failure: $m"
  [[ $(agent_failure opencode 124) == "OpenCode ran out of time"* ]] || fail 'timeout message'
)
ok 'agent usage limits and failures are explained in words'
(
  DATA=$w/backup-runtime; VAULT=$w/unused-vault; KEYS=$w/backup-keys
  mkdir -p "$DATA/template" "$KEYS"
  ln -s "$repo/bin" "$DATA/bin"
  printf 'sdk.dir=/opt/android-sdk\n' > "$DATA/template/local.properties"
  printf 'org.gradle.workers.max=1\n' > "$DATA/template/gradle.properties"
  printf '#!/bin/sh\nexit 0\n' > "$APPS/demo/gradlew"
  chmod +x "$APPS/demo/gradlew"
  printf 'fixture-passphrase\n' | project_backup demo "$w/project.enc"
  printf 'fixture-passphrase\n' | project_restore recovered "$w/project.enc"
  cmp "$APPS/demo/Main.kt" "$APPS/recovered/Main.kt"
  [ -x "$APPS/recovered/gradlew" ] || fail 'restored wrapper lost executable permission'
  [ "$(jq -r .slug "$APPS/recovered/.hatchlybox.json")" = recovered ] || fail 'restored metadata identity'
)
ok 'encrypted full-project backup and restore roundtrip'
(
  CACHE=$w/discard-cache; APPS=$w/discard-apps; mkdir -p "$CACHE/apks" "$APPS/demo/app/src/main/res/values"
  d=$APPS/demo
  git -C "$d" init -q
  hygiene "$d"
  printf baseline > "$d/Main.kt"
  printf '<resources><string name="app_name">Before</string></resources>\n' > "$d/app/src/main/res/values/strings.xml"
  gq "$d" add -A; gq "$d" commit -qm baseline
  base=$(git -C "$d" branch --show-current)
  git -C "$d" checkout -qb change/test
  printf broken > "$d/Main.kt"
  jq -nc --arg base "$base" '{slug:"demo",label:"Broken",status:"failed",updated:1,history:[{t:2,prompt:"fixture"}],pending:{branch:"change/test",base:$base,t:1,built:false}}' > "$d/.hatchlybox.json"
  printf apk > "$CACHE/apks/demo.main.apk"
  discard_change demo
  [ "$(cat "$d/Main.kt")" = baseline ] || fail 'discard did not restore tracked source'
  [ "$(git -C "$d" branch --show-current)" = "$base" ] || fail 'discard did not return to base'
  jq -e '.pending == null and .outcomes.build=="needs-rebuild"' "$d/.hatchlybox.json" >/dev/null || fail 'legacy discard metadata'
  [ ! -f "$d/.hatchlybox.json.lock" ] || fail 'metadata lock polluted project'
)
ok 'real Git wrappers and failed legacy change discard'

(
  DATA=$repo
  meta() { :; }; agent_budget() { return 0; }; protected_id() { echo fixed; }
  run_agent_impl() {
    [[ $3 == *'do not run Gradle'* || $3 == *'Do not run Gradle'* ]] || fail 'managed agent not told to return before build'
    [[ $3 == *'original request fixture'* ]] || fail 'managed prompt lost request'
    return 0
  }
  run_agent mock "$APPS/demo" 'original request fixture'
)
ok 'managed agent returns edits before backend build'

echo 'All regression checks passed.'
