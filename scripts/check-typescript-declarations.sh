#!/usr/bin/env bash
# Compiles every TypeScript declaration CodeMode generates with `tsc --strict`.
#
# The Swift tests check known failure shapes (reserved-word function names, for
# one); only a real compiler checks that the output is valid TypeScript at all.
#
#   scripts/check-typescript-declarations.sh [output-dir]
#
# TSC overrides the compiler command, e.g. `TSC=tsc` to use a local install.
# Default: TypeScript 7.0.2 via npx.
set -euo pipefail

cd "$(dirname "$0")/.."
out="${1:-$(mktemp -d)}"
rm -rf "$out"
mkdir -p "$out"
tsc_cmd="${TSC:-npx --yes --package typescript@7.0.2 tsc}"

echo "Writing declarations to $out"
CODEMODE_DTS_OUTPUT="$out" swift test --filter writeTypeDeclarationsForCompilerCheck

surfaces=$(find "$out/surfaces" -name '*.d.ts' | wc -l | tr -d ' ')
fragments=$(find "$out/fragments" -name '*.d.ts' | wc -l | tr -d ' ')
# Guard against a vacuous pass: a filter typo or a skipped test would leave
# nothing for tsc to check, and an empty compilation succeeds.
if [ "$surfaces" -ne 3 ] || [ "$fragments" -lt 100 ]; then
    echo "error: expected 3 surfaces and 100+ fragments, found $surfaces and $fragments" >&2
    exit 1
fi

# One compilation, not 124. The preamble stays a global script so fragments can
# use `CodeModeValue`, as they would in a host prompt. Each surface and fragment
# becomes its own module, so their top-level `declare const apple` stay local
# instead of colliding — each is checked exactly as it would be used alone.
for file in "$out"/surfaces/*.d.ts "$out"/fragments/*.d.ts; do
    printf '\nexport {};\n' >> "$file"
done

cat > "$out/tsconfig.json" <<'JSON'
{
  "compilerOptions": {
    "strict": true,
    "noEmit": true,
    "lib": ["es2022"],
    "types": [],
    "skipLibCheck": false
  },
  "include": ["preamble.d.ts", "surfaces/*.d.ts", "fragments/*.d.ts"]
}
JSON

echo "Compiling $surfaces surfaces and $fragments fragments with: $tsc_cmd"
listed=$($tsc_cmd -p "$out/tsconfig.json" --listFilesOnly | grep -c "$out" || true)
expected=$((surfaces + fragments + 1))
if [ "$listed" -lt "$expected" ]; then
    echo "error: tsc would check $listed of $expected declaration files" >&2
    exit 1
fi

$tsc_cmd -p "$out/tsconfig.json"
echo "OK: all $expected declaration files compile under --strict"
