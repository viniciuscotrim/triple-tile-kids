#!/bin/bash
# Build manual para o SIMULADOR iOS (sem xcodebuild, que crasha no Xcode 26 com
# iPhone pareado). Compila com swiftc + monta o .app com actool. Sem assinatura.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
SRC="$ROOT/TripleTileKids"
BUILD="$ROOT/.build_sim"
APP="$BUILD/TripleTileKids.app"
BUNDLE_ID="com.tripletile.TripleTileKids"

SDK="$(xcrun --sdk iphonesimulator --show-sdk-path)"
TARGET="arm64-apple-ios17.0-simulator"

rm -rf "$BUILD"; mkdir -p "$APP"

echo "▸ compilando swift…"
xcrun --sdk iphonesimulator swiftc \
  -sdk "$SDK" -target "$TARGET" -swift-version 5 \
  -parse-as-library -Onone -g -D DEBUG \
  -o "$APP/TripleTileKids" \
  "$SRC/TripleTileKidsApp.swift" "$SRC/ContentView.swift" "$SRC/SettingsView.swift" \
  "$SRC/GameScene.swift" "$SRC/BoardGenerator.swift" "$SRC/Tile.swift" \
  "$SRC/Theme.swift" "$SRC/Feedback.swift" "$SRC/Store.swift"

echo "▸ compilando assets (actool)…"
PARTIAL="$BUILD/assets-partial.plist"
xcrun actool "$SRC/Assets.xcassets" \
  --compile "$APP" \
  --platform iphonesimulator \
  --minimum-deployment-target 17.0 \
  --app-icon AppIcon \
  --target-device iphone --target-device ipad \
  --output-partial-info-plist "$PARTIAL" \
  --errors --warnings >/dev/null

echo "▸ Info.plist…"
PLIST="$APP/Info.plist"
cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>TripleTileKids</string>
  <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
  <key>CFBundleName</key><string>TripleTileKids</string>
  <key>CFBundleDisplayName</key><string>Triple Tile</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSRequiresIPhoneOS</key><true/>
  <key>MinimumOSVersion</key><string>17.0</string>
  <key>UIDeviceFamily</key><array><integer>1</integer><integer>2</integer></array>
  <key>UILaunchScreen</key><dict/>
  <key>UISupportedInterfaceOrientations</key>
  <array>
    <string>UIInterfaceOrientationPortrait</string>
    <string>UIInterfaceOrientationLandscapeLeft</string>
    <string>UIInterfaceOrientationLandscapeRight</string>
  </array>
  <key>UISupportedInterfaceOrientations~ipad</key>
  <array>
    <string>UIInterfaceOrientationPortrait</string>
    <string>UIInterfaceOrientationPortraitUpsideDown</string>
    <string>UIInterfaceOrientationLandscapeLeft</string>
    <string>UIInterfaceOrientationLandscapeRight</string>
  </array>
  <key>UIApplicationSceneManifest</key>
  <dict><key>UIApplicationSupportsMultipleScenes</key><false/></dict>
</dict>
</plist>
EOF

# Mescla as chaves de ícone que o actool gerou (CFBundleIcons etc.)
if [ -s "$PARTIAL" ]; then
  /usr/libexec/PlistBuddy -c "Merge '$PARTIAL'" "$PLIST" >/dev/null 2>&1 || true
fi
plutil -convert binary1 "$PLIST"

echo "✅ app montado: $APP"
