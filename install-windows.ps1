# install-windows.ps1: Hatchlybox on Windows. Hatchlybox Engine runs in WSL (Linux inside Windows); this installs what it
# needs there, runs install.sh in it, and adds Hatchlybox to the Start menu. Run it from this folder in PowerShell:
#   powershell -ExecutionPolicy Bypass -File install-windows.ps1 [-Distro Ubuntu]
# Best: clone the engine inside WSL (\\wsl$\...), so its scripts keep Linux line endings.
param([string]$Distro = "")
$ErrorActionPreference = "Stop"

function Say($t) { Write-Host $t }
function Wsl([string[]]$a) { if ($Distro) { & wsl.exe -d $Distro @a } else { & wsl.exe @a } }

# 1. WSL itself.
& wsl.exe --status *> $null
if ($LASTEXITCODE -ne 0) {
  Say "WSL isn't installed. In PowerShell as administrator run:  wsl --install"
  Say "Restart Windows, finish Ubuntu's setup (a user name and password), then run this again."
  exit 1
}
$list = (& wsl.exe -l -q) -replace "`0", "" | Where-Object { $_.Trim() -ne "" }
if (-not $list) { Say "WSL has no Linux yet. Run:  wsl --install -d Ubuntu   then run this again."; exit 1 }
if (-not $Distro) { $Distro = ((& wsl.exe -l -q) -replace "`0", "" | Where-Object { $_.Trim() -ne "" } | Select-Object -First 1).Trim() }
Say "Hatchlybox goes into WSL's $Distro."

# 2. This folder as seen from Linux, with Linux line endings.
$here = (Wsl @("wslpath", "-a", "-u", $PSScriptRoot)).Trim()
Wsl @("bash", "-c", "cd '$here' && ! grep -lq `$'\r' install.sh bin/hatchlybox") | Out-Null
if ($LASTEXITCODE -ne 0) {
  Say "This copy has Windows line endings (git's core.autocrlf). Clone it inside WSL instead:"
  Say "  wsl git clone <the engine's address> ~/hatchlybox-engine   then run ~/hatchlybox-engine/install-windows.ps1 from \\wsl$\$Distro\home\<you>\hatchlybox-engine"
  exit 1
}

# 3. What the engine needs in Linux (asks for the Linux password once).
Say "Installing Java 17, bubblewrap and the tools Hatchlybox uses (your Linux password may be asked)..."
Wsl @("bash", "-lc", "if command -v apt-get >/dev/null; then sudo apt-get update -qq && sudo apt-get install -y -qq git jq curl unzip zip python3 openjdk-17-jdk-headless bubblewrap ca-certificates; elif command -v dnf >/dev/null; then sudo dnf install -y git jq curl unzip zip python3 java-17-openjdk-devel bubblewrap; else echo 'install git jq curl unzip zip python3, a JDK 17 and bubblewrap with your distribution'; fi")

# 4. The engine.
Wsl @("bash", "-lc", "cd '$here' && HATCHLYBOX_NO_LAUNCHER=1 ./install.sh windows")
if ($LASTEXITCODE -ne 0) { Say "install.sh failed: see above."; exit 1 }

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
    Say "Mirrored networking is on."
  }
}

# 6. The Start menu: Hatchlybox runs hidden in WSL while its page is open in the browser.
$dir = Join-Path $env:LOCALAPPDATA "Hatchlybox"
New-Item -ItemType Directory -Force -Path $dir | Out-Null
Copy-Item (Join-Path $PSScriptRoot "desktop\icon.ico") (Join-Path $dir "icon.ico") -Force
$menu = Join-Path ([Environment]::GetFolderPath("Programs")) "Hatchlybox.lnk"
$s = (New-Object -ComObject WScript.Shell).CreateShortcut($menu)
$s.TargetPath = "powershell.exe"
$s.Arguments = "-NoProfile -WindowStyle Hidden -Command `"wsl.exe -d '$Distro' -e bash -lc '~/.local/bin/hatchlybox desktop --wait'`""
$s.IconLocation = (Join-Path $dir "icon.ico")
$s.Description = "Describe an app or a game: Hatchlybox makes it"
$s.WindowStyle = 7
$s.Save()
Say "Done: Hatchlybox is in the Start menu. Open it; its Settings say what's left to set up."
