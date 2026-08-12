#!/usr/bin/env bash
# lib/stale_task_detect.sh — assigned 沈黙検知（純粋判定。tmux / inbox 非依存）
#
# ═══ 失敗経路表（三欄）═══
# | 検知できるか | 検知したらどう倒れるか | 検知できぬならなぜか |
# |---|---|---|
# | L0 死署名（既知文字列当てはめ） | assigned≥2min + 署名一致 → agent_stale 通知（補助・速報） | 新しい壊れ方は未知の文字列。一覧に無ければ原理的に取りこぼす |
# | L1 沈黙（30min、本命） | 最終活動が L1 窓外 + assigned → agent_stale 通知 | busy ならスキップ。直近30分以内に活動があればスキップ（fail-closed） |
# | L2 再通知（90min） | L1 以降も沈黙継続 → 同一 task で L2 を一度通知 | L1 未通知なら L2 単独では出さない（段階通知） |
# | L_pane（pane 不在） | assigned≥2min + busy_rc=2 → agent_stale 通知（死署名不要） | busy_rc=0 はスキップ。pane 消失を黙殺しない |
# | registry 絞り自身の失敗 | 無し/読めぬ/空 → 全エージェント（ashigaru1-7/gunshi/karo）へ fallback | 対象ゼロで黙って通るな（fail-open 禁止） |
# | report が assigned_at 以降に存在 | スキップ条件に「使わない」 | assigned_at 以降 1 回報告しただけでは永久免除にならない（fail-open 禁止） |
# | 家老が対象 | 将軍 inbox（夜間特例: type=agent_stale from=watcher） | 通常の家老→将軍 inbox 禁止の例外経路 |
# | 他エージェントが対象 | 家老 inbox | — |
# | busy（稼働中） | 通知しない | agent_is_busy_check=0 の間は沈黙とみなさない |
# | 同一 (agent, task_id, level) | 連打禁止（state で dedup） | — |
#
# L0 は速さの補助。L1 沈黙が本命の網。

# ── 閾値（秒）──
readonly STALE_L0_MIN_ASSIGNED_SEC=120    # 2min
readonly STALE_L1_SILENCE_SEC=1800          # 30min
readonly STALE_L2_SILENCE_SEC=5400          # 90min

stale_death_signatures() {
    # 既知の「死」UI 文字列。新しい障害はここに追加するまで L0 は取りこぼす。
    printf '%s\n' \
        'Unable to reach the model provider'
}

stale_pane_has_death_signature() {
    local pane_text="${1:-}"
    local sig
    [ -n "$pane_text" ] || return 1
    while IFS= read -r sig; do
        [ -z "$sig" ] && continue
        if [[ "$pane_text" == *"$sig"* ]]; then
            return 0
        fi
    done < <(stale_death_signatures)
    return 1
}

stale_iso_to_epoch() {
    local ts="${1:-}"
    [ -n "$ts" ] || return 1
    date -d "$ts" +%s 2>/dev/null || date -j -f "%Y-%m-%dT%H:%M:%S%z" "${ts//+09:00/+0900}" +%s 2>/dev/null
}

stale_last_activity_epoch() {
    # 最終活動 = max(assigned_at, 当該 task_id の report mtime, task YAML mtime)
    local assigned_epoch="${1:-0}"
    local report_mtime_epoch="${2:-0}"
    local task_mtime_epoch="${3:-0}"
    local max="$assigned_epoch"
    [ "$report_mtime_epoch" -gt "$max" ] && max="$report_mtime_epoch"
    [ "$task_mtime_epoch" -gt "$max" ] && max="$task_mtime_epoch"
    echo "$max"
}

stale_silence_seconds() {
    local last_activity_epoch="${1:-0}"
    local now_epoch="${2:-0}"
    echo $(( now_epoch - last_activity_epoch ))
}

stale_should_skip_l1() {
    # 直近 L1 窓（30分）内に最終活動があればスキップ（return 0=skip）。
    # assigned_at 以降に report があるだけではスキップしない（fail-open 禁止）。
    local last_activity_epoch="${1:-0}"
    local now_epoch="${2:-0}"
    local silence
    silence=$(stale_silence_seconds "$last_activity_epoch" "$now_epoch")
    [ "$silence" -lt "$STALE_L1_SILENCE_SEC" ]
}

stale_notify_target_for_agent() {
    local agent="${1:-}"
    if [ "$agent" = "karo" ]; then
        echo shogun
    else
        echo karo
    fi
}

stale_dedup_key() {
    local agent="$1" task_id="$2" level="$3"
    printf '%s|%s|%s' "$agent" "$task_id" "$level"
}

stale_already_notified() {
    # state_file に "agent|task_id|level" 行があれば return 0
    local state_file="$1" agent="$2" task_id="$3" level="$4"
    local key
    key=$(stale_dedup_key "$agent" "$task_id" "$level")
    [ -f "$state_file" ] || return 1
    grep -qxF "$key" "$state_file" 2>/dev/null
}

stale_record_notification() {
    local state_file="$1" agent="$2" task_id="$3" level="$4"
    local key dir
    key=$(stale_dedup_key "$agent" "$task_id" "$level")
    dir=$(dirname "$state_file")
    mkdir -p "$dir"
    if ! stale_already_notified "$state_file" "$agent" "$task_id" "$level"; then
        echo "$key" >> "$state_file"
    fi
}

# stale_evaluate_levels <status> <busy_rc> <assigned_epoch> <last_activity_epoch> <now_epoch> <pane_text>
# busy_rc: 0=busy, 1=idle, 2=pane absent
# 出力: 発火すべきレベル（L0 / L1 / L2 / L_pane）を1行ずつ。該当なしなら無出力。
stale_evaluate_levels() {
    local status="$1"
    local busy_rc="$2"
    local assigned_epoch="$3"
    local last_activity_epoch="$4"
    local now_epoch="$5"
    local pane_text="$6"

    [ "$status" = "assigned" ] || return 0

    local assigned_age silence
    assigned_age=$(( now_epoch - assigned_epoch ))

    # busy（稼働中）は全レベル対象外
    [ "$busy_rc" -eq 0 ] && return 0

    # pane 不在: L_pane のみ（死署名不要・2min 以上 assigned）
    if [ "$busy_rc" -eq 2 ]; then
        if [ "$assigned_age" -ge "$STALE_L0_MIN_ASSIGNED_SEC" ]; then
            echo L_pane
        fi
        return 0
    fi

    silence=$(stale_silence_seconds "$last_activity_epoch" "$now_epoch")

    # L0: 死署名（補助・2min 以上 assigned）
    if [ "$assigned_age" -ge "$STALE_L0_MIN_ASSIGNED_SEC" ]; then
        if stale_pane_has_death_signature "$pane_text"; then
            echo L0
        fi
    fi

    # L1: 沈黙本命（fail-closed: 直近30分以内の活動が無い）
    if ! stale_should_skip_l1 "$last_activity_epoch" "$now_epoch"; then
        if [ "$silence" -ge "$STALE_L1_SILENCE_SEC" ]; then
            echo L1
        fi
    fi

    # L2: 90min 再通知（L1 窓を大幅に超えた沈黙）
    if [ "$silence" -ge "$STALE_L2_SILENCE_SEC" ]; then
        echo L2
    fi
}

stale_fallback_target_agents() {
    printf '%s\n' \
        ashigaru1 ashigaru2 ashigaru3 ashigaru4 ashigaru5 ashigaru6 ashigaru7 \
        gunshi karo
}

stale_read_registry_agents_from_settings() {
    local settings="${1:-}"
    [ -f "$settings" ] || return 0
    [ -r "$settings" ] || return 1

    awk '
        /^[[:space:]]*#/ || /^[[:space:]]*$/ { next }

        /^cli:[[:space:]]*$/ {
            in_cli = 1
            in_agents = 0
            next
        }

        in_cli && /^[^[:space:]]/ {
            in_cli = 0
            in_agents = 0
        }

        in_cli && /^[[:space:]]{2}agents:[[:space:]]*$/ {
            in_agents = 1
            next
        }

        in_agents {
            if ($0 !~ /^[[:space:]]{4}/) {
                exit
            }
            if ($0 ~ /^[[:space:]]{4}[A-Za-z0-9_-]+:[[:space:]]*/) {
                line = $0
                sub(/^[[:space:]]*/, "", line)
                sub(/:.*/, "", line)
                print line
            }
        }
    ' "$settings"
}

stale_registry_is_usable() {
    local settings="${1:-}"
    local agents=() agent

    [ -f "$settings" ] || return 1
    [ -r "$settings" ] || return 1

    while IFS= read -r agent; do
        [ -n "$agent" ] && agents+=("$agent")
    done < <(stale_read_registry_agents_from_settings "$settings")

    [ "${#agents[@]}" -gt 0 ] || return 1

    for agent in "${agents[@]}"; do
        [ "$agent" = "karo" ] && return 0
    done
    return 1
}

# stale_resolve_scan_targets <settings_path>
# registry が使えるときは布陣内エージェントのみ。無し/読めぬ/空なら全エージェントへ fallback（決して空を返さない）。
stale_resolve_scan_targets() {
    local settings="${1:-}"
    local agents=() agent count=0

    if stale_registry_is_usable "$settings"; then
        while IFS= read -r agent; do
            [ "$agent" = "shogun" ] && continue
            [ -n "$agent" ] || continue
            agents+=("$agent")
            count=$((count + 1))
        done < <(stale_read_registry_agents_from_settings "$settings")
        if [ "$count" -gt 0 ]; then
            printf '%s\n' "${agents[@]}"
            return 0
        fi
    fi

    stale_fallback_target_agents
}

stale_scan_target_agents() {
    local root
    root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    stale_resolve_scan_targets "${STALE_SETTINGS_FILE:-$root/config/settings.yaml}"
}

stale_read_task_field() {
    local task_file="$1"
    local field="$2"
    [ -f "$task_file" ] || return 1
    awk -v want="$field" '
        $0 ~ "^[[:space:]]*" want "[[:space:]]*:" {
            sub(/^[^:]*:[[:space:]]*/, "", $0)
            gsub(/^"/, "", $0)
            gsub(/"$/, "", $0)
            print $0
            exit
        }
    ' "$task_file"
}

stale_report_mtime_for_task() {
    local project_root="$1"
    local agent="$2"
    local want_task_id="$3"
    local report_file="$project_root/queue/reports/${agent}_report.yaml"
    [ -f "$report_file" ] || { echo 0; return 0; }
    local report_task_id
    report_task_id=$(stale_read_task_field "$report_file" task_id)
    if [ "$report_task_id" = "$want_task_id" ]; then
        stat -c %Y "$report_file" 2>/dev/null || stat -f %m "$report_file" 2>/dev/null || echo 0
    else
        echo 0
    fi
}

stale_task_file_mtime() {
    local task_file="$1"
    [ -f "$task_file" ] || { echo 0; return 0; }
    stat -c %Y "$task_file" 2>/dev/null || stat -f %m "$task_file" 2>/dev/null || echo 0
}
