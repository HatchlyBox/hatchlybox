# Hatchlybox Engine: working on this repository

This file is for you, the agent working on the engine itself. (`creation/AGENTS.md` is a different file: the
guide every app Hatchlybox creates gets. Change it only when the change is meant for every creation's agent.)

## What this is

The engine behind Hatchlybox: the `hatchlybox` command (bash: `bin/hatchlybox` and the `bin/*.sh` it sources) with
Java helpers (`bin/Desk.java` the desktop page's server, `bin/Sync.java` sync and pairing), the app template
(`template/`), skills (`skills/`), the desktop page (`desktop/`), and one `platforms/<name>/platform.env` per
platform (the Android app `hatchlybox`, `linux`, `macos`, `windows`). README.md explains the layout.

## Rules

- Users don't code. Every message is plain words: what happened, and what to do next.
- Hatchlybox and its agents never use `sudo`. When the system needs something only the user can do, print the exact
  command for them.
- Nothing personal in code, tests, commits, issues or pull requests: no names, emails, tokens, keys, network
  addresses or paths from a machine. In logs you paste, write `/home/USER` and leave addresses out.
- Licences are never accepted for the user: the front ends show them and ask (`hatchlybox license`).
- On computers, agents and builds run in the sandbox (`bin/isolate`); keep a change working with `ISOLATION=required`.

## Testing

Each `tests/*.sh` is self-contained (its own temporary home; it never touches the user's files):

```
for t in tests/*.sh; do bash "$t" > /tmp/t.out 2>&1 || { echo "FAIL $t"; tail -5 /tmp/t.out; }; done
```

Run the ones for what you changed while working and all of them before a pull request. A new behaviour gets a test.

## Sending work to the maintainers

You may be working on someone's computer (an Omarchy laptop, a Mac) with `gh` signed in to the HatchlyBox
organization. Everything goes through GitHub for the maintainers to approve; nothing reaches `main` without it.

- **Never push to `main`, never merge, never force-push, never delete branches or tags you didn't make.**
- A problem or an idea: an issue.
  `gh issue create -R HatchlyBox/hatchlybox --template "Bug report"` (or `"Idea"`), with the template's sections
  filled in, and the label `from-agent` plus the device's (`linux`, `macos`, `windows`, `phone`).
- A change: a branch from an up-to-date `main` (`fix/...`, `idea/...`), commits that say what a user notices, the
  tests passing, then `gh pr create -R HatchlyBox/hatchlybox --fill-first --label from-agent` and fill in the template.
  Link the issue it fixes (`Fixes #12`).
- Commit as `Hatchlybox <hatchlybox@localhost>` (`git -c user.name=Hatchlybox -c user.email=hatchlybox@localhost
  commit ...`), not as the computer's person.
- Found something on the device you're on (a failing install, a firewall rule)? Report it with what you saw; don't
  change the system to work around it.
