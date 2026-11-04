#!/bin/zsh
set -euo pipefail
cd "${0:a:h}"
APP=build.noindex/NitBoost.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp Info.plist "$APP/Contents/Info.plist"
swiftc -O -swift-version 5 -target arm64-apple-macos13.0 Sources/*.swift -o "$APP/Contents/MacOS/NitBoost"
codesign --force --sign "XDRBoost Local Signing" --identifier com.dodat.nitboost "$APP" 2>/dev/null || codesign --force --sign - --identifier com.dodat.nitboost "$APP"
if [[ "${1:-}" == "install" ]]; then
  pkill -x NitBoost || true
  rm -rf /Applications/NitBoost.app
  cp -R "$APP" /Applications/
  open /Applications/NitBoost.app
fi
echo "Built $APP"
