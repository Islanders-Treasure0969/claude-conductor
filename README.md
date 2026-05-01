# symphony-claude-gha

OpenAI Symphony 相当のエージェントオーケストレーションを **Claude Code + GitHub Actions + GitHub Issues** で再現するための雛形リポジトリ。

## コンセプト

- **Issue = 作業単位** — Issue ラベルがステートマシン
- **コントロールプレーン = GitHub** — Linear / Symphony デーモンの代替
- **エージェント = Claude Code (`claude-code-action@v1`)** — Codex の代替
- **ワークスペース = GHA runner** — Per-issue 独立チェックアウト

## ステートマシン

```
[claude-task] ──(GHA labeled イベント)──▶ [claude-in-progress]
                                              │
                                  成功 ──┬───▶ [claude-review]   PR 作成済み
                                          │
                              失敗/停滞 ──┴───▶ [claude-failed]   人間介入
```

## ファイル構成

| パス | 役割 |
|---|---|
| `.github/workflows/symphony-dispatch.yml` | Issue ラベル検知 → エージェント起動 (核心) |
| `.github/workflows/symphony-interactive.yml` | `@claude` メンション対応 |
| `.github/workflows/symphony-cleanup.yml` | 停滞 Issue のタイムアウト処理 (毎時 cron) |
| `.github/ISSUE_TEMPLATE/claude-task.md` | Issue テンプレート (Claude への作業依頼書) |
| `CLAUDE.md` | エージェントが常に参照する共通コンテキスト |

## セットアップ

### 1. リポジトリ secrets を設定
- `ANTHROPIC_API_KEY` を Settings → Secrets and variables → Actions に追加

### 2. ラベルを作成
以下 4 つのラベルをリポジトリに作成しておく:
- `claude-task` (作業キュー)
- `claude-in-progress` (実行中)
- `claude-review` (PR レビュー待ち)
- `claude-failed` (失敗・人間介入)

### 3. CLAUDE.md を埋める
`TODO:` を残してあるプロジェクト概要・ディレクトリ構成・テストコマンド等を、自分のプロジェクトに合わせて記述する。

### 4. 動作確認
1. `Claude Task` テンプレートで Issue を作成
2. `claude-task` ラベルを付与
3. Actions タブで `Symphony Dispatch` が起動することを確認

## セキュリティ

- Issue title / body は `env:` 経由で `prompt` に渡す (コマンドインジェクション対策)
- `--allowedTools` で Claude が利用できるツールを最小限に制限
- `permissions:` は必要最小限のみ宣言
- `GITHUB_TOKEN` (短命) のみ利用、PAT は使わない
- `@claude` メンションは write 権限ユーザーのみトリガー可 (デフォルト動作維持)

## 既知の制約

- `github-actions` ユーザーのコメントは後続 GHA をトリガーしない (無限ループ防止の GitHub 仕様)
- 1 つの Issue に複数回 `claude-task` を付けると複数エージェントが起動する (べき等性は別途対応が必要)
- `--max-turns 30` 超過時はエージェントが途中停止して Issue にコメントを残す

## 元設計資料

`/Users/iwashita/Downloads/symphony-claude-code-gha-design.md` ベース。
