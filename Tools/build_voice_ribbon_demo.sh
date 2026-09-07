#!/bin/sh
set -eu

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
demo_root="$project_root/.build/demos"
demo_bundle="$demo_root/VoiceRibbonDemo.app"
mkdir -p "$demo_bundle/Contents/MacOS" "$demo_bundle/Contents/Resources"

xcrun swiftc -O -parse-as-library -target "$(uname -m)-apple-macosx14.0" \
  "$project_root/Tools/VoiceRibbonDemo.swift" \
  "$project_root/Sources/Typless/IntelligenceGlowBorder.swift" \
  "$project_root/Tools/SiriDemo/"*.swift \
  -o "$demo_bundle/Contents/MacOS/VoiceRibbonDemo" \
  -framework AppKit -framework SwiftUI

cat > "$demo_bundle/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>VoiceRibbonDemo</string>
  <key>CFBundleIdentifier</key><string>com.typless.VoiceRibbonDemo</string>
  <key>CFBundleName</key><string>Siri 视觉对照</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST

cp "$project_root/Tools/SiriDemo/THIRD_PARTY_NOTICES.txt" "$demo_bundle/Contents/Resources/"
codesign --force --sign - "$demo_bundle"
printf '%s\n' "$demo_bundle"
