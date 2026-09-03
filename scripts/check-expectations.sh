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
#   2. Behavioral conformance (deviation classes 3 & 4): validates executable
#      evidence anchors, then runs the AppKit-free timeline tests.
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

# --- Parse and validate the machine-readable manifest -----------------------
manifest=$(awk '
  function trim(v) { gsub(/^[ \t]+|[ \t]+$/, "", v); return v }
  /<!-- BEGIN grammar-manifest -->/ { on=1; next }
  /<!-- END grammar-manifest -->/   { on=0 }
  on && index($0, "|") {
    n=split($0, c, "|")
    if (n != 8) {
      print "__INVALID__\t" NR "\texpected 8 columns, found " n
      next
    }
    for (i=1; i<=8; i++) c[i]=trim(c[i])
    for (i=1; i<=8; i++) {
      if (c[i] == "") {
        print "__INVALID__\t" NR "\tcolumn " i " is empty"
        next
      }
    }
    print c[1] "\t" c[2] "\t" c[3] "\t" c[4] "\t" c[5] "\t" c[6] "\t" c[7] "\t" c[8]
  }
' "$grammar")

invalid_rows=$(printf '%s\n' "$manifest" | awk -F '\t' '$1 == "__INVALID__" { print "line " $2 ": " $3 }')
[ -z "$invalid_rows" ] || { printf 'invalid grammar manifest: %s\n' "$invalid_rows" >&2; exit 2; }

effects=$(printf '%s\n' "$manifest" | awk -F '\t' 'NF == 8 { print $1 }')
duplicate_effects=$(printf '%s\n' "$effects" | sort | uniq -d)
[ -z "$duplicate_effects" ] || { printf 'duplicate effect id(s):\n%s\n' "$duplicate_effects" >&2; exit 2; }

declared=$(printf '%s\n' "$manifest" | awk -F '\t' 'NF == 8 { print $3 "\t" $4 }' | sort -u)
duplicate_anchors=$(printf '%s\n' "$manifest" | awk -F '\t' 'NF == 8 { print $3 "\t" $4 }' | sort | uniq -d)
[ -z "$duplicate_anchors" ] || { printf 'duplicate implementation anchor(s):\n%s\n' "$duplicate_anchors" >&2; exit 2; }

[ -n "$declared" ] || { echo "no declared anchors parsed from $grammar" >&2; exit 2; }

# --- Observed anchors: enclosing file:symbol of each primitive call site -----
matching_files=$(grep -rlE "$primitives" "$src" 2>/dev/null || true)
observed=$(
  # shellcheck disable=SC2016
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    # Passing a backslash-bearing ERE through awk -v is not portable: BSD awk
    # consumes the escapes before the dynamic match. ENVIRON preserves the ERE
    # on both BSD awk (macOS) and GNU awk (Linux).
    PRIM="$primitives" awk -v FILE="$f" '
      BEGIN { primitive=ENVIRON["PRIM"] }
      { if (match($0, /func +[A-Za-z_][A-Za-z0-9_]*/)) fn=substr($0, RSTART+5, RLENGTH-5) }
      {
        line=$0
        sub(/\/\/.*$/, "", line)                     # drop trailing comments
        if (line ~ /func /) next                      # skip declarations
        if (line ~ primitive) print FILE "\t" (fn=="" ? "<file-scope>" : fn)
      }
    ' "$f"
  done <<< "$matching_files" | sort -u
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
  note "Structural conformance OK: $(printf '%s\n' "$observed" | grep -c . ) presentation anchors, all declared."
fi

# --- Cardinality evidence is explicit rather than implied for every row -----
executable_count=0
structural_only_count=0
coverage=$(printf '%s\n' "$manifest" | awk -F '\t' 'NF == 8 { print $1 "\t" $8 }')
while IFS=$'\t' read -r effect verification; do
  [ -z "$effect" ] && continue
  case "$verification" in
    executable=*)
      reference=${verification#executable=}
      proof_file=${reference%%#*}
      proof_marker=${reference#*#}
      if [ "$proof_file" = "$reference" ] || [ -z "$proof_file" ] || [ -z "$proof_marker" ]; then
        problem "$effect has malformed executable evidence '$verification'"
      elif [ ! -f "$proof_file" ]; then
        problem "$effect evidence file is missing: $proof_file"
      elif ! grep -qF "$proof_marker" "$proof_file"; then
        problem "$effect evidence marker is missing from $proof_file: $proof_marker"
      fi
      executable_count=$((executable_count + 1))
      ;;
    structural-only)
      structural_only_count=$((structural_only_count + 1))
      ;;
    *)
      problem "$effect has unknown verification status '$verification'"
      ;;
  esac
done <<< "$coverage"
note "Cardinality coverage: $executable_count executable, $structural_only_count structural-only."

# --- Classes 3 & 4: run the declared executable timeline evidence -----------
note "Running behavioral property tests (swift run EdgeStashLogicTests)…"
run_logic_tests() {
  if [ "$(uname -s)" = "Darwin" ] && [ -z "${DEVELOPER_DIR:-}" ] \
      && [ -d /Applications/Xcode.app/Contents/Developer ]; then
    DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift run EdgeStashLogicTests
  else
    swift run EdgeStashLogicTests
  fi
}
if run_logic_tests; then
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
