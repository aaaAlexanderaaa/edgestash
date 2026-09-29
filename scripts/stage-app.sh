#!/bin/bash
# Stage the owner-runnable EdgeStash app. Always the same three files:
#   dist/EdgeStash.app
#   dist/EdgeStash.zip
#   dist/CURRENT.txt
# Usage: ./scripts/stage-app.sh [Release|Debug]
# Default is Release. Debug still overwrites the same paths.

set -eu

root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
configuration="${1:-Release}"
case "$configuration" in
  Release|Debug) ;;
  *)
    echo "usage: $0 [Release|Debug]" >&2
    exit 2
    ;;
esac

app_name="EdgeStash.app"
dist="$root/dist"
derived="$dist/.derived"
product="$derived/Build/Products/$configuration/$app_name"

rm -rf "$dist"
mkdir -p "$derived"

toolchain="Xcode"
if [ -d /Applications/Xcode.app/Contents/Developer ]; then
  DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
    -project "$root/EdgeStash.xcodeproj" \
    -scheme EdgeStash \
    -configuration "$configuration" \
    -derivedDataPath "$derived" \
    build
else
  # CLT can build this native app's Swift sources and Objective-C bridge. This
  # provides the owner a runnable artifact; it does not satisfy the separate
  # Xcode-project validation gate. Record the distinction in CURRENT.txt.
  toolchain="Apple Command Line Tools (Xcode project validation unavailable)"
  target="$(uname -m)-apple-macosx12.0"
  flags=(-swift-version 5 -target "$target" -g)
  if [ "$configuration" = Debug ]; then
    flags+=(-Onone -D DEBUG)
  else
    flags+=(-O)
  fi
  logic_sources=()
  app_sources=()
  while IFS= read -r -d '' source; do logic_sources+=("$source"); done \
    < <(find "$root/Sources/EdgeStashLogic" -name '*.swift' -print0)
  while IFS= read -r -d '' source; do app_sources+=("$source"); done \
    < <(find "$root/Sources/EdgeStash" -name '*.swift' -print0)
  mkdir -p "$product/Contents/MacOS" "$product/Contents/Resources"
  xcrun swiftc "${flags[@]}" -parse-as-library -module-name EdgeStashLogic \
    -emit-module -emit-module-path "$derived/EdgeStashLogic.swiftmodule" \
    -emit-library -static -o "$derived/libEdgeStashLogic.a" "${logic_sources[@]}"
  xcrun clang -target "$target" -fobjc-arc -c \
    "$root/Sources/EdgeStash/Engine/DisplaySpaceBridge.m" -o "$derived/DisplaySpaceBridge.o"
  xcrun swiftc "${flags[@]}" -module-name EdgeStash -I "$derived" -L "$derived" \
    -lEdgeStashLogic "${app_sources[@]}" "$derived/DisplaySpaceBridge.o" \
    -o "$product/Contents/MacOS/EdgeStash"
  cp "$root/Sources/Info.plist" "$product/Contents/Info.plist"
  cp "$root/Sources/EdgeStash/AppIcon.icns" "$product/Contents/Resources/AppIcon.icns"
  printf 'APPL????' > "$product/Contents/PkgInfo"
  codesign --force --sign - "$product"
fi

if [ ! -d "$product" ]; then
  echo "staged product missing: $product" >&2
  exit 1
fi

ditto "$product" "$dist/$app_name"
ditto -c -k --keepParent "$dist/$app_name" "$dist/EdgeStash.zip"
rm -rf "$derived"

{
  echo "open: $dist/$app_name"
  echo "zip: $dist/EdgeStash.zip"
  echo "configuration: $configuration"
  echo "toolchain: $toolchain"
  echo "built: $(date '+%Y-%m-%d %H:%M:%S %z')"
} > "$dist/CURRENT.txt"

echo "Staged $configuration app:"
echo "  $dist/$app_name"
cat "$dist/CURRENT.txt"
