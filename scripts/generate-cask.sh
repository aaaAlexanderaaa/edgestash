#!/bin/bash
# Emit a Cask for the exact final ZIP, after checking its extracted app. No
# placeholder Cask is checked in before a signed release is available.
set -euo pipefail

root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
  echo "usage: $0 vVERSION [/path/to/EdgeStash.zip] > Casks/edgestash.rb" >&2
  exit 2
fi
: "${EDGESTASH_TEAM_ID:?set the expected Apple Developer Team ID}"
tag="$1"
archive="${2:-$root/dist/EdgeStash.zip}"
if [[ ! "$tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "release tag must be vMAJOR.MINOR.PATCH" >&2
  exit 2
fi
if [ ! -f "$archive" ]; then
  echo "release archive missing: $archive" >&2
  exit 1
fi
work=$(mktemp -d "${TMPDIR:-/tmp}/edgestash-cask.XXXXXX")
trap 'rm -rf "$work"' EXIT
ditto -x -k "$archive" "$work"
app="$work/EdgeStash.app"
"$root/scripts/verify-distribution.sh" "$app" "$EDGESTASH_TEAM_ID" >&2
plist="$app/Contents/Info.plist"
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$plist")
minimum=$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$plist")
if [ "$tag" != "v$version" ]; then
  echo "release tag $tag does not match archive version $version" >&2
  exit 1
fi
if [ "$minimum" != 12.0 ]; then
  echo "minimum macOS version changed to $minimum; update the Cask's Monterey requirement" >&2
  exit 1
fi
checksum=$(shasum -a 256 < "$archive" | awk '{print $1}')

cat <<EOF
cask "edgestash" do
  version "$version"
  sha256 "$checksum"

  url "https://github.com/aaaAlexanderaaa/edgestash/releases/download/v#{version}/EdgeStash.zip"
  name "EdgeStash"
  desc "Stash and restore windows at display edges"
  homepage "https://github.com/aaaAlexanderaaa/edgestash"

  depends_on arch: :arm64
  depends_on macos: ">= :monterey"

  app "EdgeStash.app"

  uninstall quit: "top.whatif.edgestash"

  caveats <<~EOS
    Quit EdgeStash before upgrading so it can restore managed windows.
    Grant Accessibility access in System Settings on first installation.
    Shared-edge stashing requires macOS 26.4 or later.
  EOS
end
EOF
