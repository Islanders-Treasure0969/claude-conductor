# Claude Code × GitHub Actions で Symphony 同等システムを社内構築する

> **このドキュメントの目的**
> OpenAI Symphonyのアプローチを、Claude Code + GitHub Actions + GitHub Issues を使って
> 社内で再現するための設計資料。Zenn記事の下書きおよびClaude Codeへの引き渡し用。

---

## 背景・問題意識

### OpenAI Symphony とは

- **公開日**: 2026年4月28日（オープンソース仕様として公開）
- **リポジトリ**: https://github.com/openai/symphony
- **ライセンス**: Apache-2.0

Symphonyは「全てのオープンなタスクをエージェントが自動で拾い上げて完了する」というコンセプトのエージェントオーケストレーター仕様。
Issueトラッカーをコントロールプレーンおよびステートマシンとして使い、
各オープンIssueに対して専用エージェントワークスペースを割り当て、エージェントが常時稼働する。

```
Symphonyのコアコンセプト：
  - Issue = 作業単位（セッションやPRではなく「作業」を管理する）
  - 各Issueに独立したワークスペース
  - エージェントがクラッシュしたら自動再起動
  - チームは「エージェントを監視する」ではなく「作業を管理する」
```

### なぜ Claude Code で再現するのか

- Symphonyは現状Codex（OpenAI）専用。Claude Codeでの利用はコミュニティ実装で不完全
- Claude CodeのHooks・Subagents・CLAUDE.mdエコシステムはSymphonyの要件を満たせる
- GitHub Actionsとの公式統合（`claude-code-action@v1`）が2025年9月にGA
- 社内インフラ（GitHub）をそのままコントロールプレーンとして活用できる

### Symphonyとの機能対応表

| Symphony の要素 | Claude Code + GHA での対応 |
|---|---|
| Linear（コントロールプレーン） | GitHub Issues + Labels |
| Symphonyデーモン（常時ポーリング） | GitHub Actions（event-driven） |
| Codex（エージェント） | Claude Code headless（`claude-code-action@v1`） |
| Per-issue workspace | GHAランナー上の独立チェックアウト環境 |
| チケットステータスのステートマシン | GitHub Issue Labels |
| 再起動・リトライロジック | GHA retry / cleanup workflow |
| Human Review state | PR作成 + `claude-review` ラベル + 1 approve必須 |
| Observability | GHA logs + Issue comments |

---

## アーキテクチャ設計

### 設計原則

1. **TiDD（Ticket-driven Development）**: 全作業はIssueを起点にする
2. **TBD（Trunk-Based Development）**: ブランチは短命。`claude/issue-N` or `adr/issue-N` → すぐmain
3. **1 approve 必須**: エージェントが作成したPRは必ず人間が1件承認する
4. **Triage-first**: Issue作成時に必ず性質を判定し、最適なルートに振り分ける
5. **最小権限**: GHAのpermissionsは必要最小限のみ宣言する

### 全体フロー

```
Issue 作成（opened）
    │
    ▼
[symphony-triage.yml] ──────────────────────────────────────────
  LLMがIssueの内容を分析して3ルートに自動振り分け
    │
    ├─ triage-A（即実装可能）
    │   ↓ 人間が claude-task ラベルを付与
    │   [symphony-dispatch.yml]
    │   実装エージェント起動
    │   → PR作成（ブランチ: claude/issue-N）
    │   → 1 approve → merge
    │   → Issue close
    │
    ├─ triage-B（調査・設計先行）
    │   ↓ 人間が investigation ラベルを付与
    │   [symphony-investigate.yml]
    │   調査エージェント起動
    │   → ADR draft PR作成（ブランチ: adr/issue-N）
    │   → 人間がADR内容を編集・1 approve
    │   → merge
    │   [symphony-decompose.yml]
    │   ADRの「実装チケットへの分解」セクションを読んで
    │   実装チケットを自動生成
    │       → Route A チケット: claude-task ラベル付与 → 実装パイプラインへ
    │       → Route C チケット: 人間対応キューへ
    │
    └─ triage-C（人間主体）
        エージェントは起動しない
        人間が手動でアサイン・対応
```

### ステートマシン（IssueラベルがSymphonyのチケットステータスに対応）

```
# Triageステート
triage-pending        ← Issue作成直後（自動付与）
triage-A              ← 即実装可能と判定
triage-B              ← 調査・設計先行と判定
triage-C              ← 人間主体と判定

# Route A 実装パイプライン
claude-task           ← 実装キュー（人間が付与してエージェント起動）
claude-in-progress    ← エージェント実行中
claude-review         ← PR作成済み・1 approve待ち
claude-failed         ← 要人間介入

# Route B 調査・設計パイプライン
investigation         ← 調査キュー（人間が付与してエージェント起動）
claude-in-progress    ← 調査エージェント実行中（Route Aと共用）
adr-draft             ← ADR PR作成済み・人間レビュー待ち
claude-failed         ← 調査失敗・要人間介入（Route Aと共用）
```

### ワークフローファイル構成

```
.github/
├── workflows/
│   ├── symphony-triage.yml        # ① Issue作成 → 3ルートに自動振り分け
│   ├── symphony-dispatch.yml      # ② claude-task → 実装エージェント起動
│   ├── symphony-investigate.yml   # ③ investigation → 調査エージェント起動
│   ├── symphony-decompose.yml     # ④ ADR merge → 実装チケット自動生成
│   ├── symphony-interactive.yml   # ⑤ @claude メンション対応
│   └── symphony-cleanup.yml       # ⑥ タイムアウト・停滞Issue処理
├── ISSUE_TEMPLATE/
│   ├── claude-task.md             # Route A 用Issueテンプレート
│   └── investigation.md           # Route B 用Issueテンプレート
└── CLAUDE.md                      # エージェント共通コンテキスト（要プロジェクト固有化）

docs/
└── adr/
    └── ADR-000-template.md        # ADRフォーマットテンプレート
```

---

## ADR フォーマット定義

このシステム専用に定義したADRフォーマット。
`symphony-decompose.yml` がこのフォーマットの「実装チケットへの分解」セクションをパースしてIssueを自動生成する。

```markdown
# ADR-{NNN}: {タイトル}

## ステータス
Proposed | Accepted | Deprecated | Superseded

## コンテキスト
Closes #{Issue番号}
{なぜこの意思決定が必要になったか。背景・制約を記述}

## 調査した選択肢

### 選択肢 1: {名前}
- 概要:
- メリット:
- デメリット:
- 参考:

### 選択肢 2: {名前}
- 概要:
- メリット:
- デメリット:
- 参考:

## 決定
{Approveされた選択肢と理由。レビュアーがApprove前に記入する}

## 実装チケットへの分解
<!-- このセクションをsymphony-decompose.ymlがパースしてIssueを自動生成します -->
<!-- 各行に Route A または Route C を明記してください -->
- [ ] {タスク1のタイトル} <!-- Route A -->
- [ ] {タスク2のタイトル} <!-- Route A -->
- [ ] {タスク3のタイトル} <!-- Route C: 理由 -->

## 影響範囲
{変更が及ぶファイル・コンポーネント・チーム}
```

---

## セキュリティ設計

### チェックリスト（実務導入前に全項目を確認）

| # | チェック項目 | 理由 |
|---|---|---|
| ✅ 1 | `ANTHROPIC_API_KEY` はGitHub Secretsに格納 | ワークフローファイルへのハードコード禁止 |
| ✅ 2 | Issue title/body は `env:` 経由でpromptに渡す | コマンドインジェクション対策 |
| ✅ 3 | `--allowedTools` で最小限のツールのみ許可 | prompt injection時のリスク低減 |
| ✅ 4 | `permissions:` は必要最小限のみ宣言 | 最小権限の原則 |
| ✅ 5 | `show_full_output` はデフォルトOFF維持 | publicリポジトリでのシークレット漏洩防止 |
| ✅ 6 | `GITHUB_TOKEN`（短命）を使いPATは使わない | PATはローテーションされない |
| ✅ 7 | write権限ユーザーのみトリガー可能 | デフォルト動作を維持・変更しない |
| ⚠️ 8 | `github-actions`ユーザーのコメントは後続GHAをトリガーしない | GitHubの無限ループ防止仕様 |

### 既知の制約・落とし穴

- `--max-turns 30` を超えた場合、エージェントは途中で停止してIssueにコメントを残す
- GHA側のタイムアウト（デフォルト360分）も別途存在する
- 1つのIssueに対して複数回ラベルを付与すると複数エージェントが起動する（べき等性の担保が必要）
- `symphony-decompose.yml` はADRのmarkdownフォーマットに強く依存する。フォーマット変更時は要修正

---

## 次フェーズ：dbt/Snowflake 特化版への拡張計画（Phase C）

この汎用設計を、dbt/Snowflake プロジェクトに特化させるために変更が必要な箇所：

1. **CLAUDE.md** に dbt・Snowflake 規約を追記
   - dbtプロジェクト構造（models/staging/marts等）
   - Snowflake RBAC・命名規則
   - `dbt run`, `dbt test`, `dbt compile` の実行方法とCI要件

2. **`--allowedTools`** に dbt 操作用 Bash コマンドを追加
   ```
   Bash(dbt run:*), Bash(dbt test:*), Bash(dbt compile:*)
   ```

3. **Issueテンプレート** を dbt ユースケースに特化
   - dbtモデル追加依頼
   - スキーマ変更依頼（Expand-Contractパターン）
   - テスト追加依頼

4. **Triage判定基準** に dbt 固有のルールを追加
   - スキーマ変更を伴う場合は強制的にRoute B（ADR必須）
   - 既存モデルへの影響範囲がN件以上の場合はRoute C

---

## 参照リソース

| リソース | URL |
|---|---|
| OpenAI Symphony 公式ブログ | https://openai.com/index/open-source-codex-orchestration-symphony/ |
| openai/symphony GitHub | https://github.com/openai/symphony |
| anthropics/claude-code-action | https://github.com/anthropics/claude-code-action |
| Claude Code GitHub Actions 公式ドキュメント | https://docs.anthropic.com/ja/docs/claude-code/github-actions |
| Claude Code Hooks ガイド | https://docs.anthropic.com/ja/docs/claude-code/hooks |
| Claude Code Subagents | https://docs.anthropic.com/ja/docs/claude-code/sub-agents |
