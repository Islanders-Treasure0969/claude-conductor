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
| `.github/labels.yml` | Symphony ステートマシン用ラベル定義 |
| `scripts/setup-labels.sh` | ラベル一括作成・同期スクリプト |
| `templates/CLAUDE.md` | **導入先リポジトリ**用 CLAUDE.md テンプレート |
| `CLAUDE.md` | **本リポジトリ自身**の開発ルール |

## 導入手順 (社内プロジェクトへの適用)

### 1. ファイルを導入先リポジトリへコピー

```bash
cp -r .github/ /path/to/your-repo/
cp templates/CLAUDE.md /path/to/your-repo/CLAUDE.md
```

### 2. 導入先の `CLAUDE.md` を埋める

`TODO:` プレースホルダ(プロジェクト概要・ディレクトリ構成・テストコマンド)を、自分のプロジェクトに合わせて記述する。これが空だとエージェントの判断軸が無い。

### 3. リポジトリ secrets を設定

- `ANTHROPIC_API_KEY` を Settings → Secrets and variables → Actions に追加

### 4. ラベルを作成

`scripts/setup-labels.sh` を実行 (要 `gh` + `yq`):

```bash
./scripts/setup-labels.sh owner/your-repo
```

または手動で 4 つのラベルを作成:
- `claude-task` (作業キュー)
- `claude-in-progress` (実行中)
- `claude-review` (PR レビュー待ち)
- `claude-failed` (失敗・人間介入)

### 5. 動作確認

1. `Claude Task` テンプレートで Issue を作成
2. `claude-task` ラベルを付与
3. Actions タブで `Symphony Dispatch` が起動することを確認
4. 成功すれば `claude-review` ラベルに遷移 + PR 作成
5. 失敗すれば `claude-failed` ラベルに遷移 + Issue に GHA ログリンク

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
- GHA `timeout-minutes` は `symphony-dispatch.yml` で 60 分に設定済 (調整可)

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

## 元設計資料

OpenAI Symphony の公式仕様および `anthropics/claude-code-action` 公式ドキュメントを基に、社内向けに設計を起こしたもの。設計ドキュメント本体はリポジトリ外で管理。
