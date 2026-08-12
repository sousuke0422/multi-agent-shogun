#!/usr/bin/env bats
# test_stale_task_detect.bats — assigned 沈黙検知 純粋判定テスト

setup() {
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    TEST_TMP="$(mktemp -d)"
    # shellcheck source=lib/stale_task_detect.sh
    source "$PROJECT_ROOT/lib/stale_task_detect.sh"
}

teardown() {
    rm -rf "$TEST_TMP"
}

# ── 陽性対照: 実物文字列で L0 発火 ──
@test "T-STALE-001: L0 fires on real provider error string (positive control)" {
    local pane_text
    pane_text=$'Error: Unable to reach the model provider\nWe'\''re having trouble connecting to the model provider.'
    local now assigned last
    now=1000000
    assigned=$((now - 300))   # assigned 5min ago
    last=$assigned

    run stale_evaluate_levels assigned 1 "$assigned" "$last" "$now" "$pane_text"
    [ "$status" -eq 0 ]
    [[ "$output" == *"L0"* ]]
}

@test "T-STALE-002: L0 does NOT fire without death signature (negative control)" {
    local pane_text="Plan, search, build anything"
    local now assigned last
    now=1000000
    assigned=$((now - 300))
    last=$assigned

    run stale_evaluate_levels assigned 1 "$assigned" "$last" "$now" "$pane_text"
    [ "$status" -eq 0 ]
    [[ "$output" != *"L0"* ]]
}

# ── fail-closed: report が assigned_at 以降にあっても古ければ L1 はスキップしない ──
@test "T-STALE-003: L1 NOT skipped when report exists but activity is older than L1 window (fail-closed)" {
    local now assigned report_epoch last
    now=1000000
    assigned=$((now - 28800))          # 8h ago assigned
    report_epoch=$((now - 25200))      # report 7h ago (after assigned_at, but >30min ago)
    last=$(stale_last_activity_epoch "$assigned" "$report_epoch" 0)

    run stale_should_skip_l1 "$last" "$now"
    [ "$status" -eq 1 ]   # should NOT skip

    run stale_evaluate_levels assigned 1 "$assigned" "$last" "$now" ""
    [ "$status" -eq 0 ]
    [[ "$output" == *"L1"* ]]
}

@test "T-STALE-004: L1 skipped when last activity within 30min window" {
    local now last
    now=1000000
    last=$((now - 600))   # 10min ago

    run stale_should_skip_l1 "$last" "$now"
    [ "$status" -eq 0 ]   # skip

    run stale_evaluate_levels assigned 1 "$((now - 3600))" "$last" "$now" ""
    [ "$status" -eq 0 ]
    [[ "$output" != *"L1"* ]]
}

@test "T-STALE-005: busy agent produces no levels" {
    local now assigned last pane_text
    now=1000000
    assigned=$((now - 3600))
    last=$((now - 3600))
    pane_text="Unable to reach the model provider"

    run stale_evaluate_levels assigned 0 "$assigned" "$last" "$now" "$pane_text"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "T-STALE-006: karo routes to shogun, ashigaru routes to karo" {
    [ "$(stale_notify_target_for_agent karo)" = "shogun" ]
    [ "$(stale_notify_target_for_agent ashigaru2)" = "karo" ]
}

@test "T-STALE-007: dedup prevents same agent task_id level twice" {
    local state="$TEST_TMP/state.txt"
    stale_record_notification "$state" ashigaru2 subtask_638_001 L0
    run stale_already_notified "$state" ashigaru2 subtask_638_001 L0
    [ "$status" -eq 0 ]
    run stale_already_notified "$state" ashigaru2 subtask_638_001 L1
    [ "$status" -eq 1 ]
}

@test "T-STALE-008: L2 fires at 90min silence" {
    local now assigned last
    now=1000000
    assigned=$((now - 7200))
    last=$((now - 5500))   # ~91min silence

    run stale_evaluate_levels assigned 1 "$assigned" "$last" "$now" ""
    [ "$status" -eq 0 ]
    [[ "$output" == *"L2"* ]]
}

@test "T-STALE-009: last_activity is max of assigned report and task mtime" {
    local result
    result=$(stale_last_activity_epoch 100 500 300)
    [ "$result" -eq 500 ]
}

@test "T-STALE-010: idle status does not evaluate" {
    run stale_evaluate_levels idle 1 100 100 1000000 "Unable to reach the model provider"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}
