#!/usr/bin/env bash
# ============================================================
# Instruction Drift Check
# ============================================================
# Verifies that every section of the hand-written source file
# instructions/{role}.md has its "representative line" present in ALL
# generated per-CLI instruction files (instructions/generated/*).
#
# Why: build_instructions.sh extracts only the YAML front matter from
# instructions/{role}.md — the body is composed from roles/*_role.md +
# common/*.md + cli_specific/*_tools.md. Any section written only in the
# hand-written {role}.md body silently never reaches non-Claude CLIs.
# The existing CI check (`git diff --exit-code instructions/generated/`)
# only detects "forgot to run the build" — NOT "source body never made it
# into the generated output". This check covers that second axis.
#
# Method (cmd_712 / gunshi_712_001):
#   1. Skip YAML front matter of instructions/{role}.md
#   2. For each `##` / `###` heading, pick a representative line:
#      the longest non-empty line that is not a heading, table row (`|`),
#      code fence (```), or `---`. Sections containing only tables/fences
#      are skipped (表|行は代表行に使わない — gunshi_712_001 spec); their
#      decisions are covered by common/forbidden_actions.md etc.
#   3. `grep -F` the representative line in every generated file of the
#      role. Any miss → "MISSING: ..." and exit 1.
#
# Usage:
#   bash scripts/check_instruction_drift.sh              # default: karo ashigaru
#   bash scripts/check_instruction_drift.sh karo         # one role
#   bash scripts/check_instruction_drift.sh all          # karo ashigaru shogun gunshi
#
# Note: shogun/gunshi are NOT in the default set yet — their role.md/common
# absorption is deferred (gunshi_712_001 recommendation). Run with `all` to
# see their current drift.
#
# Env:
#   DRIFT_ROOT — repo root override (used by tests for positive control)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="${DRIFT_ROOT:-$(dirname "$SCRIPT_DIR")}"
GEN_DIR="$ROOT_DIR/instructions/generated"
CLI_PREFIXES=("" "codex-" "copilot-" "kimi-" "opencode-" "cursor-")

roles=("$@")
if [ "${#roles[@]}" -eq 0 ]; then
    roles=(karo ashigaru)
elif [ "${roles[0]}" = "all" ]; then
    roles=(karo ashigaru shogun gunshi)
fi

# extract_representatives <source.md>
# Prints one line per section: "<section title>\t<representative line>"
extract_representatives() {
    awk '
        function flush_section() {
            # table-only / fence-only sections have best=="" and are skipped
            if (sec != "" && best != "") printf "%s\t%s\n", sec, best
        }
        NR == 1 && /^---[[:space:]]*$/ { infm = 1; next }
        infm { if (/^---[[:space:]]*$/) infm = 0; next }
        /^###?[[:space:]]/ {
            flush_section()
            sec = $0
            sub(/^#+[[:space:]]+/, "", sec)
            best = ""; bestlen = 0
            next
        }
        {
            if (sec == "") next
            line = $0
            sub(/[[:space:]]+$/, "", line)
            if (line == "") next
            if (line ~ /^#/) next
            if (line ~ /^\|/ || line ~ /^```/ || line ~ /^---/) next
            l = length(line)
            if (l > bestlen) { best = line; bestlen = l }
        }
        END { flush_section() }
    ' "$1"
}

missing=0
checked_sections=0
checked_files=0

for role in "${roles[@]}"; do
    src="$ROOT_DIR/instructions/${role}.md"
    if [ ! -f "$src" ]; then
        echo "ERROR: source file not found: $src" >&2
        exit 2
    fi

    gen_files=()
    for prefix in "${CLI_PREFIXES[@]}"; do
        f="$GEN_DIR/${prefix}${role}.md"
        if [ -f "$f" ]; then
            gen_files+=("$f")
        else
            echo "ERROR: generated file not found: $f (run scripts/build_instructions.sh first)" >&2
            exit 2
        fi
    done
    checked_files=$((checked_files + ${#gen_files[@]}))

    while IFS=$'\t' read -r section rep; do
        [ -n "$rep" ] || continue
        checked_sections=$((checked_sections + 1))
        for f in "${gen_files[@]}"; do
            if ! grep -qF -- "$rep" "$f"; then
                echo "MISSING: ${role} :: ${section} :: not found in ${f#"$ROOT_DIR"/}"
                missing=$((missing + 1))
            fi
        done
    done < <(extract_representatives "$src")
done

echo ""
echo "Roles checked: ${roles[*]}"
echo "Sections checked: $checked_sections (representative-line grep against $checked_files generated files)"
if [ "$missing" -gt 0 ]; then
    echo "RESULT: $missing missing"
    exit 1
fi
echo "RESULT: 0 missing"
