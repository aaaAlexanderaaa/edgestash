#!/bin/bash
# Actual persistence and AppKit controls; never starts the window-control engine.
set -euo pipefail
root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
if [ "$(uname -s)" != Darwin ]; then echo "native adapter checks require macOS" >&2; exit 2; fi
if [ -z "${DEVELOPER_DIR:-}" ] && [ -d /Applications/Xcode.app/Contents/Developer ]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
work=$(mktemp -d "${TMPDIR:-/tmp}/edgestash-adapters.XXXXXX")
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/home" "$work/module-cache"
flags=(-swift-version 5 -target "$(uname -m)-apple-macosx12.0" -module-cache-path "$work/module-cache")
logic_sources=()
app_sources=()
while IFS= read -r -d '' source; do logic_sources+=("$source"); done \
  < <(find "$root/Sources/EdgeStashLogic" -name '*.swift' -print0)
while IFS= read -r -d '' source; do app_sources+=("$source"); done \
  < <(find "$root/Sources/EdgeStash" -name '*.swift' ! -name main.swift -print0)
xcrun swiftc "${flags[@]}" -parse-as-library -module-name EdgeStashLogic \
  -emit-module -emit-module-path "$work/EdgeStashLogic.swiftmodule" \
  -emit-library -static -o "$work/libEdgeStashLogic.a" "${logic_sources[@]}"
xcrun clang -target "$(uname -m)-apple-macosx12.0" -fobjc-arc -c \
  "$root/Sources/EdgeStash/Engine/DisplaySpaceBridge.m" -o "$work/bridge.o"
xcrun swiftc "${flags[@]}" -parse-as-library -module-name EdgeStashAdapterTests \
  -I "$work" -L "$work" -lEdgeStashLogic "${app_sources[@]}" "$work/bridge.o" \
  "$root/NativeTests/NativeAdapters.swift" -o "$work/native-adapters"
CFFIXED_USER_HOME="$work/home" "$work/native-adapters" "$work/fixtures"
