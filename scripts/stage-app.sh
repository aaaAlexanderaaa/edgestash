#!/bin/sh
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

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild \
    -project "$root/EdgeStash.xcodeproj" \
    -scheme EdgeStash \
    -configuration "$configuration" \
    -derivedDataPath "$derived" \
    build

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
  echo "built: $(date '+%Y-%m-%d %H:%M:%S %z')"
} > "$dist/CURRENT.txt"

echo "Staged $configuration app:"
echo "  $dist/$app_name"
cat "$dist/CURRENT.txt"
