# Changelog

このリポジトリの変更履歴。フォーマットは [Keep a Changelog](https://keepachangelog.com/ja/1.1.0/) 準拠、
バージョニングは [SemVer](https://semver.org/lang/ja/) に従う。

## [Unreleased]

## [0.1.1] - 2026-05-08

### Fixed

- **`install.sh` が 1 ファイルもインストールしないバグを修正** (v0.1.0 リグレッション)
  - `log()` / `ok()` が stdout に出力していたため、`extracted=$(download_archive)`
    がログメッセージごとパスとして捕捉してしまい、全ファイルが
    「ソースが見つかりません」で skip されていた。全ロガーを stderr に統一。
  - `download_archive()` 内で `local tmpdir` を参照する EXIT trap が、関数 return
    後に発火した際 `set -u` で「未割り当ての変数です」を出していた。
    `INSTALL_TMPDIR` を script-level に移し、`cleanup_tmpdir` 関数経由で安全に削除。

### Notes

- v0.1.0 の `install.sh` は壊れているため `SYMPHONY_REF=v0.1.0` での
  curl-bash 利用は不可。v0.1.1 以降を利用すること。

## [0.1.0] - 2026-05-08

初版リリース。OpenAI Symphony 同等のエージェントオーケストレーションを
Claude Code + GitHub Actions + GitHub Issues で再現する scaffolding を提供する。

### Added

- **3 ルート方式の Issue オーケストレーション**
  - `symphony-triage.yml`: Issue opened を契機に LLM 分類で 3 ルートに自動振り分け
  - `symphony-dispatch.yml`: `claude-task` ラベル / workflow_dispatch で実装エージェント起動
  - `symphony-investigate.yml`: `investigation` ラベルで調査エージェント起動 → ADR draft PR
  - `symphony-decompose.yml`: ADR merge を契機に実装チケットを自動生成
  - `symphony-interactive.yml`: `@claude` メンションで対話的応答
  - `symphony-cleanup.yml`: 停滞 Issue (`claude-in-progress` 2h+) を自動 failed 遷移
- **ステートマシン用ラベル一式** (10 種):
  triage-pending / triage-A / triage-B / triage-C /
  claude-task / claude-in-progress / claude-review / claude-failed /
  investigation / adr-draft
- **Issue テンプレート** (Route A `claude-task.md` / Route B `investigation.md`)
- **ADR テンプレート** (`docs/adr/ADR-000-template.md`、`symphony-decompose.yml` のパース対象)
- **`templates/CLAUDE.md`**: 導入先リポジトリ用エージェントコンテキスト雛形
- **`scripts/setup-labels.sh`**: `gh` + `yq` でラベル一括作成・同期
- **`install.sh`**: 既存 git リポジトリへの後付けインストーラ (C モデル)
  環境変数 `SYMPHONY_REF` / `SYMPHONY_REPO` / `SYMPHONY_TARGET` / `SYMPHONY_FORCE`
- **GitHub Template Repository 対応**: 「Use this template」ボタンで新規リポを作成可能
- **CI パイプライン** (`.github/workflows/ci.yml`):
  yaml-syntax / actionlint / shellcheck / labels-schema の 4 ジョブ
- **Dependabot**: github-actions エコシステムを毎週月曜にチェック
- **OSS メタデータ**: LICENSE (Apache-2.0) / SECURITY.md / CONTRIBUTING.md
- **DESIGN.md**: アーキテクチャ判断・セキュリティチェックリスト・既知の落とし穴

### Security

- すべての Issue title / body は `env:` 経由で `prompt` に渡す (コマンドインジェクション対策)
- 各 workflow で `permissions:` を最小権限に絞る
- `--allowedTools` でエージェントが触れるツールを明示的に制限
- `ANTHROPIC_API_KEY` は GitHub Secrets のみ
- `GITHUB_TOKEN` (短命) のみ利用、PAT は使わない
- `@claude` メンションは write 権限ユーザーのみトリガー可

### Notes

- `symphony-decompose.yml` から `symphony-dispatch.yml` を起動する経路は
  GITHUB_TOKEN events の制約 ([GitHub Docs](https://docs.github.com/en/actions/using-workflows/triggering-a-workflow#triggering-a-workflow-from-a-workflow))
  を回避するため `workflow_dispatch` 経由で実装している。
- `symphony-decompose.yml` は ADR の markdown フォーマットに強く依存する。
  `docs/adr/ADR-000-template.md` の見出し構造を変更する場合は workflow も
  合わせて修正が必要。

[Unreleased]: https://github.com/Islanders-Treasure0969/claude-conductor/compare/v0.1.1...HEAD
[0.1.1]: https://github.com/Islanders-Treasure0969/claude-conductor/releases/tag/v0.1.1
[0.1.0]: https://github.com/Islanders-Treasure0969/claude-conductor/releases/tag/v0.1.0
