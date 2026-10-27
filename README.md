<p align="center"><img src="docs/logo.svg" alt="Hatchlybox" width="96"></p>

<h1 align="center">Hatchlybox</h1>

<p align="center"><b>Say it. Hatch it.</b><br>Describe an app or a game, and AI builds it, installs it and keeps it in one library across all your devices.</p>

<p align="center">
  <a href="#install">Install</a> ·
  <a href="#how-it-works">How it works</a> ·
  <a href="https://github.com/HatchlyBox/hatchlybox-android">Android app</a> ·
  <a href="https://github.com/sponsors/HatchlyBox">Sponsor</a>
</p>

<p align="center">
  <a href="https://github.com/HatchlyBox/hatchlybox/releases"><img alt="Release" src="https://img.shields.io/github/v/release/HatchlyBox/hatchlybox?include_prereleases&color=56DCC9&labelColor=101828"></a>
  <a href="LICENSE"><img alt="Licence: AGPL 3.0" src="https://img.shields.io/badge/licence-AGPL%203.0-56DCC9?labelColor=101828"></a>
  <img alt="Platforms" src="https://img.shields.io/badge/runs%20on-Linux%20%7C%20macOS%20%7C%20Windows%20%7C%20Android-56DCC9?labelColor=101828">
  <a href="https://github.com/HatchlyBox/hatchlybox/discussions"><img alt="Discussions" src="https://img.shields.io/badge/questions-Discussions-56DCC9?labelColor=101828"></a>
</p>

---

Hatchlybox makes apps and games from what you describe, on Linux, macOS, Windows and Android. Type what you want,
such as *"a budget tracker with a pie chart"* or *"a neon racing game"*, and an AI helper (Claude Code, Codex or
OpenCode) writes it, builds it and installs it on your computer. Ask for changes the same way. Make the same creation
for another system, send it to your phone, and keep everything in one library, synced across all your devices.

No Hatchlybox account, no analytics, no server of ours in between. The AI helper runs under **your own** account.

## Install

Paste one line, or download one file. Either installs everything Hatchlybox needs (your password is asked once), a
free AI helper when you have none, and opens Hatchlybox.

**Linux** (Arch/Omarchy, Debian, Ubuntu, Fedora):
```sh
curl -fsSL https://github.com/HatchlyBox/hatchlybox/releases/latest/download/hatchlybox-linux-install.sh | bash
```
**macOS** 12 or later, in Terminal:
```sh
curl -fsSL https://github.com/HatchlyBox/hatchlybox/releases/latest/download/hatchlybox-macos-install.command | bash
```
**Windows** 10 or 11, in PowerShell:
```powershell
irm https://github.com/HatchlyBox/hatchlybox/releases/latest/download/hatchlybox-windows-install.ps1 | iex
```

**Or one file** from the [latest release](../../releases/latest):

| System | File | Run it |
| --- | --- | --- |
| Linux | `hatchlybox-linux-install.sh` | `bash hatchlybox-linux-install.sh` |
| macOS | `hatchlybox-macos-install.command` | `bash hatchlybox-macos-install.command` in Terminal |
| Windows | `hatchlybox-windows-install.ps1` | right-click it, **Run with PowerShell** |

**Android:** [Hatchlybox for Android](https://github.com/HatchlyBox/hatchlybox-android/releases/latest).

Run it again to update: creations, keys and settings stay. `SHA256SUMS` in the release checks a download
(`sha256sum -c SHA256SUMS`). macOS gets its tools from Homebrew (installed if missing); Windows runs Hatchlybox in
WSL (installed if missing, after one restart). From a checkout instead: `./install.sh [linux|macos]`, or
`install-windows.ps1` on Windows.

## How it works

Hatchlybox opens like an app from your app menu, Launchpad or Start menu, as a page in your browser. Only you can
open it: it runs on your computer, and nothing else on the network or the web can reach it.

1. **Create.** Describe what you want and pick what it is: *Auto*, a web app, an Android app, a game, or an app for
   this computer. Hatchlybox makes it, builds it and shows you the result. *Tasks* shows what it's doing while it
   works, and you can stop it anytime.
2. **Change it.** Open a creation in the *Library* and say what to change: "make the buttons bigger", "add a
   leaderboard". Each change is made, built and tried again.
3. **Make it for another system.** Any creation can get its Linux, macOS, Windows, web or Android version, made from
   its newest one.
4. **Send it to your phone.** An Android version installs on your phone with a QR code, or straight over Wi-Fi once the
   phone is connected (*Settings › Phone*).
5. **Sync your devices.** *Devices* pairs this computer with your phone or another computer, once, with a code. After
   that they keep each other's library up to date by themselves, end-to-end encrypted, directly between your devices.

**Settings** has the rest: which AI helper to use (and carrying on with another when one hits its usage limit), Android
building and Godot for games (both set up when first needed), GitHub and Google Play if you want them, backups of your
creations, and safety.

## Features

- **Apps and games from plain words**, built and installed for you. No coding.
- **Games with Godot**: 2D and 3D, exported for Linux, macOS, Windows and Android.
- **One creation, every system**, kept in one library.
- **Your choice of AI helper**: Claude Code, Codex or OpenCode (free models included), with your own account.
- **Safe by default**: on computers, AI helpers and builds run in a sandbox. They see only the creation they're
  working on, never your files, your keys or your other creations.
- **Sync across devices**, phones and computers, with no cloud of ours.
- **GitHub and Google Play, if you want**: a private repository per creation, and publishing to the Play Store.
- **Backups** of your creations, and restoring them.

## Privacy

Nothing is sent to us. When an AI helper works, your request and the creation's files go to that helper's company
(Anthropic, OpenAI, or OpenCode's provider), under your account and their terms. Sync goes directly between your
devices, encrypted. GitHub and Google Play only when you connect them.

## Support Hatchlybox

Hatchlybox is free, with no ads and no tracking. If it's useful to you, [sponsor it](https://github.com/sponsors/HatchlyBox):
sponsorships pay for its development.

## Contributing

Bug reports, ideas and pull requests are welcome: see [CONTRIBUTING.md](CONTRIBUTING.md), and the
[Contributor Licence Agreement](CLA.md) for code. How Hatchlybox is built inside: [docs/architecture.md](docs/architecture.md).
Tests: `for t in tests/*.sh; do bash "$t"; done`. Security problems: [SECURITY.md](SECURITY.md), please not as a public issue. Everyone here follows the [code of conduct](CODE_OF_CONDUCT.md). Questions: [Discussions](https://github.com/HatchlyBox/hatchlybox/discussions).

## Licence

Free software under the [GNU AGPL 3.0](LICENSE). The Hatchlybox name and logo are not covered by the licence.
