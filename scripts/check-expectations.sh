#!/usr/bin/env bash
# EdgeStash expectation check — the standing conformance gate.
#
# Runs when code is considered ready to commit. It verifies the live app against
# the declared behavior grammar (docs/contracts/behavior-grammar.md) instead of
# only running unit tests:
#
#   1. Structural conformance (deviation classes 1 & 2): every user-facing
#      presentation primitive in Sources/EdgeStash must map to a declared effect
#      anchor, and every declared anchor must exist in the code.
#   2. Behavioral conformance (deviation classes 3 & 4): runs the AppKit-free
#      property tests, which assert declared cardinalities on scripted timelines.
#
# Runs on Linux; no macOS dependency. Perceptual review stays an owner step.

set -euo pipefail

root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
cd "$root"

grammar="docs/contracts/behavior-grammar.md"
src="Sources/EdgeStash"
# The user-facing presentation primitives that make something appear on screen.
primitives='orderFront\(|orderFrontRegardless\(|makeKeyAndOrderFront\(|EdgeAlert\.run\(|\.runModal\('

fail=0
note() { printf '%s\n' "$*"; }
problem() { printf 'DEVIATION: %s\n' "$*" >&2; fail=1; }

[ -f "$grammar" ] || { echo "missing grammar: $grammar" >&2; exit 2; }
[ -d "$src" ] || { echo "missing source tree: $src" >&2; exit 2; }

# --- Declared anchors: "file\tsymbol" from the manifest block ---------------
declared=$(awk '
  /<!-- BEGIN grammar-manifest -->/ { on=1; next }
  /<!-- END grammar-manifest -->/   { on=0 }
  on && index($0, "|") {
    n=split($0, c, "|")
    if (n >= 4) {
      f=c[3]; s=c[4]
      gsub(/^[ \t]+|[ \t]+$/, "", f); gsub(/^[ \t]+|[ \t]+$/, "", s)
      if (f != "" && s != "") print f "\t" s
    }
  }
' "$grammar" | sort -u)

[ -n "$declared" ] || { echo "no declared anchors parsed from $grammar" >&2; exit 2; }

# --- Observed anchors: enclosing file:symbol of each primitive call site -----
observed=$(
  # shellcheck disable=SC2016
  grep -rlE "$primitives" "$src" 2>/dev/null | while IFS= read -r f; do
    awk -v FILE="$f" -v PRIM="$primitives" '
      { if (match($0, /func +[A-Za-z_][A-Za-z0-9_]*/)) fn=substr($0, RSTART+5, RLENGTH-5) }
      {
        line=$0
        sub(/\/\/.*$/, "", line)                     # drop trailing comments
        if (line ~ /func /) next                      # skip declarations
        if (line ~ PRIM) print FILE "\t" (fn=="" ? "<file-scope>" : fn)
      }
    ' "$f"
  done | sort -u
)

# --- Class 2: observed effect with no declared production -------------------
while IFS= read -r pair; do
  [ -z "$pair" ] && continue
  if ! printf '%s\n' "$declared" | grep -qxF "$pair"; then
    problem "undeclared user-facing effect (class 2 — 'should not do, does'): $(printf '%s' "$pair" | tr '\t' ':') — add a production to $grammar"
  fi
done <<< "$observed"

# --- Class 1: declared production with no implementation anchor --------------
while IFS= read -r pair; do
  [ -z "$pair" ] && continue
  if ! printf '%s\n' "$observed" | grep -qxF "$pair"; then
    problem "declared effect has no implementation (class 1 — 'should do, does not'): $(printf '%s' "$pair" | tr '\t' ':') — implement it or remove the production from $grammar"
  fi
done <<< "$declared"

if [ "$fail" -eq 0 ]; then
  note "Structural conformance OK: $(printf '%s\n' "$observed" | grep -c . ) presentation sites, all declared."
fi

# --- Classes 3 & 4: behavioral cardinality property tests -------------------
note "Running behavioral property tests (swift run EdgeStashLogicTests)…"
if swift run EdgeStashLogicTests; then
  note "Behavioral conformance OK."
else
  problem "behavioral property tests failed (class 3/4 — cardinality violation)."
fi

if [ "$fail" -ne 0 ]; then
  echo "" >&2
  echo "Expectation check FAILED. Each deviation is a code fix or a grammar change." >&2
  exit 1
fi
note "Expectation check PASSED."
