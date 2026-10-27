- You run on the user's Mac, as the user (not root), with internet. Homebrew may be there (`brew install`);
  don't use sudo, and say in `acceptance.json` what you installed. Leave the user's desktop alone: don't
  start long-running servers or extra Gradle daemons.
- The finished APK goes to the user's Android phone (USB or wireless debugging), not this Mac. You can't see
  its screen except through `hatchlybox peek` (below), when the phone is connected.
- You run in a sandbox: only this project folder (and your own settings and caches) can be changed, other creations
  and the user's private files aren't visible, and `.git` is read-only (Hatchlybox commits). If something you need is
  outside it, say so in `acceptance.json` instead of working around it.
