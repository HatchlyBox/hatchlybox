# How Hatchlybox works

For developers and the agents working on Hatchlybox. Using it? See the [README](../README.md).

This is the engine behind Hatchlybox: a coding agent (Claude Code, Codex or OpenCode) makes what you describe, and
the engine builds it, installs it and keeps improving it on request.

The engine is the same on every platform. Each platform adds a small description of itself:

- `bin/`, `template/`, `skills/`, `creation/AGENTS.md` (the guide every creation gets), `visual/`: the engine (the `hatchlybox` command).
- `platforms/<name>/platform.env`: what differs per platform (ports, how agents run, what the front end
  offers). It's installed next to the engine as `platform.env`; `hatchlybox platform` prints it.
- One creation for every system: `hatchlybox create <system>` starts one on any system, `hatchlybox make <slug> <system>`
  makes it for another (from its newest version), changes it, or brings it up to date (`bin/systems.sh`).
- The library is creations: `hatchlybox creations` (and `$CACHE/creations.json`) lists each creation once, with a
  system for each build (Android from the app state, the others from `~/ports/<slug>/<system>`), "here" for the
  systems this platform installs (`INSTALLS`).
- Platforms: `hatchlybox` (the Hatchlybox Android app: `./sync-hatchlybox.sh [app folder]` copies the engine in),
  `linux`, `macos` and `windows` (computers, below).

On a computer: `./install.sh [linux|macos]` installs it for your user, with Hatchlybox in the app menu (Linux) or
`~/Applications/Hatchlybox.app` (macOS). On Windows, `install-windows.ps1` (PowerShell) sets up WSL's Linux, runs
`install.sh windows` there and adds Hatchlybox to the Start menu: the engine runs in WSL, Windows versions install on
the Windows side (`bin/here.sh`, `bin/win-shortcut`).

The desktop front end (`hatchlybox desktop`; `bin/desktop.sh`, `bin/Desk.java`, the page in `desktop/`): a local
server on 127.0.0.1 opens Hatchlybox in the browser: create with Auto, Web, Android, Game or this computer's kind,
the library with each version's actions (install here, open, send to the phone with a QR code, make for another
system, change), the current job with its log, the phone's wireless debugging, devices (sync), and settings (what's
missing to build, AI helpers, the sandbox). Signed in by a token per start; nothing else on the machine or the
web can use it.

Agents and builds run isolated (`bin/isolate`, `bin/sandbox-check`): bubblewrap on Linux and in WSL (a minimal
filesystem: the project, the agent's own login and program, never other creations, keys or the user's files),
sandbox-exec on macOS (writes only to the project and the agent's folders; secrets and other creations hidden).
Computers require it (`ISOLATION=required`: `hatchlybox doctor` names the package to install); the phones can't
isolate under proot and keep running as before. Games: Godot exports to every system, and `visual render --for
linux|macos|windows` judges a computer's version with Forward+ (software Vulkan in Xvfb, or the Mac's GPU).

Where things go is decided in one place, `bin/paths.sh`: the front end's `HATCHLYBOX_*` folders, else the
system's own places (XDG on Linux, `~/Library` on macOS, creations in `~/Hatchlybox`). `bin/compat.sh` gives every
script the same shell tools (GNU's, from Homebrew on macOS). Each platform's `environment.md` tells agents where
they run, in the projects' AGENTS.md.

Sync between the user's devices (`bin/sync.sh`, `bin/Sync.java`): `hatchlybox sync send` shows a code (and its QR
code), `hatchlybox sync receive <code>` on the other device; both end up with everything either made, and stay
paired. `hatchlybox sync serve` then syncs by itself with paired devices (on a computer `hatchlybox sync autostart on`).
Same Wi-Fi: found by a UDP broadcast. Different networks: a relay, `java bin/Relay.java <port>` on any server
both can reach, set with `hatchlybox set relay host:port`; it only passes encrypted bytes (SPAKE2 keys from the
code or the pair's key) and keeps nothing.

Releases: `release/make-installers.sh` makes the one-file installers for each computer system.

Tests: `for t in tests/*.sh; do bash $t; done`.
