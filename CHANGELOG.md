# Changelog

このリポジトリの変更履歴。フォーマットは [Keep a Changelog](https://keepachangelog.com/ja/1.1.0/) 準拠、
バージョニングは [SemVer](https://semver.org/lang/ja/) に従う。

## [Unreleased]

## [0.2.1] - 2026-05-10

### Added

- **`symphony-dispatch.yml` に `@coderabbitai review` 自動コメント step を追加**
  (ADR-001 / #26 / #24)
  - claude-code-action が作成する PR は author が `app/claude` (bot) で、CodeRabbit が
    default で auto-review しない問題への対処。
  - `Verify Claude produced output` step 直後に新規 step `Trigger CodeRabbit review on PR`
    を追加。`gh pr list --head` で PR を取得して `@coderabbitai review` メンションを
    投稿することで CodeRabbit のレビューを手動トリガー。
  - CodeRabbit を入れていない repo では無視されるため実害なし。
  - ADR-001 の「採用理由」に詳細記載。

### Fixed

- **`symphony-dispatch.yml` の Decompose → Dispatch chain が `claude-code-action` の
  bot ガードで拒否される問題を修正** (#26, ADR-001 派生)
  - `claude-code-action@v1` は `Workflow initiated by non-human actor: github-actions
    (type: Bot). Add bot to allowed_bots list or use '*' to allow all bots.` で workflow
    起動を拒否する built-in safeguard を持つ。
  - Symphony の Decompose は ADR merge 時に **`workflow_dispatch` 経由で Dispatch を
    chain 起動**するため、trigger actor が `github-actions[bot]` になり Dispatch が常に
    失敗していた (self-healing flow が成立しない)。
  - 修正: `symphony-dispatch.yml` の `claude-code-action` 呼び出しに
    `allowed_bots: "github-actions"` を追加。これは Symphony 内部 chain trigger だけを
    許可する最小限の設定で、外部からの bot trigger は依然として拒否される。
  - 検出経路: ADR-001 のチケット自動分解で生成された Issue #26 上で実機 Dispatch を
    走らせた際の failure ログから判明。

- **`actionlint` の SC2016 info 警告 4 件を解消** (#11)
  - `symphony-cleanup.yml` / `symphony-decompose.yml` / `symphony-triage.yml` の
    `printf` / `NEXT='...'` で使われている **markdown inline code 表記の
    バックティック** を、shellcheck が「単一引用符内のシェル展開」と誤認していた
    (false positive)。
  - 対応: 該当箇所に `# shellcheck disable=SC2016` directive と意図説明コメントを
    追加。markdown 表記である旨を後続の編集者にも明示。
  - `actionlint .github/workflows/*.yml` の出力が完全に clean に。

### Added

- **CodeRabbit AI レビュー設定** (`.coderabbit.yaml`)
  - 日本語レビュー (`language: ja-JP`)、profile: chill (穏やか)
  - main 向け PR のみ自動レビュー、draft PR は対象外
  - 除外パス: `CHANGELOG.md` / `LICENSE` / `.gitignore` / `docs/adr/**`
  - GitHub App は別途 https://github.com/apps/coderabbitai から install 必要
  - Symphony Dispatch が PR 作成 → CodeRabbit が自動レビュー → 人間 merge、の
    二段レビュー体制が組める

## [0.2.0] - 2026-05-09

### Added

- **Claude 起動 workflow の execution log を artifact として保存** (#13)
  - 対象: `symphony-triage.yml` / `symphony-dispatch.yml` / `symphony-investigate.yml`
  - 各 workflow 末尾に `actions/upload-artifact@v4` step を追加。Claude が実行中に
    生成した `/home/runner/work/_temp/claude-execution-output.json` を 30 日保存。
  - 名前形式: `claude-execution-log-{triage|dispatch|investigate}-{run_id}`
  - `if: always()` により workflow 失敗時も保存される。`gh run download <run-id>`
    で取得して空振り原因や permission_denials の詳細を後追い可能。
  - `if-no-files-found: ignore` 指定で、claude-code-action 起動前の失敗時
    (e.g. checkout 失敗) は upload エラーにせず無視する。

### Fixed

- **`symphony-dispatch.yml` が Claude の空振りを検出せず `claude-review` に遷移する
  状態機械バグを修正** (#12)
  - claude-code-action は内部エラー無しに 1 件もコミットせず終了することがある。
    そのまま success 扱いで `Mark as review` step が走り、PR 不在で review 待ち
    状態になっていた。
  - 修正: `Run Claude Code Agent` の直後に `Verify Claude produced output` step を
    追加し、`claude/issue-N` ブランチの commit 数と関連 PR の存在を確認。
    どちらも無い場合は exit 1 して `Mark as failed (on failure)` パスへ流す。

## [0.1.3] - 2026-05-09

### Security

- **`symphony-triage.yml` / `symphony-interactive.yml` に `author_association` ガードを
  追加** (#14)
  - public repo + GitHub Template + Anthropic API key 利用 という構成における外部
    ユーザーからの **cost griefing** 対策。
  - 対象: `triage` job と `claude-respond` job。`OWNER` / `MEMBER` / `COLLABORATOR` の
    author のみ workflow 起動を許可。それ以外のユーザーが立てた issue や書いた
    `@claude` メンションコメントは無視される。
  - 副作用: 外部ユーザーからの issue は自動 triage されず、ラベル付与は repo
    オーナー側で手動運用となる。導入先がチーム開発で外部 contributor を
    許容したい場合は `if:` 条件を緩めて再 install すること。

### Notes

- 個人 dev (solo) で導入する場合、Branch protection の
  `required_approving_review_count` は **0** が現実的（同一アカウントから PR 作成
  すると GitHub の self-approval ブロックで詰むため）。チーム開発では 1 以上を
  推奨。Symphony の "1 approve" は本来「人間ゲート」の意味であり、solo の場合は
  「label promote」と「manual merge」の 2 アクションでその役割を代替できる。

## [0.1.2] - 2026-05-08

### Fixed

- **`symphony-triage.yml` の `permissions` に `id-token: write` を追加** (v0.1.0 から
  続く Triage 起動失敗バグを修正)
  - `claude-code-action` は OIDC トークン取得を要求するため `id-token: write` 権限
    が必須。他の Claude 起動 workflow (dispatch / investigate / interactive) には
    付与されていたが、triage だけ漏れていた。
  - 影響: secret 設定済みでも Triage が `Could not fetch an OIDC token` で 3 回
    リトライ後失敗し、`Handle triage failure` step の fallback により全 issue が
    強制的に `triage-C` ラベル付与されていた。
  - 検出経路: 実 issue による E2E テスト。

### Notes

- v0.1.0 / v0.1.1 を install 済みの場合、`.github/workflows/symphony-triage.yml`
  の `permissions:` ブロックに `id-token: write` を 1 行追加するか、v0.1.2 を
  改めて install することで解消する。

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

[Unreleased]: https://github.com/Islanders-Treasure0969/claude-conductor/compare/v0.2.1...HEAD
[0.2.1]: https://github.com/Islanders-Treasure0969/claude-conductor/releases/tag/v0.2.1
[0.2.0]: https://github.com/Islanders-Treasure0969/claude-conductor/releases/tag/v0.2.0
[0.1.3]: https://github.com/Islanders-Treasure0969/claude-conductor/releases/tag/v0.1.3
[0.1.2]: https://github.com/Islanders-Treasure0969/claude-conductor/releases/tag/v0.1.2
[0.1.1]: https://github.com/Islanders-Treasure0969/claude-conductor/releases/tag/v0.1.1
[0.1.0]: https://github.com/Islanders-Treasure0969/claude-conductor/releases/tag/v0.1.0
