#!/bin/zsh
set -euo pipefail
cd "${0:a:h}"
./build.sh
TOOLS="$PWD/build.noindex/Sparkle-2.10.1/bin"
PUBLIC_KEY=$(/usr/libexec/PlistBuddy -c 'Print SUPublicEDKey' Info.plist)
if [[ "$PUBLIC_KEY" != "$("$TOOLS/generate_keys" --account com.dodat.nitboost -p)" ]]; then
  echo "The Sparkle signing key does not match Info.plist." >&2
  exit 1
fi
VERSION=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Info.plist)
STAGE=$(mktemp -d "$PWD/build.noindex/release.XXXXXX")
trap 'rm -rf "$STAGE"' EXIT
mkdir -p dist "$STAGE/image" "$STAGE/updates"
ditto build.noindex/NitBoost.app "$STAGE/image/NitBoost.app"
ln -s /Applications "$STAGE/image/Applications"
hdiutil create -volname NitBoost -srcfolder "$STAGE/image" -ov -format UDZO "dist/NitBoost-$VERSION.dmg"
ditto -c -k --sequesterRsrc --keepParent build.noindex/NitBoost.app "dist/NitBoost-$VERSION.zip"
cp "dist/NitBoost-$VERSION.zip" "$STAGE/updates/"
"$TOOLS/generate_appcast" --account com.dodat.nitboost --maximum-deltas 0 --disable-signing-warning --download-url-prefix "https://github.com/dodat1905/nitboost/releases/download/v$VERSION/" "$STAGE/updates"
"$TOOLS/sign_update" --account com.dodat.nitboost --verify "$STAGE/updates/appcast.xml"
cp "$STAGE/updates/appcast.xml" appcast.xml
swift Tests/verify_archive.swift "dist/NitBoost-$VERSION.zip"
hdiutil verify "dist/NitBoost-$VERSION.dmg"
shasum -a 256 "dist/NitBoost-$VERSION.dmg" "dist/NitBoost-$VERSION.zip"
