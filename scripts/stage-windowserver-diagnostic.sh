#!/bin/bash
set -euo pipefail
root="$(cd -- "$(dirname -- "$0")/.." && pwd)"
package="$root/dist/WindowServerDiagnostic"
mkdir -p "$package"
xcrun swiftc -O -parse-as-library -target arm64-apple-macosx12.0 \
  -module-cache-path "$root/.build/windowserver-diagnostic/module-cache" \
  "$root/scripts/WindowServerDiagnostic.swift" -o "$package/WindowServerDiagnostic"
codesign --force --sign - "$package/WindowServerDiagnostic"
cp "$root/scripts/diagnose-windowserver.sh" "$package/diagnose-windowserver.sh"
cp "$root/docs/windowserver-diagnostic.md" "$package/README.md"
cat > "$package/Run Diagnostic.command" <<'SCRIPT'
#!/bin/bash
cd -- "$(dirname -- "$0")"
/bin/bash ./diagnose-windowserver.sh --pause-engine --occlusion-probe
result=$?
printf '\n按回车关闭。\n'
read -r _
exit "$result"
SCRIPT
chmod +x "$package/Run Diagnostic.command" "$package/diagnose-windowserver.sh"
ditto -c -k --keepParent "$package" "$root/dist/WindowServerDiagnostic.zip"
printf 'Diagnostic: %s\nZip: %s\n' "$package/Run Diagnostic.command" "$root/dist/WindowServerDiagnostic.zip"
