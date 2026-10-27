#!/usr/bin/env bash
# install.sh [linux|macos|windows]: Hatchlybox Engine from this checkout, for this computer's user: the engine in its
# data folder (bin/paths.sh decides where: HATCHLYBOX_HOME, else the system's own place), this platform's files,
# `hatchlybox` on the PATH (~/.local/bin), and the desktop front end with a launcher: an app menu entry on Linux,
# Hatchlybox.app in ~/Applications on a Mac (Windows: install-windows.ps1 runs this in WSL and adds the Start menu
# shortcut). Run again to update; creations, keys and settings stay. HATCHLYBOX_NO_LAUNCHER=1 skips the launcher.
set -euo pipefail
cd "$(dirname "$0")"
if [ -n "${1:-}" ]; then platform=$1
elif [ "$(uname -s)" = Darwin ]; then platform=macos
elif grep -qis microsoft /proc/version; then platform=windows
else platform=linux; fi
[ -f "platforms/$platform/platform.env" ] || { echo "no platform $platform (see platforms/)" >&2; exit 1; }
source bin/paths.sh
mkdir -p "$DATA" "$CACHE" "$APPS" "$PORTS"
for d in bin template skills starter; do rm -rf "$DATA/$d.new"; cp -R "$d" "$DATA/$d.new"; rm -rf "${DATA:?}/$d"; mv "$DATA/$d.new" "$DATA/$d"; done
rm -f "$DATA/template/local.properties"
rm -rf "$DATA/visual" && mkdir -p "$DATA/visual" && cp -R visual/bin visual/kb visual/gl.list "$DATA/visual/"
rm -rf "$DATA/desktop" && mkdir -p "$DATA/desktop" && cp desktop/*.html desktop/*.js desktop/*.css desktop/icon.* "$DATA/desktop/"
cp creation/AGENTS.md "platforms/$platform/platform.env" "platforms/$platform/environment.md" "$DATA/"
chmod +x "$DATA"/bin/* "$DATA/template/gradlew" "$DATA"/visual/bin/*
# The skills library matches this engine (hatchlybox doctor checks).
sed -n 's/^VERSION=//p' bin/hatchlybox > "$DATA/.library"
mkdir -p "$HOME/.local/bin" && ln -sfn "$DATA/bin/hatchlybox" "$HOME/.local/bin/hatchlybox"
# A desktop server from before this update stops; the next open starts this one's.
[ ! -x "$HOME/.local/bin/hatchlybox" ] || "$HOME/.local/bin/hatchlybox" desktop stop >/dev/null 2>&1 || true
# The launcher: Hatchlybox opens in the browser, like an app.
if [ -z "${HATCHLYBOX_NO_LAUNCHER:-}" ]; then
  case $platform in
    linux)
      apps=${XDG_DATA_HOME:-$HOME/.local/share}/applications; mkdir -p "$apps"
      printf '%s\n' '[Desktop Entry]' 'Type=Application' 'Name=Hatchlybox' 'Comment=Describe an app or a game: Hatchlybox makes it' \
        "Exec=\"$HOME/.local/bin/hatchlybox\" desktop" "Icon=$DATA/desktop/icon.png" 'Terminal=false' 'Categories=Development;' 'StartupNotify=false' > "$apps/hatchlybox.desktop"
      command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database -q "$apps" 2>/dev/null || true
      echo "Hatchlybox is in your app menu." ;;
    macos)
      app=$HOME/Applications/Hatchlybox.app; rm -rf "$app"; mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
      cat > "$app/Contents/MacOS/Hatchlybox" <<EOF
#!/bin/bash
# Started from Finder or the Dock: Homebrew's tools aren't on the PATH there.
export PATH="/opt/homebrew/bin:/usr/local/bin:\$HOME/.local/bin:\$PATH"
exec "\$HOME/.local/bin/hatchlybox" desktop
EOF
      chmod +x "$app/Contents/MacOS/Hatchlybox"
      printf '%s\n' '<?xml version="1.0" encoding="UTF-8"?>' '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">' \
        '<plist version="1.0"><dict>' '<key>CFBundleName</key><string>Hatchlybox</string>' '<key>CFBundleIdentifier</key><string>app.hatchlybox.desktop</string>' \
        '<key>CFBundleExecutable</key><string>Hatchlybox</string>' '<key>CFBundleIconFile</key><string>icon</string>' '<key>CFBundlePackageType</key><string>APPL</string>' \
        '<key>LSUIElement</key><true/>' '</dict></plist>' > "$app/Contents/Info.plist"
      # The icon: macOS's own tools turn the PNG into an .icns.
      if command -v sips >/dev/null && command -v iconutil >/dev/null; then
        set_=$(mktemp -d)/icon.iconset; mkdir -p "$set_"
        for s in 16 32 128 256 512; do
          sips -z $s $s desktop/icon.png --out "$set_/icon_${s}x${s}.png" >/dev/null
          sips -z $((s * 2)) $((s * 2)) desktop/icon.png --out "$set_/icon_${s}x${s}@2x.png" >/dev/null 2>&1 || true
        done
        iconutil -c icns "$set_" -o "$app/Contents/Resources/icon.icns" 2>/dev/null || true
      fi
      echo "Hatchlybox is in ~/Applications (open it from Launchpad or Spotlight)." ;;
  esac
fi
echo "Hatchlybox Engine $(cat "$DATA/.library") for $platform is in $DATA, your creations in $APPS."
case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) echo "Add ~/.local/bin to your PATH to run hatchlybox." ;; esac
echo "Next: open Hatchlybox (or run hatchlybox desktop): its Settings say what's missing and set up Android building."
