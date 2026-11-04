#!/bin/bash
# Build + deploy no iPhone FÍSICO sem xcodebuild (que crasha no Xcode 26 com
# device pareado: INTERNAL ERROR em DVTDeviceManager). Pipeline manual:
#   swiftc → actool → Info.plist → codesign(--entitlements do profile) → devicectl install
#
# PRÉ-REQUISITO (uma vez): um provisioning profile para o bundle id abaixo precisa
# existir em ~/Library/Developer/Xcode/UserData/Provisioning Profiles/. O Xcode 26
# CLI não consegue criar (crash), então gere-o UMA vez pela GUI do Xcode:
#   abra TripleTileKids.xcodeproj → target TripleTileKids → Signing & Capabilities
#   → Team U3H5DHZP65, "Automatically manage signing" → o Xcode cria o profile.
# Depois este script assume tudo.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
SRC="$ROOT/TripleTileKids"
BUILD="$ROOT/.build_device"
APP="$BUILD/TripleTileKids.app"
BUNDLE_ID="com.tripletile.TripleTileKids"
TEAM="U3H5DHZP65"
DEVICE="${DEVICE:-A495656F-4801-515B-9900-E7989FCB561A}"   # iPhone 17 Pro
SIGN_ID="${SIGN_ID:-F21A80091B14809E07836D4B6D81B5400B263610}"  # Apple Development: viniciusluciano@me.com

SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
TARGET="arm64-apple-ios17.0"

# ── localizar provisioning profile do bundle id ───────────────────────────────
PROFILES_DIR="$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"
PROFILE=""
if [ -d "$PROFILES_DIR" ]; then
  for p in "$PROFILES_DIR"/*.mobileprovision; do
    [ -e "$p" ] || continue
    appid="$(security cms -D -i "$p" 2>/dev/null | plutil -extract Entitlements.application-identifier raw - 2>/dev/null || true)"
    if [ "$appid" = "$TEAM.$BUNDLE_ID" ]; then PROFILE="$p"; break; fi
  done
fi

rm -rf "$BUILD"; mkdir -p "$APP"

echo "▸ compilando swift (arm64 iphoneos)…"
xcrun --sdk iphoneos swiftc -sdk "$SDK" -target "$TARGET" -swift-version 5 \
  -parse-as-library -Onone -g -o "$APP/TripleTileKids" "$SRC"/*.swift

echo "▸ compilando assets (actool)…"
PARTIAL="$BUILD/assets-partial.plist"
xcrun actool "$SRC/Assets.xcassets" --compile "$APP" \
  --platform iphoneos --minimum-deployment-target 17.0 --app-icon AppIcon \
  --target-device iphone --target-device ipad \
  --output-partial-info-plist "$PARTIAL" --errors --warnings >/dev/null

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
[ -s "$PARTIAL" ] && /usr/libexec/PlistBuddy -c "Merge '$PARTIAL'" "$PLIST" >/dev/null 2>&1 || true
plutil -convert binary1 "$PLIST"

if [ -z "$PROFILE" ]; then
  cat <<EOF

⚠️  Sem provisioning profile para $TEAM.$BUNDLE_ID.
   O .app foi montado (NÃO assinado) em: $APP
   Gere o profile UMA vez pela GUI do Xcode (veja o cabeçalho deste script),
   depois rode novamente: ./build_device.sh
EOF
  exit 2
fi

echo "▸ profile: $PROFILE"
cp "$PROFILE" "$APP/embedded.mobileprovision"
ENT="$BUILD/entitlements.plist"
security cms -D -i "$PROFILE" | plutil -extract Entitlements xml1 -o "$ENT" -

echo "▸ assinando…"
codesign --force --sign "$SIGN_ID" --entitlements "$ENT" --timestamp=none "$APP"
codesign --verify --verbose "$APP"

echo "▸ instalando no device $DEVICE (desbloqueie o iPhone)…"
xcrun devicectl device install app --device "$DEVICE" "$APP"
echo "✅ instalado."
