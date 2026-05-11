# claude-conductor

> **Drop-in Symphony for Claude Code.**
> [OpenAI Symphony](https://github.com/openai/symphony) 相当のエージェント
> オーケストレーションを **Claude Code + GitHub Actions + GitHub Issues** で再現する。

[![License: Apache 2.0](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE)

GitHub Issues をコントロールプレーンとして、Issue が opened された瞬間から
**Triage → 実装 / 調査 → ADR → 実装チケット分解** までを自動化します。

---

## 目次

- [何ができるのか](#何ができるのか)
- [アーキテクチャ](#アーキテクチャ)
- [導入方法](#導入方法)
- [ファイル構成](#ファイル構成)
- [セキュリティ](#セキュリティ)
- [既知の制約](#既知の制約)
- [ローカル検証](#ローカル検証)
- [ライセンス](#ライセンス)

---

## 何ができるのか

| あなたがやること | システムが自動でやること |
|---|---|
| Issue を立てる | LLM が内容を分析して 3 ルートに振り分け (Triage) |
| `claude-task` ラベル付与 | エージェントが調査・実装・テスト・PR 作成 |
| `investigation` ラベル付与 | エージェントが調査して ADR draft PR を作成 |
| ADR PR を approve & merge | ADR の「実装チケットへの分解」をパースして子 Issue を自動生成 |
| `@claude` でメンション | 対話的に追加修正・質問対応 |
| (放置) | 2 時間以上停滞した Issue は `claude-failed` に自動遷移 |

## アーキテクチャ

```
Issue opened
   │
   ▼
[symphony-triage.yml]   LLM が 3 ルートに自動振り分け
   │
   ├─ triage-A → 人間が claude-task ラベル付与
   │             [symphony-dispatch.yml] → 実装 PR 作成 → 1 approve → merge
   │
   ├─ triage-B → 人間が investigation ラベル付与
   │             [symphony-investigate.yml] → ADR draft PR 作成
   │             → 人間が ADR を編集・approve・merge
   │             [symphony-decompose.yml]  → 実装チケット自動生成
   │             (Route A → symphony-dispatch.yml を workflow_dispatch で起動)
   │             (Route C → triage-C 付与 → 人間対応キューへ)
   │
   └─ triage-C → 人間がアサイン・対応 (エージェントは関与しない)

[symphony-interactive.yml] @claude メンションで対話モード (任意のタイミング)
[symphony-cleanup.yml]     停滞 Issue を毎時クリーンアップ
```

詳細は以下を参照:
- [DESIGN.md](DESIGN.md) — 設計詳細
- [docs/ARCHITECTURE_REVIEW.md](docs/ARCHITECTURE_REVIEW.md) — 網羅的アーキテクチャ レビュー資料 (v0.2.1 時点の全体像、設計判断、セキュリティ、既知課題、レビューチェックリスト)

---

## 導入方法

導入形態は **2 つ**から選べます。新規リポジトリは A、既存リポジトリは C を推奨。

### A. GitHub Template Repository (新規リポ向け / 推奨)

1. このリポジトリの **「Use this template」** ボタンをクリック
2. 自分の Organization / アカウント配下に新リポジトリを作成
3. [初期セットアップ](#初期セットアップ) に進む

> **Note**: テンプレートとして公開する側で、リポジトリ Settings → General →
> "Template repository" を有効化してください。

### C. インストールスクリプト (既存リポ向け)

既存の git リポジトリのルートで以下を実行:

```bash
curl -fsSL https://raw.githubusercontent.com/Islanders-Treasure0969/claude-conductor/main/install.sh | bash
```

オプション (環境変数で挙動を変更):

| 変数 | デフォルト | 用途 |
|---|---|---|
| `SYMPHONY_REF` | `main` | 取得するブランチ・タグ・commit hash |
| `SYMPHONY_REPO` | `Islanders-Treasure0969/claude-conductor` | フォークから取得する場合 |
| `SYMPHONY_TARGET` | `.` | インストール先ディレクトリ |
| `SYMPHONY_FORCE` | `0` | 既存ファイルを上書き (`1` で有効、自動で `.bak` を作成) |

例: 特定タグから取得・既存ファイルを上書き:

```bash
SYMPHONY_REF=v0.2.1 SYMPHONY_FORCE=1 \
  bash <(curl -fsSL https://raw.githubusercontent.com/Islanders-Treasure0969/claude-conductor/main/install.sh)
```

> **Note**: `v0.1.0` には install.sh のバグがあるため `v0.1.1` 以上を指定してください
> ([CHANGELOG](CHANGELOG.md) の v0.1.1 を参照)。安定版は [Releases](../../releases)
> ページから最新を確認してください。

---

## 初期セットアップ

導入形態 A / C どちらの場合も、以下の **3 ステップ** を行ってください。

### 1. `CLAUDE.md` の `TODO:` を埋める

リポジトリ直下の `CLAUDE.md` に `TODO:` プレースホルダがあります。これがエージェントの
判断軸になるため、必ず埋めてください。

- プロジェクト概要 (技術スタック・主要ドメイン)
- ディレクトリ構成
- テストコマンド (例: `npm test` / `pytest` / `dbt test`)

### 2. GitHub Secret を設定

GitHub リポジトリの Settings → Secrets and variables → Actions で:

- `ANTHROPIC_API_KEY` を追加 ([API Key 取得](https://console.anthropic.com/))

### 3. ラベルを作成

```bash
# 要件: gh CLI (auth 済み) + yq v4+
brew install gh yq
gh auth login

./scripts/setup-labels.sh                    # カレントリポ
./scripts/setup-labels.sh owner/your-repo    # 明示指定
```

10 個のラベルが作成されます (`triage-pending` / `triage-A` / `triage-B` / `triage-C` /
`claude-task` / `claude-in-progress` / `claude-review` / `claude-failed` /
`investigation` / `adr-draft`)。

### 4. (推奨) Branch Protection ルール

`main` ブランチに以下を設定することを強く推奨します:

- Require a pull request before merging
- **Require approvals: 1** (エージェント PR も含めて全 PR に 1 approve 必須)
- Require status checks to pass before merging

> **Note (個人開発の場合)**: 同一アカウントから PR を作る solo dev では GitHub の
> self-approval ブロックで詰むため、`Require approvals: 0` を推奨します
> (Symphony の「人間ゲート」は label 昇格と手動 merge の 2 アクションで実質的に
> 維持されます)。チーム開発では 1 以上を維持してください。

### 動作確認

1. `🔧 実装依頼 (Route A)` テンプレートで Issue を作成
2. Actions タブで `Symphony Triage` が起動することを確認
3. Triage 結果コメントが Issue に投稿される (Route A/B/C のいずれか)
4. Route A なら `claude-task` ラベルを付与 → `Symphony Dispatch` が起動
5. 成功すれば `claude-review` ラベル + PR 作成、失敗すれば `claude-failed`

---

## ファイル構成

| パス | 役割 |
|---|---|
| `.github/workflows/symphony-triage.yml` | ① Issue opened → 3 ルート自動振り分け |
| `.github/workflows/symphony-dispatch.yml` | ② `claude-task` → 実装エージェント |
| `.github/workflows/symphony-investigate.yml` | ③ `investigation` → 調査エージェント (ADR draft) |
| `.github/workflows/symphony-decompose.yml` | ④ ADR merge → 実装チケット自動生成 |
| `.github/workflows/symphony-interactive.yml` | ⑤ `@claude` メンション対応 |
| `.github/workflows/symphony-cleanup.yml` | ⑥ 停滞 Issue のタイムアウト処理 (毎時 cron) |
| `.github/ISSUE_TEMPLATE/claude-task.md` | Route A (実装依頼) 用 Issue テンプレート |
| `.github/ISSUE_TEMPLATE/investigation.md` | Route B (調査・設計依頼) 用 Issue テンプレート |
| `.github/labels.yml` | Symphony ステートマシン用ラベル定義 |
| `docs/adr/ADR-000-template.md` | ADR テンプレート (decompose のパース対象) |
| `scripts/setup-labels.sh` | ラベル一括作成・同期スクリプト |
| `templates/CLAUDE.md` | **導入先リポジトリ**用 CLAUDE.md テンプレート |
| `CLAUDE.md` | **本リポジトリ自身**の開発ルール |
| `DESIGN.md` | アーキテクチャ設計資料 |
| `SECURITY.md` | セキュリティポリシー・脆弱性報告先 |
| `CONTRIBUTING.md` | 貢献ガイド |
| `install.sh` | 既存リポへの後付けインストーラ (C モデル) |

---

## セキュリティ

- Issue title / body は `env:` 経由で `prompt` に渡す (コマンドインジェクション対策)
- `--allowedTools` で Claude が利用できるツールを明示的に最小限に制限
- `permissions:` は各 workflow で必要最小限のみ宣言
- `ANTHROPIC_API_KEY` は GitHub Secrets のみ。コード直書き禁止
- `GITHUB_TOKEN` (短命) のみ利用、PAT は使わない
- `@claude` メンションは write 権限ユーザーのみトリガー可 (claude-code-action のデフォルト動作)

詳細なセキュリティ方針・脆弱性報告先は [SECURITY.md](SECURITY.md) を参照。

---

## 既知の制約

- `github-actions` ユーザーのコメント・コミットは後続 GHA をトリガーしない (無限ループ防止の GitHub 仕様)
- ただし `gh issue create` + ラベル付与は別アクター扱いとなり、`claude-task` 付与で `symphony-dispatch.yml` が正常にトリガーされる
- 1 つの Issue に複数回 `claude-task` を付けると複数エージェントが起動する (べき等性は別途対応が必要)
- `--max-turns 30` 超過時はエージェントが途中停止して Issue にコメントを残す
- GHA タイムアウトは各 workflow で個別設定 (`symphony-dispatch.yml` / `symphony-investigate.yml` は 60 分、`symphony-triage.yml` は 15 分)
- `symphony-decompose.yml` は ADR の markdown フォーマットに強く依存。`docs/adr/ADR-000-template.md` の見出し構造を変更する場合は workflow も合わせて修正

---

## ローカル検証

workflow YAML 構文チェック:

```bash
python3 -c "import yaml,glob; [yaml.safe_load(open(p)) for p in glob.glob('.github/workflows/*.yml')]" \
  && echo OK
```

GHA 固有の検証は `actionlint` を推奨:

```bash
brew install actionlint
actionlint .github/workflows/*.yml
```

---

## ライセンス

Apache License 2.0. 詳細は [LICENSE](LICENSE) を参照。

OpenAI Symphony と同じライセンスを採用しています。

---

## 関連リソース

| リソース | URL |
|---|---|
| OpenAI Symphony | https://github.com/openai/symphony |
| anthropics/claude-code-action | https://github.com/anthropics/claude-code-action |
| Claude Code GitHub Actions ドキュメント | https://docs.anthropic.com/ja/docs/claude-code/github-actions |
