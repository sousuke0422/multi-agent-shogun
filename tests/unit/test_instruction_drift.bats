#!/usr/bin/env bats
# check_instruction_drift.sh tests (cmd_712)
#
# Verifies the drift detector itself:
# - negative case: repo sources/generated files are in sync → 0 missing
# - positive control: an artificially removed section line IS detected
#   (feedback_positive_control_before_concluding — a detector that never
#   fires on a known defect proves nothing when it reports success)

setup() {
    TEST_TMP="$(mktemp -d)"
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    SCRIPT="$PROJECT_ROOT/scripts/check_instruction_drift.sh"

    mkdir -p "$TEST_TMP/instructions/generated"
    for role in karo ashigaru; do
        cp "$PROJECT_ROOT/instructions/${role}.md" "$TEST_TMP/instructions/"
        for prefix in "" codex- copilot- kimi- opencode- cursor-; do
            cp "$PROJECT_ROOT/instructions/generated/${prefix}${role}.md" \
               "$TEST_TMP/instructions/generated/"
        done
    done
}

teardown() {
    rm -rf "$TEST_TMP"
}

@test "instruction_drift: repo sources and generated files are in sync (0 missing)" {
    run env DRIFT_ROOT="$TEST_TMP" bash "$SCRIPT" karo ashigaru
    [ "$status" -eq 0 ]
    [[ "$output" == *"RESULT: 0 missing"* ]]
}

@test "instruction_drift: positive control — removed section line is detected" {
    # Remove a known representative line (RACE-001 example) from one
    # generated file to simulate "source body never reached the output".
    target="$TEST_TMP/instructions/generated/codex-karo.md"
    grep -v '❌ ashigaru1 → output.md + ashigaru2 → output.md  (conflict!)' \
        "$target" > "$target.tmp"
    mv "$target.tmp" "$target"

    run env DRIFT_ROOT="$TEST_TMP" bash "$SCRIPT" karo ashigaru
    [ "$status" -eq 1 ]
    [[ "$output" == *"MISSING: karo :: RACE-001"* ]]
    [[ "$output" == *"codex-karo.md"* ]]
}

@test "instruction_drift: missing generated file is a hard error" {
    rm "$TEST_TMP/instructions/generated/kimi-ashigaru.md"
    run env DRIFT_ROOT="$TEST_TMP" bash "$SCRIPT" karo ashigaru
    [ "$status" -eq 2 ]
}
