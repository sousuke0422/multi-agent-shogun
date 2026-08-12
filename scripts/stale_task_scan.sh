#!/usr/bin/env bash
# stale_task_scan.sh — assigned 沈黙検知の1 tick（watcher_supervisor から呼ぶ）
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$SCRIPT_DIR"

# shellcheck source=lib/stale_task_detect.sh
source "$SCRIPT_DIR/lib/stale_task_detect.sh"
# shellcheck source=lib/agent_status.sh
source "$SCRIPT_DIR/lib/agent_status.sh"
# shellcheck source=lib/agent_registry.sh
source "$SCRIPT_DIR/lib/agent_registry.sh"

STALE_STATE_FILE="${STALE_STATE_FILE:-$SCRIPT_DIR/queue/stale_notify_state.txt}"
NOW_EPOCH=$(date +%s)

get_multiagent_pane_base() {
    if [ -n "${SHOGUN_PANE_BASE:-}" ]; then
        echo "$SHOGUN_PANE_BASE"
        return 0
    fi
    tmux show-options -gv pane-base-index 2>/dev/null || echo 0
}

stale_send_notification() {
    local agent="$1" task_id="$2" level="$3" silence="$4" parent_cmd="${5:-}"
    local target msg

    target=$(stale_notify_target_for_agent "$agent")
    msg="[agent_stale ${level}] ${agent} task=${task_id} parent=${parent_cmd} silence=${silence}s — assigned 沈黙を検知。自動振り直しなし。"

    bash "$SCRIPT_DIR/scripts/inbox_write.sh" "$target" "$msg" agent_stale watcher
    stale_record_notification "$STALE_STATE_FILE" "$agent" "$task_id" "$level"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [STALE] ${level} ${agent} ${task_id} → ${target}" >&2
}

stale_scan_once() {
    local pane_base agent pane_target task_file status task_id assigned_at
    local assigned_epoch report_mtime task_mtime last_activity silence
    local busy_rc pane_text cli level parent_cmd

    pane_base=$(get_multiagent_pane_base)

    while IFS= read -r agent; do
        [ -n "$agent" ] || continue
        task_file="$SCRIPT_DIR/queue/tasks/${agent}.yaml"
        status=$(stale_read_task_field "$task_file" status || true)
        [ "$status" = "assigned" ] || continue

        task_id=$(stale_read_task_field "$task_file" task_id || true)
        assigned_at=$(stale_read_task_field "$task_file" assigned_at || true)
        parent_cmd=$(stale_read_task_field "$task_file" parent_cmd || true)
        [ -n "$task_id" ] || continue
        [ -n "$assigned_at" ] || continue

        assigned_epoch=$(stale_iso_to_epoch "$assigned_at" || echo 0)
        [ "$assigned_epoch" -gt 0 ] || continue

        report_mtime=$(stale_report_mtime_for_task "$SCRIPT_DIR" "$agent" "$task_id")
        task_mtime=$(stale_task_file_mtime "$task_file")
        last_activity=$(stale_last_activity_epoch "$assigned_epoch" "$report_mtime" "$task_mtime")
        silence=$(stale_silence_seconds "$last_activity" "$NOW_EPOCH")

        if ! pane_target=$(agent_registry_pane_for_agent "$agent" "$pane_base" 2>/dev/null); then
            continue
        fi

        cli=$(tmux show-options -p -t "$pane_target" -v @agent_cli 2>/dev/null || echo "")
        busy_rc=1
        agent_is_busy_check "$pane_target" "$cli" || busy_rc=$?

        pane_text=""
        pane_text=$(timeout 2 tmux capture-pane -t "$pane_target" -p 2>/dev/null || true)

        while IFS= read -r level; do
            [ -n "$level" ] || continue
            if stale_already_notified "$STALE_STATE_FILE" "$agent" "$task_id" "$level"; then
                continue
            fi
            stale_send_notification "$agent" "$task_id" "$level" "$silence" "$parent_cmd"
        done < <(stale_evaluate_levels "$status" "$busy_rc" "$assigned_epoch" "$last_activity" "$NOW_EPOCH" "$pane_text")
    done < <(stale_scan_target_agents)
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    stale_scan_once
fi
