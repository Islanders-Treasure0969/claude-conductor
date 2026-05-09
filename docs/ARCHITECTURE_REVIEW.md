# claude-conductor アーキテクチャ レビュー

> このドキュメントは scaffold 全体を網羅的かつ構造的に把握し、設計レビューに耐えられるよう整理した一次資料。
> 作成日: 2026-05-10 / 対象バージョン: **v0.2.1**

---

## 目次

- [0. このドキュメントについて](#0-このドキュメントについて)
- [1. プロジェクト概要](#1-プロジェクト概要)
- [2. 高レベル アーキテクチャ](#2-高レベル-アーキテクチャ)
- [3. コンポーネント](#3-コンポーネント)
- [4. 設計判断と根拠](#4-設計判断と根拠)
- [5. セキュリティモデル](#5-セキュリティモデル)
- [6. 信頼性・観察可能性](#6-信頼性観察可能性)
- [7. 配布モデル](#7-配布モデル)
- [8. テスト・CI](#8-テストci)
- [9. 既知の課題と将来計画](#9-既知の課題と将来計画)
- [10. レビュー観点 チェックリスト](#10-レビュー観点-チェックリスト)
- [付録 A: 用語](#付録-a-用語)
- [付録 B: 参照リンク](#付録-b-参照リンク)

---

## 0. このドキュメントについて

### 目的

- scaffold 全体のアーキテクチャをレビュー観点で **網羅的** に整理する
- 各設計判断の **根拠とトレードオフ** を明示する
- 実機検証済み事項と未検証事項を **区別** して提示する
- 既知の課題を **正直に** 記録する

### 想定読者

- OSS author 自身（リリース判断、改善計画）
- これから採用を検討する利用者
- (将来) 第三者レビュア / contributor

### スコープ外

- 個別実装の行単位レビュー（PR レビューや CodeRabbit に委譲）
- claude-code-action 自体の仕様（[公式 docs](https://github.com/anthropics/claude-code-action) 参照）
- Anthropic API の挙動

---

## 1. プロジェクト概要

### 1.1 何を提供するか

**OpenAI Symphony 相当のエージェント オーケストレーションを Claude Code + GitHub Actions + GitHub Issues で再現する scaffolding (雛形)**。

導入したリポジトリは以下を即座に得る：

- Issue を立てる → LLM が Triage → 3 ルートに自動振り分け
- Route A: 即実装 → Claude が PR 作成 → 1 approve で merge
- Route B: 調査・設計先行 → Claude が ADR draft → 人間がレビュー → 実装チケット自動生成
- Route C: 人間主体（エージェント関与しない）

### 1.2 スコープ外（このリポジトリは提供しない）

- 業務ロジック（このリポは scaffold で、実プロジェクトの中身は持たない）
- 自前 MCP サーバ実装（claude-code-action 既製品を利用）
- 多言語対応（日本語前提、英語は二級扱い）

### 1.3 想定ユーザー

| 想定 | 説明 |
|---|---|
| **個人 dev (solo)** | private repo で活用、ruleset で 0 approve 設定可能 |
| **小規模チーム (2-10名)** | 1 approve + CodeRabbit のレビュー二段ゲート |
| 大規模チーム | non-goal。CODEOWNERS 等を別途構成すれば一応動く |
| 完全 public OSS | non-goal。author_association ガードで限定的にカバー |

### 1.4 配布形態

- **A モデル (一次)**: GitHub Template Repository (「Use this template」ボタン)
- **C モデル (補助)**: `install.sh` を curl bash で既存リポに後付け

詳細: [§ 7. 配布モデル](#7-配布モデル)

---

## 2. 高レベル アーキテクチャ

### 2.1 全体俯瞰図

```text
┌──────────────────────────────────────────────────────────────────────┐
│                          GitHub Issue (opened)                        │
└────────────────────────────────┬─────────────────────────────────────┘
                                 │
                                 ▼
                  ┌──────────────────────────────┐
                  │  symphony-triage.yml         │
                  │  (LLM が 3 ルート分類)         │
                  └──────────────┬───────────────┘
                                 │
        ┌────────────────────────┼────────────────────────┐
        ▼                        ▼                        ▼
  triage-A                 triage-B                  triage-C
  (即実装)                 (調査・設計)               (人間主体)
        │                        │                        │
        ▼                        ▼                        ▼
  人間 promote:           人間 promote:             人間が対応
  claude-task             investigation             (自動化なし)
        │                        │
        ▼                        ▼
  symphony-               symphony-
  dispatch.yml            investigate.yml
        │                        │
        ▼                        ▼
  実装 PR 作成             ADR draft PR 作成
        │                        │
        ▼                        ▼
  CodeRabbit              人間レビュー
  自動レビュー            「決定」記入
        │                        │
        ▼                        ▼
  人間 approve            ADR merge
  + merge                       │
                                ▼
                         symphony-
                         decompose.yml
                                │
                                ▼
                  実装チケット自動生成
                  (workflow_dispatch で
                   dispatch を chain)
                                │
                          ┌─────┴─────┐
                          ▼           ▼
                   Route A 子issue  Route C 子issue
                   (claude-task)    (triage-C)
                          │
                          ▼
                   dispatch.yml
                   (再帰: 通常 Route A flow へ)
```

### 2.2 ラベル状態機械

```text
[Triage]
  (Issue opened) → triage-pending → {triage-A, triage-B, triage-C}

[Route A: 実装]
  triage-A
    ↓ (人間が claude-task 付与)
  claude-task
    ↓ (dispatch.yml が剥がす)
  claude-in-progress
    ↓ (Verify Claude produced output passed)
  claude-review            (PR 作成済 + CodeRabbit レビュー済)
    ↓ (人間 approve & merge)
  closed

  ※ verify failure / 2h timeout
  → claude-failed

[Route B: 調査]
  triage-B
    ↓ (人間が investigation 付与)
  investigation
    ↓ (investigate.yml が剥がす)
  claude-in-progress
    ↓ (ADR draft PR 作成済)
  adr-draft
    ↓ (人間が決定記入 → ADR merge)
  closed
    ↓ (decompose.yml が走る)
  子 Issue 自動生成 → Route A or C へ

[Route C: 人間主体]
  triage-C
    ↓ (人間が対応)
  closed
```

### 2.3 トリガーグラフ

| trigger | 起動する workflow | 起動条件 |
|---|---|---|
| `issues.opened` | symphony-triage.yml | 必ず（OWNER/MEMBER/COLLABORATOR の場合のみ：author_association ガード） |
| `issues.labeled` (claude-task) | symphony-dispatch.yml | label 付与で発火 |
| `issues.labeled` (investigation) | symphony-investigate.yml | label 付与で発火 |
| `issue_comment.created` | symphony-interactive.yml | `@claude` メンション、author_association ガード付き |
| `pull_request.closed` (merged) | symphony-decompose.yml | ADR draft PR が merge された時 |
| `workflow_dispatch` (chain) | symphony-dispatch.yml | decompose から子 issue 用に chain 起動 |
| `schedule` (2h) | symphony-cleanup.yml | claude-in-progress の停滞検出 |

### 2.4 データフロー（実装ルート例: Issue → PR → merge）

```text
1. ユーザが Issue 作成
   ↓ payload: title / body / number
2. Triage (Claude API call): title/body を env: 経由で受け取り
   - CLAUDE.md / repo を Read で参照
   - /tmp/triage-result.json を Write
   ↓ output: { route, reason, confidence, note }
3. Apply triage label step が JSON を読み issue にラベル + コメント
   ↓
4. 人間が claude-task ラベル付与
   ↓
5. Dispatch (Claude API call): title/body/number を env: 経由
   - 実装、ブランチ作成、コミット、PR 作成
   ↓
6. Verify Claude produced output: git rev-list, gh pr list で検証
   ↓ HAS_COMMITS=1 OR HAS_PR=1 でなければ exit 1
7. Trigger CodeRabbit review on PR: gh pr comment "@coderabbitai review"
   ↓
8. Mark as review (label transition)
   ↓
9. CodeRabbit がレビュー (CodeRabbit App が PR に review コメント投稿)
   ↓
10. 人間 approve & merge → issue auto-close (PR 本文の "Closes #N")
```

---

## 3. コンポーネント

### 3.1 Workflow 6 本

| ファイル | trigger | 用途 | timeout | 備考 |
|---|---|---|---|---|
| `symphony-triage.yml` | issues.opened | LLM 3 ルート分類 | 15 min | author_association ガード |
| `symphony-dispatch.yml` | issues.labeled / workflow_dispatch | Claude が実装 PR 作成 | 60 min | Verify guard, allowed_bots, CodeRabbit trigger |
| `symphony-investigate.yml` | issues.labeled | Claude が ADR draft PR 作成 | 60 min | |
| `symphony-decompose.yml` | pull_request.closed | ADR merge → 子 issue 生成 | 15 min | awk で ADR をパース、chain で dispatch 起動 |
| `symphony-interactive.yml` | issue_comment / pr_review_comment | `@claude` 応答 | 30 min | author_association ガード |
| `symphony-cleanup.yml` | schedule (2h) / workflow_dispatch | 停滞 issue を claude-failed に遷移 | 10 min | gh CLI ベース、Claude 不使用 |
| **CI** (`ci.yml`) | push / pull_request | yaml-syntax / actionlint / shellcheck / labels-schema | 5 min | scaffold 自身のリンター |

### 3.2 ラベル定義 (10 種)

[`/.github/labels.yml`](../.github/labels.yml) で管理、[`scripts/setup-labels.sh`](../scripts/setup-labels.sh) で同期。

| ラベル名 | 役割 | 色 |
|---|---|---|
| triage-pending | Triage 中 | グレー |
| triage-A | Route A 判定（即実装） | 青 |
| triage-B | Route B 判定（調査） | 黄 |
| triage-C | Route C 判定（人間主体） | 赤 |
| claude-task | Dispatch キュー | 青 |
| claude-in-progress | エージェント作業中 | 黄 (cleanup 対象) |
| claude-review | PR 作成済・人間レビュー待ち | 緑 |
| claude-failed | 失敗・タイムアウト | 赤 |
| investigation | Investigate キュー | 黄 |
| adr-draft | ADR PR 作成済・レビュー待ち | 桃 |

### 3.3 設定ファイル

| パス | 用途 |
|---|---|
| `.github/labels.yml` | ラベル定義（state machine の真実） |
| `.github/dependabot.yml` | github-actions 依存の週次 update |
| `.github/ISSUE_TEMPLATE/claude-task.md` | Route A 用テンプレート |
| `.github/ISSUE_TEMPLATE/investigation.md` | Route B 用テンプレート |
| `.coderabbit.yaml` | CodeRabbit AI レビュー設定 (ja-JP, profile: chill) |
| `templates/CLAUDE.md` | 導入先で利用する CLAUDE.md 雛形 |
| `docs/adr/ADR-000-template.md` | ADR テンプレート (decompose のパース対象) |

### 3.4 配布物 (install.sh が配置するファイル)

```text
.github/workflows/symphony-*.yml          (6 ファイル)
.github/ISSUE_TEMPLATE/*.md               (2 ファイル)
.github/labels.yml                        (1 ファイル)
docs/adr/ADR-000-template.md              (1 ファイル)
scripts/setup-labels.sh                   (1 ファイル)
templates/CLAUDE.md → CLAUDE.md (rename)  (1 ファイル)
                                           ─────────
                                           計 12 ファイル
```

> 注: CI workflow (`ci.yml`)、`.coderabbit.yaml`、`.github/dependabot.yml` は scaffold 自身用で、配布対象外。導入先は必要に応じて自前で追加。

---

## 4. 設計判断と根拠

### 4.1 GitHub Issues を中心に据える

**判断**: Symphony オーケストレーションのキューを **GitHub Issues** で表現。

**根拠**:
- 既存の Issue UI でユーザーは慣れている
- ラベル変更で state machine を素朴に表現できる
- 履歴が可視化される（コメント・ラベル変更ログ）
- 外部 DB / Redis / queue サービス不要（運用コスト極小）
- Cleanup workflow も `gh issue list` で停滞検出が容易

**トレードオフ**:
- ラベル付与レースコンディション（複数 workflow が同時にラベル変更すると競合）→ 現状は dispatch / investigate が独占的に label 操作するので問題化していないが、将来 contention が出る可能性は残る

### 4.2 Human-in-the-Loop の配置

**判断**: 以下 4 点で人間が介入する：
1. Triage 判定後 → ラベル昇格 (`claude-task` / `investigation`)
2. ADR draft の「決定」記入
3. PR の approve & merge
4. claude-failed の振り返り

**根拠**: コスト griefing 防止、設計判断の責任所在明確化、エージェント暴走の最終ガード。

**トレードオフ**:
- solo dev は手動操作が増える（ただし 0 approve 設定で軽減可能）
- 完全自律にしたい用途には合わない（が、本 scaffold の設計目的が「人間と協調するエージェント」なので想定通り）

### 4.3 ラベル駆動 state machine

**判断**: 状態遷移を GitHub label の付け替えで表現。

**根拠**:
- GitHub Actions の `issues.labeled` トリガーが直感的に対応する
- ラベル一覧で「今キューに何件あるか」が即可視化
- プロジェクト DB を持たない設計と整合

**トレードオフ**:
- ラベルが多い (10 種) → setup-labels.sh で一括同期する仕組みが必須
- 人間がうっかりラベルを誤付与するとフロー崩れる → 命名で誤操作を抑止する程度

### 4.4 Branch protection: Repository Ruleset (modern)

**判断**: classic branch protection ではなく [Repository Ruleset](https://docs.github.com/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets) を採用。

**現在の rule 構成** (このリポでの値):

| rule | 値 |
|---|---|
| target | main |
| deletion | 禁止 |
| non_fast_forward | 禁止 (force push 不可) |
| required_linear_history | true |
| pull_request.required_approving_review_count | **0** (solo dev 前提、self-approval ブロック回避) |
| pull_request.required_review_thread_resolution | **true** (CodeRabbit 指摘の resolve 必須) |
| pull_request.allowed_merge_methods | squash / rebase (merge commit 禁止) |
| required_status_checks | 4 CI + CodeRabbit |
| strict_required_status_checks_policy | true (branch up-to-date 強制) |
| bypass_actors | [] (誰も bypass 不可、admin 含む) |

**根拠**:
- ruleset は modern API、bypass の細かい設定が可能
- `required_review_thread_resolution: true` で CodeRabbit の actionable 指摘を自動的に gate にできる
- 0 approve は **solo dev で同一アカウントから PR を作る GitHub の self-approval ブロック**を回避（重要）

**注意**: チーム開発で導入する場合は `required_approving_review_count` を 1 以上に上げること。CHANGELOG v0.1.3 にも明記。

### 4.5 CodeRabbit との二段レビュー

**判断**: AI レビューを CodeRabbit に委譲、人間は merge 判断とコメント解決に集中。

**根拠**:
- Symphony Dispatch が量産する PR の品質ゲートを自動化したい
- CodeRabbit は CLAUDE.md ルール（例: gh comment は printf 経由）まで読んで指摘してくる（実証済）
- `.coderabbit.yaml` で path_filter / language / profile を統一管理できる
- (検出された問題) bot author の自動 review skip → ADR-001 で解決済 (`@coderabbitai review` 手動トリガー)

**コスト**: free tier で十分（Personal / Open Source plan）。Pro Plus が無料で適用されているケースもある。

### 4.6 ADR 駆動型 decompose

**判断**: 調査 (Route B) は ADR draft → 人間が「決定」記入 → ADR merge → decompose で実装チケット生成、というルート。

**根拠**:
- 設計判断のトレーサビリティ（後から「なぜそうしたか」を追える）
- 人間が ADR を編集する余地を残し、AI の判定を盲信しない
- decompose の自動生成は ADR の特定セクション (`実装チケットへの分解`) を awk でパースするだけのシンプル実装

**トレードオフ**:
- ADR テンプレートのフォーマット変更時、decompose の awk スクリプトも追従修正が必要（CLAUDE.md に明記）

### 4.7 セッション内で蓄積された設計修正履歴

| 修正 | リリース | 経緯 |
|---|---|---|
| install.sh stdout 汚染修正 | v0.1.1 | local dry-run で発覚 |
| Triage に `id-token: write` 追加 | v0.1.2 | 実 issue で初の Triage 実行時 fail で発覚 |
| author_association ガード追加 | v0.1.3 | public repo の cost griefing 対策 |
| Verify Claude produced output guard | v0.2.0 | live E2E で 0 commit 完走を観測 (#12) |
| execution log artifact upload | v0.2.0 | 空振り原因解析の observability 不足 (#13) |
| `allowed_bots` + CodeRabbit auto trigger | v0.2.1 | self-healing chain が claude-code-action の bot ガードに弾かれる発見 (#26, ADR-001) |
| SC2016 false-positive disable | v0.2.1 | actionlint info noise の整理 (#11) |

これらは全て **dogfood (実機運用)** で発見され、Symphony 自身を使って fix するメタループで対処された。

---

## 5. セキュリティモデル

### 5.1 脅威モデル

| # | 脅威 | 主体 | 緩和策 |
|---|---|---|---|
| T1 | secret 漏洩（API key / GITHUB_TOKEN） | 外部 contributor / 内部攻撃者 | secret は GitHub Secrets のみ、log マスク、fork PR には渡らない |
| T2 | コスト griefing（API 課金消費） | 外部公開 issue 投下者 | author_association ガード、Anthropic spend limit、fork PR approval |
| T3 | prompt injection（issue body で claude を操る） | issue 投下者 | env: 経由の値受け渡し、`--allowedTools` の最小化、Claude の内蔵 prompt safety |
| T4 | 任意コード実行（workflow を編集する PR） | 外部 contributor | branch protection (PR 必須・1 approve・status check)、pull_request_target 不使用 |
| T5 | 自己破壊的 push（main を force push） | admin / 内部誤操作 | ruleset の `non_fast_forward`、bypass_actors=[] |
| T6 | secret を log/artifact に出力 | 偶発（claude-code-action のバグ等） | artifact audit (実施済、漏洩 0 確認) |

### 5.2 緩和策の実装位置

| 緩和 | 実装 | 検証 |
|---|---|---|
| `permissions:` 最小宣言 | 各 workflow top-level | 静的レビュー |
| `--allowedTools` 制限 | claude-code-action 呼び出し時 | 各 workflow |
| `env:` 経由の user input | triage / dispatch / investigate / interactive | grep audit |
| author_association ガード | triage / interactive | v0.1.3 で追加 |
| Anthropic spend limit | Anthropic Console (UI) | 利用者運用 |
| fork PR approval | repo settings (`approval_policy: all_external_contributors`) | API 確認済 |
| GitHub Secrets のみ | ANTHROPIC_API_KEY | API 経由設定確認済 |
| OIDC token | id-token: write per workflow | v0.1.2 で全 claude 起動 workflow に揃えた |
| artifact 内 secret 漏洩なし | secret-leak audit | live 検証で `sk-ant-` 0 件確認済 |

### 5.3 セキュリティ チェックリスト（CLAUDE.md より）

- [x] Issue title/body 等のユーザー制御値は **必ず `env:` 経由**で `prompt` に渡す
- [x] `permissions:` は最小権限のみ宣言
- [x] `--allowedTools` でエージェントが触れるツールを明示的に制限
- [x] `ANTHROPIC_API_KEY` は GitHub Secrets のみ
- [x] `GITHUB_TOKEN` を使用（PAT は使わない）
- [x] gh CLI 経由のコメント本文は `printf` で実改行を生成
- [x] `pull_request_target` 不使用（fork PR からの secret 露出防止）

---

## 6. 信頼性・観察可能性

### 6.1 状態機械の整合性

dispatch / investigate / cleanup の各 workflow は **必ず最終的に label を遷移させる**。

- 成功時: `Mark as review (on success)` step
- 失敗時: `Mark as failed (on failure)` step（`if: failure()`）
- 停滞時: cleanup workflow が定期検出 → `claude-failed` 強制遷移

### 6.2 Verify Claude produced output (#12 → v0.2.0)

claude-code-action は内部エラーなしで 0 commit 終了することがある (live で再現)。dispatch にこの verify step を入れて：

- branch に commits があるか (`git rev-list --count main..claude/issue-N`)
- ブランチ head の PR 数 (`gh pr list --head`)

両方ゼロなら `exit 1` → `Mark as failed` パスへ流す。

### 6.3 Cleanup workflow

- schedule trigger (2h cron)
- `claude-in-progress` ラベル付き issue を全件走査
- 最終更新から 2h 以上経過していれば `claude-failed` に強制遷移
- 人間に「失敗しました」コメント投稿

### 6.4 Artifact 上の execution log (#13 → v0.2.0)

triage / dispatch / investigate が claude-code-action を呼ぶ際に、`/home/runner/work/_temp/claude-execution-output.json` を 30 日 retention で artifact 化。

- 名前形式: `claude-execution-log-{triage|dispatch|investigate}-{run_id}`
- `if: always()` なので失敗時も保管
- `if-no-files-found: ignore` で claude 起動前の失敗時は無害
- `gh run download <run-id>` で取得可能

### 6.5 監査結果（live verification）

- 全 6 workflow のうち **5 本** が live 動作確認済（cleanup / triage / dispatch / investigate / decompose）
- Symphony Interactive のみ静的検証のみ（`@claude` メンションを実装中で誰も投げてないため）

---

## 7. 配布モデル

### 7.1 A モデル: GitHub Template Repository

- 設定: repo の `isTemplate: true` フラグ（このリポは設定済）
- 利用方法: GitHub UI の「Use this template」ボタン
- 結果: 新規 repo に 23 ファイルが転送される（main HEAD のスナップショット）
- 検証済: live E2E で実機テンプレートから生成 → ファイル全件確認 → CodeRabbit / Triage / Dispatch すべて含むことを確認

### 7.2 C モデル: install.sh

- 配信: `curl -fsSL https://raw.githubusercontent.com/{REPO}/main/install.sh | bash`
- 環境変数: `SYMPHONY_REF` / `SYMPHONY_REPO` / `SYMPHONY_TARGET` / `SYMPHONY_FORCE`
- 動作: `codeload.github.com/{REPO}/tar.gz/{REF}` から archive 取得 → 展開 → 12 ファイルを配置
- 安全装置:
  - 既存ファイルはデフォルト skip（`SYMPHONY_FORCE=1` で `.bak` 作成して上書き）
  - git リポジトリ外では実行しない
- 検証済: ローカル temp dir で全 12 ファイル install 成功（v0.1.1）

### 7.3 versioning

- SemVer 準拠 (`v{MAJOR}.{MINOR}.{PATCH}`)
- CHANGELOG.md (Keep a Changelog 準拠)
- リリース履歴 (本セッションで生成):
  - v0.1.0 (初版)
  - v0.1.1 (install.sh 修正)
  - v0.1.2 (Triage `id-token: write`)
  - v0.1.3 (author_association ガード)
  - v0.2.0 (Verify guard + observability)
  - v0.2.1 (self-healing + CodeRabbit auto-trigger)

---

## 8. テスト・CI

### 8.1 CI suite (`.github/workflows/ci.yml`)

| ジョブ | 内容 | コスト |
|---|---|---|
| `YAML syntax check` | `yaml.safe_load` で全 workflow / labels.yml 検証 | <10s |
| `actionlint (GitHub Actions linter)` | actionlint で workflow lint | <10s |
| `shellcheck` | install.sh + setup-labels.sh の shellcheck | <10s |
| `labels.yml schema check` | labels.yml が必要 fields を持つか | <10s |

### 8.2 CodeRabbit AI レビュー

- `.coderabbit.yaml` 設定（profile: chill, ja-JP, path_filters, auto_review only on main）
- main 向け PR で自動レビュー (drafts はスキップ)
- bot author PR は手動トリガー（`@coderabbitai review` を Symphony Dispatch が自動投稿）
- pre-merge checks: Title / Linked Issues / Out of Scope / Description / Docstring を 5 件パス必須

### 8.3 実機 E2E 検証履歴

| Phase | Issue / PR | 結果 |
|---|---|---|
| Triage 初動 | #11 | secret 未設定で fallback、secret 設定後 success |
| Triage 高負荷 | #20 / #24 | 確信度 high / Route 正しく分類 |
| Dispatch 完走 | #20 → PR #23 | 90 秒、Verify guard pass、artifact upload OK |
| Dispatch 空振り検出 | #11 (旧) | Verify guard が catch して claude-failed 遷移 |
| Investigate 完走 | #24 → PR #25 (ADR-001) | 3.5 分、ADR 構造遵守 |
| Decompose 完走 | PR #25 merge → #26 | 子 issue 生成 + Dispatch chain 起動 |
| Self-heal | #26 → 失敗 (allowed_bots) → PR #27 で根本修正 → v0.2.1 | meta 修正完遂 |
| install.sh 配布 | local dry-run | 12 ファイル配置 |
| A-model 配布 | template instantiate | 23 ファイル配置 |

---

## 9. 既知の課題と将来計画

### 9.1 機能・品質の Open ギャップ

| ID | 内容 | 影響度 | 対応案 |
|---|---|---|---|
| G1 | Symphony Interactive が live 未検証 | 中 | `@claude` メンションを 1 回投げるだけで verify 可。次回セッション |
| G2 | SC2153 info warning が decompose に残存 | 低 | $PR_NUMBER 変数命名（actionlint の指摘）。実害なし |
| G3 | ADR が ADR-000-template と ADR-001 の 2 件のみ | 低 | 利用者向け ADR cookbook を docs に追加検討 |
| G4 | テスト repo (`symphony-template-e2e-test-1778337138`) 削除未実施 | 低 | gh CLI に `delete_repo` scope 不足。UI 削除 or scope 追加 |
| G5 | first-time user チュートリアル不在 | 中 | README 拡充、screencast 検討 |
| G6 | エッジケース (大型 issue body, 非英日言語) 未テスト | 低 | 必要に応じてストレステスト |
| G7 | Anthropic API コストの自動 budget alert なし | 中 | Anthropic Console で月次 spend limit 設定する運用に依存 |
| G8 | unit test for embedded shell scripts | 低 | bats などで script-level test 追加検討 |

### 9.2 拡張余地

- 多様な base model 対応（claude-opus / sonnet / haiku 切替を Issue body のヒントで判断）
- Decompose の出力フォーマット拡張（現状 awk パース、将来は YAML frontmatter）
- Multi-repo orchestration（このリポは単一 repo 前提）
- 他 AI レビュー との統合（Sourcery、Codecov 等）

### 9.3 持続性に関する留意

- claude-code-action の v1 → 将来 v2 への破壊的変更に追従する必要がある
- CodeRabbit の配布 free tier 条件が変わる可能性
- GitHub Actions の課金モデル変更リスク（基本無料枠で運用想定）

---

## 10. レビュー観点 チェックリスト

### 10.1 設計妥当性

- [ ] 3 ルート分類は実用的か（Route の数、分類粒度）
- [ ] ラベル状態機械は competing transitions で破綻しないか
- [ ] Human-in-the-Loop の配置箇所は適切か
- [ ] Decompose の awk パース実装は脆弱でないか

### 10.2 セキュリティ

- [ ] T1〜T6 の脅威に対する緩和は十分か
- [ ] secret が artifact に紛れていないか（live 確認済）
- [ ] author_association ガードが OWNER/MEMBER/COLLABORATOR で十分か（CONTRIBUTOR 含めるべきか議論）
- [ ] CLAUDE.md のセキュリティチェックリストは網羅的か

### 10.3 運用性

- [ ] Anthropic API コスト想定は妥当か（Triage ~$0.05 / 回、Dispatch ~$0.5-2 / 回）
- [ ] 緊急停止コマンド（`gh workflow disable`）が記載されているか
- [ ] cleanup の閾値 (2h) は適切か

### 10.4 拡張性

- [ ] テンプレート repo 利用者がカスタマイズしやすい構造か
- [ ] install.sh の冪等性（再実行安全性）
- [ ] 設定の上書きが直感的か

### 10.5 ドキュメント品質

- [ ] README が「初導入の 5 ステップ」を明示しているか
- [ ] CLAUDE.md（templates/）が TODO プレースホルダで記入箇所を明示しているか
- [ ] CHANGELOG が利用者にとって action item を明確にしているか
- [ ] このドキュメント自体が網羅的か

### 10.6 OSS 配布準備

- [ ] LICENSE (Apache-2.0) が適切か
- [ ] CONTRIBUTING.md / SECURITY.md がコントリビューター向けに十分か
- [ ] Issue / PR テンプレートの使い勝手
- [ ] Release notes の書き方が一貫しているか

---

## 付録 A: 用語

| 用語 | 説明 |
|---|---|
| **scaffold** | 業務ロジックを持たない、導入先で TODO を埋めて使う雛形 |
| **A モデル** | GitHub Template Repository を介した配布形式 |
| **C モデル** | install.sh による既存リポへの後付け配布形式 |
| **dogfood** | scaffold 自身を使って scaffold を改善するメタ運用 |
| **Route A/B/C** | Triage が判定する 3 つの処理経路（実装 / 調査 / 人間） |
| **claude-code-action** | Anthropic 公式の GitHub Actions 用 Claude エージェント。GitHub App として PR を作成 |
| **CodeRabbit** | AI コードレビュー SaaS。GitHub App 形式 |
| **ADR** | Architecture Decision Record |
| **Self-healing** | Symphony が自らの bug を Symphony 自身を通じて発見・修正する循環 |

---

## 付録 B: 参照リンク

### 本リポジトリ内の主要ドキュメント

- [README.md](../README.md) — プロジェクト概要・セットアップ
- [DESIGN.md](../DESIGN.md) — 設計詳細・アーキテクチャ判断
- [CLAUDE.md](../CLAUDE.md) — 本リポ向けエージェント・人間共通ルール
- [SECURITY.md](../SECURITY.md) — 脆弱性報告
- [CONTRIBUTING.md](../CONTRIBUTING.md) — コントリビュート手順
- [CHANGELOG.md](../CHANGELOG.md) — リリース履歴
- [docs/adr/ADR-000-template.md](adr/ADR-000-template.md) — ADR テンプレート
- [docs/adr/ADR-001-coderabbit-bot-author-auto-review.md](adr/ADR-001-coderabbit-bot-author-auto-review.md) — 初の本物 ADR

### 主要 Workflow

- [.github/workflows/symphony-triage.yml](../.github/workflows/symphony-triage.yml)
- [.github/workflows/symphony-dispatch.yml](../.github/workflows/symphony-dispatch.yml)
- [.github/workflows/symphony-investigate.yml](../.github/workflows/symphony-investigate.yml)
- [.github/workflows/symphony-decompose.yml](../.github/workflows/symphony-decompose.yml)
- [.github/workflows/symphony-interactive.yml](../.github/workflows/symphony-interactive.yml)
- [.github/workflows/symphony-cleanup.yml](../.github/workflows/symphony-cleanup.yml)
- [.github/workflows/ci.yml](../.github/workflows/ci.yml)

### 外部参考

- [claude-code-action 公式 GitHub](https://github.com/anthropics/claude-code-action)
- [claude-code-action Security Docs](https://github.com/anthropics/claude-code-action/blob/main/docs/security.md)
- [OpenAI Symphony 原典](https://github.com/openai/symphony)
- [GitHub Repository Rulesets](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/about-rulesets)
- [CodeRabbit Configuration Docs](https://docs.coderabbit.ai/configuration)

---

**ドキュメント末尾。レビューをお願いします。**
