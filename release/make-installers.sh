#!/usr/bin/env bash
# make-installers.sh [out dir]: one file per computer system that installs Hatchlybox with everything it needs, the
# engine (this checkout's HEAD) inside it, so nothing else has to be downloaded from us:
#   hatchlybox-linux-install.sh       Arch/Omarchy, Debian, Ubuntu, Fedora     bash hatchlybox-linux-install.sh
#   hatchlybox-macos-install.command  macOS 12 or later (Homebrew)             bash hatchlybox-macos-install.command
#   hatchlybox-windows-install.ps1    Windows 10/11 (WSL)                      right-click › Run with PowerShell
# Each also runs as one line straight from the latest release (curl ... | bash, irm ... | iex): see README.md.
# They install the system's packages (asking for the password once), the engine with its launcher, a free AI helper
# (OpenCode) when there's none, and open Hatchlybox. Android's tools (about 1 GB) aren't in them: Hatchlybox offers
# them when an Android app is first wanted. Also writes SHA256SUMS for the three.
set -euo pipefail
cd "$(dirname "$0")/.."
out=${1:-.}
mkdir -p "$out"
url=https://github.com/HatchlyBox/hatchlybox/releases/latest/download
payload=$(git archive --format=tar.gz --prefix=hatchlybox-engine/ HEAD | base64 -w 76)

# ---- Linux ------------------------------------------------------------------------------------------------------
{
cat <<HEAD
#!/usr/bin/env bash
# Hatchlybox for Linux: installs everything Hatchlybox needs, then opens it. Run it as yourself (not root):
#   bash hatchlybox-linux-install.sh
# or, in one line:
#   curl -fsSL $url/hatchlybox-linux-install.sh | bash
HEAD
cat <<'HEAD'
set -euo pipefail
say() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
# All in one function: with curl | bash, nothing runs before the whole script has arrived.
main() {
[ "$(id -u)" != 0 ] || { echo "Run this as yourself, not as root: it asks for the password when it needs it."; exit 1; }
[ "$(uname -s)" = Linux ] || { echo "This installer is for Linux."; exit 1; }

say "Installing what Hatchlybox needs (your password may be asked once)"
if command -v pacman >/dev/null; then
  sudo pacman -S --needed --noconfirm git jq curl unzip zip python jdk17-openjdk bubblewrap android-tools github-cli
elif command -v apt-get >/dev/null; then
  sudo apt-get update -qq && sudo apt-get install -y -qq git jq curl unzip zip python3 openjdk-17-jdk-headless bubblewrap adb gh
elif command -v dnf >/dev/null; then
  sudo dnf install -y git jq curl unzip zip python3 java-17-openjdk-devel bubblewrap android-tools gh
else
  echo "Install these with your system's package manager, then run this again: git jq curl unzip zip python3, a JDK 17, bubblewrap, adb"
  exit 1
fi

say "Installing Hatchlybox"
src=$(mktemp -d)
trap 'rm -rf "$src"' EXIT
base64 -d <<'PAYLOAD' | tar -xz -C "$src"
HEAD
printf '%s\n' "$payload"
cat <<'TAIL'
PAYLOAD
bash "$src/hatchlybox-engine/install.sh" linux
export PATH="$HOME/.local/bin:$PATH"

if ! command -v opencode >/dev/null && ! command -v claude >/dev/null && ! command -v codex >/dev/null \
   && [ ! -x "$HOME/.opencode/bin/opencode" ]; then
  say "Adding a free AI helper (OpenCode)"
  curl -fsSL https://opencode.ai/install | bash || echo "OpenCode didn't install: Hatchlybox's Settings can do it later."
fi

# Phones on the same Wi-Fi download apps from here, and devices find each other to sync.
if command -v ufw >/dev/null && sudo ufw status 2>/dev/null | grep -q "Status: active"; then
  say "Letting your phone reach Hatchlybox through the firewall"
  sudo ufw allow 8765/tcp >/dev/null && sudo ufw allow 47197:47199/udp >/dev/null && sudo ufw allow 47197:47199/tcp >/dev/null
fi

say "Opening Hatchlybox"
"$HOME/.local/bin/hatchlybox" desktop || true
echo
echo "Done. Hatchlybox is in your app launcher. To sign in to Claude or Codex instead of OpenCode's free models,"
echo "open Hatchlybox's Settings. Android apps need a one-time setup, offered when you first make one."
}
main "$@"
TAIL
} > "$out/hatchlybox-linux-install.sh"

# ---- macOS ------------------------------------------------------------------------------------------------------
# macOS's own bash is 3.2: this file keeps to what it has, and runs install.sh with Homebrew's bash.
{
cat <<HEAD
#!/bin/bash
# Hatchlybox for macOS: installs everything Hatchlybox needs (with Homebrew), then opens it. Run it as yourself:
#   bash hatchlybox-macos-install.command        (in Terminal; or right-click › Open in Finder)
# or, in one line:
#   curl -fsSL $url/hatchlybox-macos-install.command | bash
HEAD
cat <<'HEAD'
set -euo pipefail
say() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
# All in one function: with curl | bash, nothing runs before the whole script has arrived.
main() {
[ "$(id -u)" != 0 ] || { echo "Run this as yourself, not as root: it asks for the password when it needs it."; exit 1; }
[ "$(uname -s)" = Darwin ] || { echo "This installer is for macOS."; exit 1; }

for b in /opt/homebrew/bin/brew /usr/local/bin/brew; do
  command -v brew >/dev/null || { [ -x "$b" ] && eval "$("$b" shellenv)"; } || true
done
if ! command -v brew >/dev/null; then
  say "Installing Homebrew, which installs the tools Hatchlybox uses (your password is asked)"
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" < /dev/tty
  for b in /opt/homebrew/bin/brew /usr/local/bin/brew; do [ -x "$b" ] && eval "$("$b" shellenv)" && break; done
  command -v brew >/dev/null || { echo "Homebrew didn't install. Install it from https://brew.sh, then run this again."; exit 1; }
fi

say "Installing what Hatchlybox needs"
brew install bash git jq curl unzip zip coreutils gnu-sed findutils grep gawk flock openjdk@17 android-platform-tools gh

say "Installing Hatchlybox"
src=$(mktemp -d)
trap 'rm -rf "$src"' EXIT
base64 --decode <<'PAYLOAD' | tar -xz -C "$src"
HEAD
printf '%s\n' "$payload"
cat <<'TAIL'
PAYLOAD
"$(brew --prefix)/bin/bash" "$src/hatchlybox-engine/install.sh" macos
export PATH="$HOME/.local/bin:$PATH"

if ! command -v opencode >/dev/null && ! command -v claude >/dev/null && ! command -v codex >/dev/null \
   && [ ! -x "$HOME/.opencode/bin/opencode" ]; then
  say "Adding a free AI helper (OpenCode)"
  curl -fsSL https://opencode.ai/install | bash || echo "OpenCode didn't install: Hatchlybox's Settings can do it later."
fi

say "Opening Hatchlybox"
"$HOME/.local/bin/hatchlybox" desktop || true
echo
echo "Done. Hatchlybox is in ~/Applications (Launchpad, Spotlight). If macOS asks whether Java may accept incoming"
echo "connections, allow it: that's how your phone downloads apps and syncs. To sign in to Claude or Codex instead of"
echo "OpenCode's free models, open Hatchlybox's Settings."
}
main "$@"
TAIL
} > "$out/hatchlybox-macos-install.command"

# ---- Windows ----------------------------------------------------------------------------------------------------
# PowerShell, through WSL: the engine goes into WSL's Linux, unpacked there so its scripts keep Linux line endings.
# Everything runs inside one script block, so `irm | iex` never closes the window (return, not exit).
{
cat <<HEAD
# Hatchlybox for Windows: installs WSL's Linux if needed, everything Hatchlybox needs in it, and adds Hatchlybox to the
# Start menu. Right-click this file, then Run with PowerShell, or in PowerShell:
#   powershell -ExecutionPolicy Bypass -File hatchlybox-windows-install.ps1
# or, in one line:
#   irm $url/hatchlybox-windows-install.ps1 | iex
# Another Linux than WSL's default: set \$env:HATCHLYBOX_DISTRO = "Ubuntu-24.04" first.
HEAD
cat <<'HEAD'
& {
$ErrorActionPreference = "Stop"
$Distro = $env:HATCHLYBOX_DISTRO
function Say($t) { Write-Host "`n==> $t" -ForegroundColor Cyan }
function Wsl([string[]]$a) { if ($Distro) { & wsl.exe -d $Distro @a } else { & wsl.exe @a } }

# 1. WSL and a Linux in it.
& wsl.exe --status *> $null
if ($LASTEXITCODE -ne 0) {
  Say "Installing WSL, Windows' Linux (Windows asks for permission)"
  Start-Process wsl.exe -ArgumentList "--install", "-d", "Ubuntu" -Verb RunAs -Wait
  Write-Host "Restart Windows, open Ubuntu from the Start menu once to choose a user name and password, then run this installer again."
  return
}
$list = (& wsl.exe -l -q) -replace "`0", "" | Where-Object { $_.Trim() -ne "" }
if (-not $list) {
  Say "Installing Ubuntu in WSL"
  & wsl.exe --install -d Ubuntu
  Write-Host "Finish Ubuntu's setup (a user name and password) in the window it opened, then run this installer again."
  return
}
if (-not $Distro) { $Distro = ($list | Select-Object -First 1).Trim() }
Write-Host "Hatchlybox goes into WSL's $Distro."

# 2. What the engine needs there (asks for the Linux password once).
Say "Installing Java 17, bubblewrap and the tools Hatchlybox uses (your Linux password may be asked)"
Wsl @("bash", "-lc", "if command -v apt-get >/dev/null; then sudo apt-get update -qq && sudo apt-get install -y -qq git jq curl unzip zip python3 openjdk-17-jdk-headless bubblewrap ca-certificates gh; elif command -v dnf >/dev/null; then sudo dnf install -y git jq curl unzip zip python3 java-17-openjdk-devel bubblewrap gh; else echo 'Install git jq curl unzip zip python3, a JDK 17 and bubblewrap with your Linux, then run this again.'; exit 1; fi")
if ($LASTEXITCODE -ne 0) { Write-Host "The tools didn't install: see above."; return }

# 3. The engine, unpacked inside Linux.
Say "Installing Hatchlybox"
$payload = @'
HEAD
printf '%s\n' "$payload"
cat <<'TAIL'
'@
$tgz = Join-Path $env:TEMP "hatchlybox-engine.tar.gz"
[IO.File]::WriteAllBytes($tgz, [Convert]::FromBase64String(($payload -replace "\s", "")))
$ltgz = (Wsl @("wslpath", "-a", "-u", $tgz)).Trim()
$src = '$HOME/.cache/hatchlybox-install/hatchlybox-engine'
Wsl @("bash", "-lc", "rm -rf ~/.cache/hatchlybox-install && mkdir -p ~/.cache/hatchlybox-install && tar -xzf '$ltgz' -C ~/.cache/hatchlybox-install")
Remove-Item $tgz -Force
if ($LASTEXITCODE -ne 0) { Write-Host "Hatchlybox couldn't be unpacked in $Distro."; return }
Wsl @("bash", "-lc", "cd `"$src`" && HATCHLYBOX_NO_LAUNCHER=1 ./install.sh windows")
if ($LASTEXITCODE -ne 0) { Write-Host "Hatchlybox didn't install: see above."; return }

# 4. A free AI helper, when there's none.
Wsl @("bash", "-lc", "command -v opencode >/dev/null || command -v claude >/dev/null || command -v codex >/dev/null || [ -x ~/.opencode/bin/opencode ] || { echo 'Adding a free AI helper (OpenCode)'; curl -fsSL https://opencode.ai/install | bash; }")

# 5. Phones on the Wi-Fi reach WSL only with mirrored networking (Windows 11 22H2 or later).
$cfg = Join-Path $env:USERPROFILE ".wslconfig"
$text = if (Test-Path $cfg) { Get-Content $cfg -Raw } else { "" }
if ($text -notmatch "(?m)^\s*networkingMode\s*=") {
  $a = Read-Host "Let phones on your Wi-Fi download apps from Hatchlybox? This turns on WSL's mirrored networking and restarts WSL. [Y/n]"
  if ($a -eq "" -or $a -match "^[Yy]") {
    if ($text -match "(?m)^\[wsl2\]") { $text = $text -replace "(?m)^\[wsl2\]\s*$", "[wsl2]`r`nnetworkingMode=mirrored" }
    else { $text = $text.TrimEnd() + "`r`n[wsl2]`r`nnetworkingMode=mirrored`r`n" }
    Set-Content -Path $cfg -Value $text.TrimStart() -NoNewline
    & wsl.exe --shutdown
    Write-Host "Mirrored networking is on."
  }
}

# 6. The Start menu: Hatchlybox runs hidden in WSL while its page is open in the browser.
$dir = Join-Path $env:LOCALAPPDATA "Hatchlybox"
New-Item -ItemType Directory -Force -Path $dir | Out-Null
$ico = (Wsl @("bash", "-lc", "wslpath -w `"$src/desktop/icon.ico`"")).Trim()
Copy-Item $ico (Join-Path $dir "icon.ico") -Force
$menu = Join-Path ([Environment]::GetFolderPath("Programs")) "Hatchlybox.lnk"
$s = (New-Object -ComObject WScript.Shell).CreateShortcut($menu)
$s.TargetPath = "powershell.exe"
$s.Arguments = "-NoProfile -WindowStyle Hidden -Command `"wsl.exe -d '$Distro' -e bash -lc '~/.local/bin/hatchlybox desktop --wait'`""
$s.IconLocation = (Join-Path $dir "icon.ico")
$s.Description = "Describe an app or a game: Hatchlybox makes it"
$s.WindowStyle = 7
$s.Save()

Say "Opening Hatchlybox"
Start-Process $menu
Write-Host "Done: Hatchlybox is in the Start menu. To sign in to Claude or Codex instead of OpenCode's free models, open its Settings."
}
TAIL
} > "$out/hatchlybox-windows-install.ps1"
# Windows' PowerShell reads a file without a BOM as the system's code page, and the script is plain ASCII, so that's
# fine; CRLF line endings keep Notepad and older PowerShell happy.
sed -i 's/$/\r/' "$out/hatchlybox-windows-install.ps1"

chmod +x "$out/hatchlybox-linux-install.sh" "$out/hatchlybox-macos-install.command"
(cd "$out" && sha256sum hatchlybox-linux-install.sh hatchlybox-macos-install.command hatchlybox-windows-install.ps1 > SHA256SUMS)
for f in hatchlybox-linux-install.sh hatchlybox-macos-install.command hatchlybox-windows-install.ps1; do
  echo "$out/$f ($(du -h "$out/$f" | cut -f1))"
done
echo "from $(git rev-parse --short HEAD)"
