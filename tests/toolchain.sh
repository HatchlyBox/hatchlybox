#!/usr/bin/env bash
# The Android toolchain adapter (android.sh): the right downloads and build-tools for each system, Java 17 found
# where each system keeps it, Gradle tuned for a phone or a computer (the phones' settings unchanged), and
# `hatchlybox toolchain`. Systems are simulated with a uname that says what they are.
set -euo pipefail
repo=$(cd "$(dirname "$0")/.." && pwd)
w=$(mktemp -d)
trap 'rm -rf "$w"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }
ok() { echo "PASS: $*"; }

# as <os> <machine> <code>: run code with android.sh loaded on that system (proot: PROOT=1).
as() {
  local d=$w/uname-$1-$2
  mkdir -p "$d"
  printf '#!/bin/sh\ncase "$1" in -s) echo %s ;; -m) echo %s ;; *) echo %s ;; esac\n' "$1" "$2" "$1" > "$d/uname"; chmod +x "$d/uname"
  PATH="$d:$PATH" bash -c 'under_proot() { [ "${PROOT:-}" = 1 ]; }; source "$0"; eval "$1"' "$repo/bin/android.sh" "$3"
}

# Which tools, from where, for each system.
[ "$(as Linux x86_64 'echo $(android_os)/$(android_arch)/$(android_tools_kind)')" = linux/x86_64/google ] || fail "x86_64 Linux"
[ "$(as Linux aarch64 'echo $(android_os)/$(android_arch)/$(android_tools_kind)')" = linux/arm64/arm64-build ] || fail "ARM Linux"
[ "$(as Darwin arm64 'echo $(android_os)/$(android_arch)/$(android_tools_kind)')" = macos/arm64/google ] || fail "Apple silicon"
[ "$(as Darwin x86_64 'echo $(android_tools_kind)')" = google ] || fail "Intel Mac"
[ "$(as Linux riscv64 'echo $(android_tools_kind)')" = none ] || fail "RISC-V: nothing runs"
[ "$(as Linux x86_64 'android_clt')" = "$(as Linux x86_64 'echo $CLT_LINUX_URL $CLT_LINUX_SHA')" ] || fail "Linux command-line tools"
[[ $(as Darwin arm64 'android_clt') == *commandlinetools-mac-*" "5673201e* ]] || fail "Mac command-line tools: $(as Darwin arm64 'android_clt')"
[ -z "$(as FreeBSD amd64 'android_clt')" ] || fail "no command-line tools for FreeBSD"
[[ $(as Darwin arm64 'android_sdk_dirs') == */Library/Android/sdk ]] || fail "Mac SDK place"
as Linux x86_64 'android_sdk_dirs' | grep -qx /usr/lib/android-sdk || fail "Debian's SDK place"
ok "each system's command-line tools, build-tools and SDK places"

# Java 17: the front end's choice first; a JAVA_HOME that isn't 17 is passed over.
jdk() { mkdir -p "$w/$1/bin"; printf '#!/bin/sh\necho "openjdk version \\"%s\\"" >&2\n' "$2" > "$w/$1/bin/java"; chmod +x "$w/$1/bin/java"
        [ -z "${3:-}" ] || echo "JAVA_VERSION=\"$2\"" > "$w/$1/release"; }
jdk j17 17.0.12 release; jdk j21 21.0.4 release; jdk j17bare 17.0.9
[ "$(HATCHLYBOX_JAVA_HOME=$w/j17 as Linux x86_64 'android_java_home')" = "$w/j17" ] || fail "HATCHLYBOX_JAVA_HOME"
as Linux x86_64 "java17 '$w/j17' && ! java17 '$w/j21' && java17 '$w/j17bare' && ! java17 '$w/none'" || fail "telling a 17 (release file, else java -version)"
[ "$(HATCHLYBOX_JAVA_HOME=$w/j21 JAVA_HOME=$w/j21 as Linux x86_64 'android_java_home || echo none')" != "$w/j21" ] || fail "a 21 taken for 17"
[[ $(as Darwin arm64 'android_java_hint') == "brew install openjdk@17" ]] || fail "Mac hint"
ok "Java 17 found, other versions passed over, an install hint per system"

# Gradle: a phone keeps exactly its old settings; a computer gets memory and workers for its size.
old="org.gradle.jvmargs=-Xmx1536m -XX:MaxMetaspaceSize=512m -Dfile.encoding=UTF-8
org.gradle.daemon=true
org.gradle.parallel=false
org.gradle.workers.max=2
org.gradle.caching=true
kotlin.compiler.execution.strategy=in-process
android.useAndroidX=true
android.nonTransitiveRClass=true
android.aapt2FromMavenOverride=/sdk/build-tools/35.0.0/aapt2
# AGP 8.7 knows API 35; 36 builds fine with it.
android.suppressUnsupportedCompileSdk=36"
[ "$(PROOT=1 HATCHLYBOX_MEMORY_MB=7600 as Linux aarch64 'android_gradle_props /sdk')" = "$old" ] || fail "phone settings changed"
[ "$(HATCHLYBOX_MEMORY_MB=3900 HATCHLYBOX_CPUS=4 as Linux aarch64 'android_gradle_props /sdk')" = "$old" ] || fail "a small ARM board builds like a phone"
p=$(HATCHLYBOX_MEMORY_MB=16000 HATCHLYBOX_CPUS=8 as Linux x86_64 'android_gradle_props /sdk')
grep -qx 'org.gradle.jvmargs=-Xmx4000m -XX:MaxMetaspaceSize=768m -Dfile.encoding=UTF-8' <<< "$p" && grep -qx org.gradle.parallel=true <<< "$p" \
  && grep -qx org.gradle.workers.max=4 <<< "$p" && ! grep -q aapt2FromMavenOverride <<< "$p" && ! grep -q in-process <<< "$p" || fail "x86_64 computer: $p"
p=$(HATCHLYBOX_MEMORY_MB=65000 HATCHLYBOX_CPUS=64 as Linux aarch64 'android_gradle_props /sdk')
grep -q 'Xmx6144m' <<< "$p" && grep -qx org.gradle.workers.max=8 <<< "$p" && grep -qx 'android.aapt2FromMavenOverride=/sdk/build-tools/35.0.0/aapt2' <<< "$p" || fail "ARM server: $p"
p=$(HATCHLYBOX_MEMORY_MB=8192 HATCHLYBOX_CPUS=2 as Darwin arm64 'android_gradle_props /sdk')
grep -q 'Xmx2048m' <<< "$p" && grep -qx org.gradle.workers.max=2 <<< "$p" && ! grep -q aapt2FromMavenOverride <<< "$p" || fail "small Mac: $p"
ok "Gradle: phones unchanged, computers sized (2–6 GB heap, 2–8 workers), aarch64 aapt2 only on ARM Linux"

# hatchlybox toolchain: one JSON object a front end can show.
mkdir -p "$w/data"; ln -s "$repo/bin" "$w/data/bin"
j=$(HATCHLYBOX_HOME=$w/data HATCHLYBOX_CACHE=$w/cache HATCHLYBOX_APPS=$w/apps HATCHLYBOX_MEMORY_MB=16000 HATCHLYBOX_CPUS=8 "$repo/bin/hatchlybox" toolchain)
[ "$(jq -r '[.os, .buildTools, (.aapt2Runs | type), (.memoryMB | tostring)] | join("|")' <<< "$j")" = "$(as "$(uname -s)" "$(uname -m)" 'echo $(android_os)')|35.0.0|boolean|16000" ] || fail "toolchain: $j"
ok "hatchlybox toolchain reports the system, tools, Java, SDK and build profile"
