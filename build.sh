#!/bin/zsh
set -euo pipefail
cd "${0:a:h}"
SPARKLE=build.noindex/Sparkle-2.10.1
if [[ ! -d "$SPARKLE/Sparkle.framework" ]]; then
  mkdir -p "$SPARKLE"
  curl -fL --retry 2 https://github.com/sparkle-project/Sparkle/releases/download/2.10.1/Sparkle-2.10.1.tar.xz -o "$SPARKLE.tar.xz"
  printf '%s  %s\n' 1a856d2a9edb8e628de88121d7be04cf0e2167f8641650b78fca00b14244cf27 "$SPARKLE.tar.xz" | shasum -a 256 -c -
  tar -xf "$SPARKLE.tar.xz" -C "$SPARKLE"
fi
APP=build.noindex/NitBoost.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Frameworks" "$APP/Contents/Resources"
cp Info.plist "$APP/Contents/Info.plist"
ditto "$SPARKLE/Sparkle.framework" "$APP/Contents/Frameworks/Sparkle.framework"
cp "$SPARKLE/LICENSE" "$APP/Contents/Resources/Sparkle-LICENSE.txt"
swiftc -O -swift-version 5 -target arm64-apple-macos13.0 -F "$SPARKLE" -framework Sparkle -Xlinker -rpath -Xlinker @executable_path/../Frameworks Sources/*.swift -o "$APP/Contents/MacOS/NitBoost"
SIGNING_IDENTITY=-
if security find-identity -p codesigning | grep -q '"XDRBoost Local Signing"'; then
  SIGNING_IDENTITY="XDRBoost Local Signing"
fi
FRAMEWORK="$APP/Contents/Frameworks/Sparkle.framework/Versions/B"
for component in "$FRAMEWORK"/XPCServices/*.xpc "$FRAMEWORK/Autoupdate" "$FRAMEWORK/Updater.app" "$APP/Contents/Frameworks/Sparkle.framework"; do
  codesign --force --sign "$SIGNING_IDENTITY" --preserve-metadata=entitlements "$component"
done
codesign --force --sign "$SIGNING_IDENTITY" --identifier com.dodat.nitboost "$APP"
codesign --verify --deep --strict "$APP"
if [[ "${1:-}" == "install" ]]; then
  pkill -x NitBoost || true
  for attempt in {1..50}; do
    if ! pgrep -x NitBoost >/dev/null; then break; fi
    sleep 0.1
  done
  if pgrep -x NitBoost >/dev/null; then
    echo "NitBoost did not stop. Installation cancelled." >&2
    exit 1
  fi
  rm -rf /Applications/NitBoost.app
  cp -R "$APP" /Applications/
  open /Applications/NitBoost.app
fi
echo "Built $APP"
