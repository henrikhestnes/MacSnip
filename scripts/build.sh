#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"

# Keep compiler caches inside the project so builds work in restricted environments.
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/module-cache"
# Screen Recording permission is tied to the signature. With the default ad-hoc signature,
# macOS forgets the permission after every rebuild; set SIGN_IDENTITY to a stable certificate to avoid that.
identity="${SIGN_IDENTITY:--}"
architectures=()
if [[ "${1:-}" == "--universal" ]]; then
  architectures=(--arch arm64 --arch x86_64)
fi
swift build -c release --disable-sandbox -debug-info-format none "${architectures[@]}"
bin_path=$(swift build -c release --disable-sandbox -debug-info-format none "${architectures[@]}" --show-bin-path)
app="$PWD/dist/MacSnip.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
# Replace the executable instead of overwriting a binary that may be running.
cp "$bin_path/MacSnip" "$app/Contents/MacOS/MacSnip.new"
mv -f "$app/Contents/MacOS/MacSnip.new" "$app/Contents/MacOS/MacSnip"
cp Resources/Info.plist "$app/Contents/Info.plist"
swift scripts/make-icon.swift "$PWD/dist"
cp "$PWD/dist/AppIcon.icns" "$app/Contents/Resources/AppIcon.icns"
codesign --force --sign "$identity" --identifier io.macsnip.app "$app"
ditto -c -k --sequesterRsrc --keepParent "$app" "$PWD/dist/MacSnip.zip"
echo "Built: $app"
echo "Install: cp -R dist/MacSnip.app /Applications/ && open /Applications/MacSnip.app"
