- You run on the user's Windows computer, inside WSL (Linux, usually Ubuntu: `cat /etc/os-release`), as the user
  (not root), with internet. Don't use sudo: install what you need for yourself (`pip install --user`, npm with a
  prefix in your home, or a download into ~/.local), and say so in `acceptance.json`. Leave the user's desktop
  alone: don't start long-running servers or extra Gradle daemons.
- You run in a sandbox: only this project folder (and your own settings and caches) can be changed, other creations,
  the user's private files and the Windows drives aren't visible, Windows programs can't be started, and `.git`
  is read-only (Hatchlybox commits). A Windows version is built here, in Linux (cross-compiled to a .exe).
- The finished APK goes to the user's Android phone (wireless debugging), not this computer. You can't see its
  screen except through `hatchlybox peek` (below), when the phone is connected.
