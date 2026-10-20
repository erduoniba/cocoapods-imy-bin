#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_dir="$(cd "$script_dir/.." && pwd)"
build_dir="$project_dir/dist"
app_name="IMYBinManager"
app_bundle="$build_dir/$app_name.app"
version="1.0.0"
bundle_id="org.imybin.IMYBinManager"

echo "==> Building $app_name in Release configuration..."
cd "$project_dir"
swift build -c release

binary_path="$(swift build -c release --show-bin-path)/$app_name"
if [[ ! -f "$binary_path" ]]; then
    echo "Error: Release binary not found at $binary_path" >&2
    exit 1
fi

echo "==> Constructing $app_bundle..."
rm -rf "$build_dir"
mkdir -p "$app_bundle/Contents/MacOS"
mkdir -p "$app_bundle/Contents/Resources"

cp "$binary_path" "$app_bundle/Contents/MacOS/$app_name"
chmod +x "$app_bundle/Contents/MacOS/$app_name"

echo "APPL????" > "$app_bundle/Contents/PkgInfo"

cat <<EOF > "$app_bundle/Contents/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>$app_name</string>
    <key>CFBundleIdentifier</key>
    <string>$bundle_id</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>$app_name</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$version</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
EOF

echo "==> Creating distribution archives..."
cd "$build_dir"
zip -qry "$app_name.zip" "$app_name.app"
sha256_zip=$(shasum -a 256 "$app_name.zip" | awk '{print $1}')

if command -v hdiutil >/dev/null 2>&1; then
    hdiutil create -volname "$app_name" -srcfolder "$app_name.app" -ov -format UDZO "$app_name.dmg" >/dev/null
    sha256_dmg=$(shasum -a 256 "$app_name.dmg" | awk '{print $1}')
    echo "Created DMG: $build_dir/$app_name.dmg (SHA-256: $sha256_dmg)"
fi

echo "Created ZIP: $build_dir/$app_name.zip (SHA-256: $sha256_zip)"
echo "==> Packaging complete!"
