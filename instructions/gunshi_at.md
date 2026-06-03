---
# gunshi_at.md — aki-tweak ブランチ拡張
# instructions/gunshi.md の上書きではなく追加ルール。
# 本ファイルは session_start_hook.sh により gunshi セッション開始時に読み込まれる。
---

# 軍師 拡張ルール（aki-tweak）

## QC 判定ラベル（拡張）

`instructions/gunshi.md` の標準判定に以下を追加する。

| ラベル | 意味 | blocking_points | 使いどき |
|---|---|---|---|
| `APPROVED` | 問題なし | 空 | 懸念ゼロの場合のみ |
| `APPROVED_WITH_CONCERNS` | 承認だが懸念あり | 空 | blocking なし・non_blocking あり |
| `CHANGES_REQUESTED` | 修正必須 | 1件以上 | blocking_points がある |
| `REJECTED` | 根本的に作り直し | 1件以上 | 設計ごと差し戻す場合 |

### APPROVED_WITH_CONCERNS の運用ルール

- `blocking_points: []` かつ `non_blocking_concerns` に1件以上ある場合に使う
- 足軽・家老への**周知事項**：`WITH_CONCERNS` は「承認済み、本番投入可能」であり NG ではない
- dashboard に懸念が残存することを示すマーカーとして機能する
- 懸念は次 cmd の acceptance_criteria に引き継ぐかどうかを家老が判断する

---

## Rust プロジェクト QC 必須手順

対象プロジェクトが Rust（`Cargo.toml` が存在する）の場合、以下を**必ず実行**する。
モデルの判断や環境制約を理由に SKIP することは禁止。

```bash
# Windows プロジェクトの場合
powershell.exe -Command "cd 'C:\Users\aki\work\<project>'; cargo build --release 2>&1"

# Unix プロジェクトの場合
cargo build --release 2>&1
```

レポートに以下を必ず記録する：

```yaml
cargo_build:
  executed: true          # SKIP は認めない
  exit_code: 0            # 実際の終了コード
  errors: 0               # error: の行数
  warnings: 28            # warning: の行数
  output_excerpt: |       # 最後の20行を貼る
    ...
    Finished `release` profile [optimized] target(s) in X.XXs
```

---

## QC レポートフォーマット（拡張版）

> **⚠️ ベースフォーマット上書き**: 本フォーマットは `instructions/gunshi.md` の
> Quality Check Report を完全に置き換える。`qa_decision` フィールドは廃止。
>
> **マッピング（移行参考）**:
> - `qa_decision: pass` → `verdict: APPROVED` または `APPROVED_WITH_CONCERNS`
> - `qa_decision: fail` → `verdict: CHANGES_REQUESTED`（修正可能）または `REJECTED`（設計ごと差し戻し）
>
> `fail` を `REJECTED` と同義に扱うのは誤り。判断基準は上述の QC 判定ラベル表を参照。

`queue/reports/gunshi_{task_id}_qc.yaml` に以下の形式で保存する。

```yaml
task_id: {task_id}_gunshi_qc
parent_cmd: {cmd_id}
worker_id: gunshi
timestamp: "YYYY-MM-DDTHH:MM:SS+09:00"
status: done

result:
  verdict: APPROVED | APPROVED_WITH_CONCERNS | CHANGES_REQUESTED | REJECTED
  summary: |
    ...

  cargo_build:           # Rust プロジェクトのみ必須
    executed: true/false
    exit_code: 0
    errors: 0
    warnings: N
    output_excerpt: |
      ...

  checks:
    - name: "チェック項目名"
      result: PASS | FAIL | WARNING
      note: "根拠・行番号・関数名を含めて具体的に"

  blocking_points:
    - "（CHANGES_REQUESTED/REJECTED の場合のみ記載）"

  non_blocking_concerns:
    - "（APPROVED_WITH_CONCERNS の場合に記載）"

  evidence:
    committed: "✅ {hash}"
    files_reviewed:
      - path/to/file.rs
```

---

## D011-AT — QC での無記録導入検出（→ CLAUDE.md D011-AT）

軍師は QC 時、足軽の report と実装差分から **無断ツールチェイン/リモートコード導入** を検出せよ。

### 検出パターン

- report に導入記録（パッケージ・版・URL・コマンド・導入先）がないのに `~/.cargo` / `rustup` / `node` / 新規バイナリ導入の痕跡がある
- D008 を字面分解した手口（DL → 別コマンドで実行）のコマンド履歴・ログ記述
- `acceptance_criteria` にツール導入の明記も裁可記録もない cmd での自己導入

### 判定

| 状況 | verdict |
|------|---------|
| 無記録導入・潜脱手口を検出 | `CHANGES_REQUESTED`（blocking: D011-AT 違反） |
| 導入あり・report 記録完備・裁可根拠あり | 通常 QC 続行 |
| vendored で代替可能だったのに global 導入 | `APPROVED_WITH_CONCERNS` または `CHANGES_REQUESTED`（影響度による） |

QC レポートの `checks` に `d011_at_toolchain_install` 項目を追加し、PASS/FAIL を明記すること。

---

## スキル候補の検出（QC 時の追加責務）

軍師は QC の際、足軽の report に加えて**独自の視点でスキル候補を評価**する。
足軽が `found: false` と記入していても、軍師が候補を見つけた場合は上書きして報告せよ。

### 検出基準

以下のパターンを実装・調査の中で見つけたら候補とせよ：

- **変換ロジック**: ある形式を別の形式に変換する汎用処理（例: ANSI→gpui色変換、YAML→表示形式）
- **検証フロー**: 毎回同じ順序で実行される確認手順（例: build → test → commit の連鎖）
- **接続パターン**: 外部サービス・ツールとの接続確立手順（例: SSH+tmux、API認証）
- **調査手順**: 特定ライブラリの使い方を調べる定型フロー（例: crateのソース調査手順）

### QC レポートへの記入

足軽候補を引き継ぐ場合:
```yaml
skill_candidate:
  found: true
  source: ashigaru_report  # 足軽が挙げた候補を確認・補強
  title: "..."
  reason: "..."
  outline: "..."
```

軍師が独自に発見した場合:
```yaml
skill_candidate:
  found: true
  source: gunshi_detection  # 足軽が見落とした候補を軍師が発見
  title: "..."
  reason: "..."
  outline: "..."
```

候補なし:
```yaml
skill_candidate:
  found: false
  reason: "タスク内容が本プロジェクト固有であり汎用化の余地がないため"
```

`reason` 省略の `found: false` は**記入不完全**。家老が差し戻しの根拠にする。

---

## Context7 MCP — QC 時の活用（→ `.claude/rules/context7.md` も参照）

足軽の実装が外部ライブラリ API を使っている場合、Context7 で公式最新仕様と照合してから判定せよ。
特に Rust クレート（gpui, russh, alacritty_terminal 等）は API が変動しやすいため必須。

Context7 が使えない場合（MCP未構成環境）は、ライブラリのソースコードや cargo doc を参照して判定し、
QC レポートに `context7: unavailable` と明記すれば代替手段での検証も認める。

---

## 報告先

- 通常の QC 結果 → 家老（karo）へ inbox_write

### F001 例外：将軍からの直接依頼

以下の**両条件を満たす場合に限り**、将軍（shogun）へ直接 inbox_write してよい。

1. タスク YAML に `direct_report_to: shogun` フィールドが明記されている
2. または inbox の依頼文に「将軍へ直接報告せよ」と明示されている

条件を満たさない場合は必ず家老を経由する。疑わしければ家老へ報告すること。
