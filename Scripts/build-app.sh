#!/bin/zsh
set -euo pipefail

project_dir=${0:A:h:h}
app_dir="$project_dir/.build/CodexMeter.app"
contents_dir="$app_dir/Contents"
executable="$contents_dir/MacOS/CodexMeter"
resources_dir="$contents_dir/Resources"
plist="$contents_dir/Info.plist"
sources=()

while IFS= read -r -d '' source; do sources+=("$source"); done < <(find "$project_dir/CodexMeter" -name '*.swift' -print0)

mkdir -p "$contents_dir/MacOS" "$resources_dir"
/usr/bin/swiftc "${sources[@]}" -O -o "$executable"
/bin/cp "$project_dir/Resources/AppIcon.icns" "$resources_dir/AppIcon.icns"
/usr/bin/plutil -create xml1 "$plist"
/usr/bin/plutil -insert CFBundleExecutable -string CodexMeter "$plist"
/usr/bin/plutil -insert CFBundleIdentifier -string com.codexmeter.app "$plist"
/usr/bin/plutil -insert CFBundleName -string "Codex Meter" "$plist"
/usr/bin/plutil -insert CFBundleIconFile -string AppIcon.icns "$plist"
/usr/bin/plutil -insert CFBundlePackageType -string APPL "$plist"
/usr/bin/plutil -insert CFBundleShortVersionString -string 0.1.0 "$plist"
/usr/bin/plutil -insert CFBundleVersion -string 2 "$plist"
/usr/bin/plutil -insert LSMinimumSystemVersion -string 14.0 "$plist"
/usr/bin/plutil -insert LSUIElement -bool true "$plist"
/usr/bin/codesign --force --sign - "$app_dir"

echo "构建完成：$app_dir"
