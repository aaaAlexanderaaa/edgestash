#!/bin/bash
# Verify a distribution app without changing it. --signed-only is the check
# before submitting to Apple; the default also requires notarization evidence.
set -euo pipefail

signed_only=false
if [ "${1:-}" = --signed-only ]; then signed_only=true; shift; fi
if [ "$#" -ne 2 ]; then
  echo "usage: $0 [--signed-only] /path/to/EdgeStash.app EXPECTED_TEAM_ID" >&2
  exit 2
fi
app="$1"
team="$2"
if [[ ! "$team" =~ ^[A-Z0-9]{10}$ ]]; then
  echo "expected team must be a 10-character Apple Team ID" >&2
  exit 2
fi
plist="$app/Contents/Info.plist"
identifier=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$plist")
if [ "$identifier" != top.whatif.edgestash ]; then
  echo "unexpected bundle identifier: $identifier" >&2
  exit 1
fi
architecture=$(xcrun lipo -archs "$app/Contents/MacOS/EdgeStash")
if [ "$architecture" != arm64 ]; then
  echo "distribution must be Apple Silicon only; found: $architecture" >&2
  exit 1
fi

# Use Apple's Developer ID certificate classes and the team, not a leaf
# fingerprint or cdhash. Normal certificate renewal must not change identity.
requirement='anchor apple generic and identifier "top.whatif.edgestash"'
requirement+=' and certificate 1[field.1.2.840.113635.100.6.2.6] exists'
requirement+=' and certificate leaf[field.1.2.840.113635.100.6.1.13] exists'
requirement+=' and certificate leaf[subject.OU] = "'"$team"'"'
codesign --verify --deep --strict --verbose=2 -R "=$requirement" "$app" >&2
signature=$(codesign --display --verbose=4 "$app" 2>&1)
case "$signature" in
  *"(runtime)"*) ;;
  *) echo "Hardened Runtime is missing" >&2; exit 1 ;;
esac
case "$signature" in
  *"Timestamp="*) ;;
  *) echo "secure signing timestamp is missing" >&2; exit 1 ;;
esac
if ! "$signed_only"; then
  xcrun stapler validate "$app" >&2
  spctl --assess --type execute --verbose=2 "$app" >&2
fi
