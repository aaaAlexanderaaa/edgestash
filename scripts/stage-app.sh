#!/bin/bash
# Stage the owner-runnable EdgeStash app. Always the same three files:
#   dist/EdgeStash.app
#   dist/EdgeStash.zip
#   dist/CURRENT.txt
# Usage: ./scripts/stage-app.sh [Release|Debug] [--distribution]
# Default is a local, ad-hoc-signed Release. Distribution requires Developer ID
# signing and notarization; see docs/distribution.md for one-time setup.

set -euo pipefail

root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
configuration="${1:-Release}"
distribution=false
if [ "$#" -gt 2 ] || { [ "$#" -eq 2 ] && [ "$2" != --distribution ]; }; then
  echo "usage: $0 [Release|Debug] [--distribution]" >&2
  exit 2
fi
case "$configuration" in
  Release|Debug) ;;
  *)
    echo "usage: $0 [Release|Debug] [--distribution]" >&2
    exit 2
    ;;
esac
if [ "${2:-}" = --distribution ]; then
  distribution=true
  if [ "$configuration" != Release ]; then
    echo "distribution requires the Release configuration" >&2
    exit 2
  fi

  # Check prerequisites before building or replacing any existing staged app.
  : "${EDGESTASH_SIGNING_IDENTITY:?set a Developer ID Application identity}"
  : "${EDGESTASH_TEAM_ID:?set the expected Apple Developer Team ID}"
  : "${EDGESTASH_NOTARY_PROFILE:?set a notarytool Keychain profile}"
  if [[ ! "$EDGESTASH_TEAM_ID" =~ ^[A-Z0-9]{10}$ ]]; then
    echo "EDGESTASH_TEAM_ID must be a 10-character Apple Team ID" >&2
    exit 2
  fi
  case "$EDGESTASH_SIGNING_IDENTITY" in
    "Developer ID Application: "*" ($EDGESTASH_TEAM_ID)") ;;
    *)
      echo "signing identity must be Developer ID Application for the expected team" >&2
      exit 2
      ;;
  esac
  identities=$(security find-identity -v -p codesigning)
  case "$identities" in
    *"\"$EDGESTASH_SIGNING_IDENTITY\""*) ;;
    *)
      echo "Developer ID Application identity and private key not found in Keychain" >&2
      exit 1
      ;;
  esac
  xcrun --find notarytool >/dev/null
  xcrun --find stapler >/dev/null
fi

app_name="EdgeStash.app"
dist="$root/dist"
work=$(mktemp -d "${TMPDIR:-/tmp}/edgestash-stage.XXXXXX")
trap 'rm -rf "$work"' EXIT
derived="$work/derived"
staged="$work/staged"
product="$derived/Build/Products/$configuration/$app_name"
mkdir -p "$derived" "$staged"

toolchain="Xcode"
if [ -d /Applications/Xcode.app/Contents/Developer ]; then
  build_options=(CODE_SIGN_IDENTITY=-)
  if "$distribution"; then
    # Sign the final bundle below with exactly the same policy as the CLT path.
    build_options=(ARCHS=arm64 ONLY_ACTIVE_ARCH=NO CODE_SIGNING_ALLOWED=NO)
  fi
  DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
    -project "$root/EdgeStash.xcodeproj" \
    -scheme EdgeStash \
    -configuration "$configuration" \
    -derivedDataPath "$derived" \
    "${build_options[@]}" \
    build
else
  # CLT can build this native app's Swift sources and Objective-C bridge. This
  # provides the owner a runnable artifact; it does not satisfy the separate
  # Xcode-project validation gate. Record the distinction in CURRENT.txt.
  toolchain="Apple Command Line Tools (Xcode project validation unavailable)"
  architecture="$(uname -m)"
  if "$distribution"; then architecture=arm64; fi
  target="$architecture-apple-macosx12.0"
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
fi

if [ ! -d "$product" ]; then
  echo "staged product missing: $product" >&2
  exit 1
fi

app="$staged/$app_name"
ditto "$product" "$app"
mode="development"
signing="ad-hoc (not a distribution identity)"
notarization="not requested"
if "$distribution"; then
  codesign --force --sign "$EDGESTASH_SIGNING_IDENTITY" \
    --identifier top.whatif.edgestash --options runtime --timestamp \
    --entitlements "$root/packaging/EdgeStash.entitlements" "$app"
  "$root/scripts/verify-distribution.sh" --signed-only "$app" "$EDGESTASH_TEAM_ID"

  # Apple accepts a ZIP submission, but the ticket must be stapled to the app.
  # The submission ZIP is never the final published archive.
  ditto -c -k --keepParent "$app" "$derived/notarization.zip"
  echo "Submitting to Apple notarization; waiting up to 30 minutes..."
  notary_exit_status=0
  xcrun notarytool submit "$derived/notarization.zip" \
    --keychain-profile "$EDGESTASH_NOTARY_PROFILE" \
    --wait --timeout 30m --output-format plist \
    > "$derived/notary-result.plist" || notary_exit_status=$?
  notary_status=$(/usr/libexec/PlistBuddy -c 'Print :status' \
    "$derived/notary-result.plist" 2>/dev/null || true)
  if [ "$notary_exit_status" -ne 0 ] || [ "$notary_status" != Accepted ]; then
    cat "$derived/notary-result.plist" >&2
    submission_id=$(/usr/libexec/PlistBuddy -c 'Print :id' \
      "$derived/notary-result.plist" 2>/dev/null || true)
    if [ -n "$submission_id" ]; then
      echo "Notarization submission: $submission_id" >&2
      xcrun notarytool log "$submission_id" \
        --keychain-profile "$EDGESTASH_NOTARY_PROFILE" >&2 || true
    fi
    echo "notarization did not finish with Accepted; existing dist is unchanged" >&2
    exit 1
  fi
  xcrun stapler staple "$app"
  "$root/scripts/verify-distribution.sh" "$app" "$EDGESTASH_TEAM_ID"
  mode="distribution"
  signing="Developer ID Application (team $EDGESTASH_TEAM_ID)"
  notarization="Accepted; ticket stapled and validated; Gatekeeper accepted"
else
  # Make both build paths explicitly local; never reuse a distribution identity.
  codesign --force --sign - "$app"
  codesign --verify --deep --strict "$app"
fi

ditto -c -k --keepParent "$app" "$staged/EdgeStash.zip"
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")
build=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$app/Contents/Info.plist")
architecture=$(xcrun lipo -archs "$app/Contents/MacOS/EdgeStash")

{
  echo "open: $dist/$app_name"
  echo "zip: $dist/EdgeStash.zip"
  echo "configuration: $configuration"
  echo "toolchain: $toolchain"
  echo "mode: $mode"
  echo "version: $version ($build)"
  echo "architecture: $architecture"
  echo "signing: $signing"
  echo "notarization: $notarization"
  echo "built: $(date '+%Y-%m-%d %H:%M:%S %z')"
} > "$staged/CURRENT.txt"

# A build, signing, or notarization failure must not destroy the previous app.
rm -rf "$dist"
mv "$staged" "$dist"

echo "Staged $configuration app:"
echo "  $dist/$app_name"
cat "$dist/CURRENT.txt"
