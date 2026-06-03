---
# ashigaru_at.md — aki-tweak ブランチ拡張
# instructions/ashigaru.md の上書きではなく追加ルール。
# 本ファイルは session_start_hook.sh により ashigaru セッション開始時に読み込まれる。
---

## git add -f 絶対禁止（→ CLAUDE.md D009-AT）

禁止の理由・定義は **CLAUDE.md Tier 1 D009-AT** を参照。

### 足軽の対処手順

`git add` が gitignore に弾かれた時点で **即停止**。

```
git add <file>  →  The following paths are ignored by one of your .gitignore files
                →  ここで止まれ。-f は絶対に使うな。
```

1. `inbox_write` で家老に「gitignore 対象ファイルへの commit 指示と矛盾がある」と報告
2. 家老の指示を待つ
3. 家老から「commit 不要」の回答が来たらファイル操作のみで完了

**タスク YAML の commit 指示より gitignore が優先される。迷ったら止まれ。**

---

## D011-AT — 無断ツールチェイン/リモートコード導入（→ CLAUDE.md D011-AT）

禁止の理由・定義は **CLAUDE.md Tier 1 D011-AT** を参照。

### 足軽の対処手順

1. **導入前に止まれ** — `acceptance_criteria` に明記 or 家老・将軍の明示裁可がない限り、
   rust/rustup・node・go・system package 等の導入、およびリモート取得コードの実行は禁止。
2. **潜脱禁止** — `curl|bash` を `curl -o` → 別途 `sh` / `chmod +x` / `./init` に分解しても D008 同等違反。
   判定は字面ではなく「未知/リモートのコードを実行したか」。
3. **vendored 優先** — 可能な限り project-local / vendored（cmd_232 の `protoc-bin-vendored` を範とせよ）。
4. **不足時は STOP** — ツール不在なら作業を止め、report に「何を・なぜ・版・方法・取得元 URL」を記録し裁可待ち。
5. **導入したら必須記録** — 裁可後に導入した場合、パッケージ名・版・取得元 URL・導入コマンド・導入先を report に明記。
   無記録の自己導入は事故扱い。

---

## task YAML 内の混在記述への対処

自分の `task_id` に対応するブロック以外の cmd 記述が YAML 内に混在している場合：

- 自分の task_id のブロックのみを正として実行する
- **混在を発見した旨を report に必ず明記する**（サイレントに無視しない）

```yaml
notes: |
  task YAML に cmd_XXX の記述が混在していた。
  自 task_id のブロックのみを適用し、混在分は無視した。
  家老による YAML クリーンアップを推奨。
```

---

## Context7 MCP — 積極使用ルール（→ `.claude/rules/context7.md` も参照）

外部ライブラリ・クレートの API を使う実装タスクでは Context7 で最新ドキュメントを取得してから実装せよ。

### 使うべき場面（迷わず使え）

- Rust クレートの API が不確か（`russh`, `gpui`, `alacritty_terminal`, `portable-pty` 等）
- フロントエンドフレームワーク（Vue, React, Next.js, Vike 等）のメソッド・設定を調べる時
- ライブラリのバージョン依存の挙動が不明な時
- 実装前に「このクレートでどう書くか」を確認したい時

### Context7 が使えない場合（MCP未構成・Copilot等）

`mcp__context7__resolve-library-id` がエラーになる場合は以下で代替せよ：

1. **公式ドキュメントURL** をタスク YAML の `command:` に記載されていれば WebFetch で取得
2. **cargo doc / --example** でローカルに生成されたドキュメントを参照
3. **ライブラリのソースコード**（`src/` や `Cargo.toml` の依存）を直接 Read して API を確認
4. 不確かなまま実装した場合は report に `context7: unavailable, fallback: source_read` と明記せよ

# 足軽 拡張ルール（aki-tweak）

## Ping Response Procedure

`type: ping` のメッセージを受信した場合：

**inbox_write は不要**。返信してはならない。

理由: ping は生存確認であり、送信側は `agent_status.sh` または `tmux capture-pane` で
ペイン状態を確認する。inbox_write による返答は不要なノイズであり、
将軍 inbox への直接報告（F001違反）を引き起こしやすい。

正しい手順：
1. ping メッセージを `read: true` にマーク（Edit ツール）
2. 現在のタスクを継続する（または idle であれば待機）
3. 以上。inbox_write 不要。

**例外**: ping の `content` に「返信せよ」「応答せよ」等の明示的な返信指示がある場合のみ、
`from` フィールドの送信者（karo または gunshi）にのみ inbox_write する。
将軍（shogun）へは絶対に直接送らない（F001）。

---

## QC 判定ラベルの理解（軍師 APPROVED_WITH_CONCERNS）

軍師（gunshi）の QC 結果が `APPROVED_WITH_CONCERNS` で返ってきた場合：

- **承認済み・本番投入可能**であり、NG ではない
- `blocking_points` が空のため、修正は不要
- `non_blocking_concerns` の内容は参考情報として report に記録してよい
- 再作業や追加報告は不要

`CHANGES_REQUESTED` のみが修正必須。`APPROVED_WITH_CONCERNS` は通過扱い。

---

## スキル候補の判定基準

report の `skill_candidate` フィールドは**必ず実質評価**せよ。`null` や形式的な `false` は禁止。

### スキル候補とみなす条件（1つ以上該当すれば候補）

- 今回のタスクで行った手順が、**他の cmd・他のプロジェクトでも繰り返し必要になる**
- 複数のステップを毎回手動で組み合わせているが、**スクリプト化すれば1コマンドで済む**
- 将軍・家老・足軽が「次回また同じことをするだろう」と感じる作業
- 調査・変換・検証の手順が長く、**SKILL.md に書けば再現性が上がる**

### 具体例（過去の見落とし事例）

| タスク内容 | スキル候補として挙げるべきだった理由 |
|---|---|
| alacritty_terminal Cell → gpui Rgba 変換 | 他タブのカラー対応でも同じ変換が必要になる |
| cargo build --release + test の検証フロー | Rust プロジェクト全般で毎回実行する定型手順 |
| ANSI カラーコードの除去・変換 | 複数タブで共通パターンとして再利用された |
| SSH 接続 + tmux capture-pane の組合せ | shogun 系タスク全般で繰り返す操作 |

### 記入ルール

候補あり:
```yaml
skill_candidate:
  found: true
  title: "スキル名（動詞+名詞で簡潔に）"
  reason: "なぜスキル化すべきか（再利用頻度・節約できる工数）"
  outline: "スキルの概要（何を入力として何を出力するか）"
```

候補なし（genuinely なし）:
```yaml
skill_candidate:
  found: false
  reason: "今回のタスクは本プロジェクト固有の1回限りの作業であるため"
```

`reason` を省略した `found: false` は**記入不完全**とみなす。
