# プロジェクトコンテキスト (Claude Code 共通ルール)

<!--
このファイルは導入先リポジトリのルートに配置するテンプレートです。
`TODO:` を埋めて自分のプロジェクト用に書き換えてから使ってください。
-->

## プロジェクト概要

<!-- リポジトリの目的・技術スタック・主要なドメインを 3〜5 行で記述 -->
TODO: プロジェクト固有の概要をここに記述

**技術スタック**:
- 言語: TODO
- フレームワーク: TODO
- データベース: TODO
- インフラ: TODO

## ディレクトリ構成

<!-- 主要ディレクトリの役割。エージェントがコードベースを把握する手がかりになる -->
TODO: 主要ディレクトリと役割を記述

```
src/
  ├── (例) models/     # データモデル定義
  ├── (例) services/   # ビジネスロジック
  └── (例) api/        # エンドポイント定義
tests/
docs/
  └── adr/             # Architecture Decision Records
```

## 開発ルール

### ブランチ戦略 (TBD: Trunk-Based Development)

- `main` ブランチへの直接 push は禁止
- 全作業は Issue を起点にする (TiDD: Ticket-driven Development)
- エージェント実装ブランチ: `claude/issue-{N}`
- ADR ブランチ: `adr/issue-{N}`
- その他: `feature/`, `fix/`, `chore/`, `docs/` プレフィックスを使用
- ブランチは作成後できる限り速やかに PR を出すこと

### PR・レビュールール

- **全ての PR に 1 approve 以上が必須** (エージェント作成の PR も例外なし)
- PR は小さく保つ (1 Issue = 1 PR を原則とする)
- PR 本文には必ず `Closes #{Issue番号}` を含める

### テスト

- PR は必ずテストをパスさせてから作成すること
- テストコマンド: TODO (例: `npm test` / `pytest` / `dbt test` 等)
- 新機能には必ずテストを追加すること

### コミットメッセージ

Conventional Commits に従うこと:
- `feat:` 新機能
- `fix:` バグ修正
- `docs:` ドキュメントのみの変更
- `refactor:` 機能変更を伴わないリファクタリング
- `test:` テストの追加・修正
- `chore:` ビルド・CI 等の変更

## ADR (Architecture Decision Records)

アーキテクチャ上の重要な決定は `docs/adr/ADR-NNN-{title}.md` に記録する。
既存の ADR は必ず確認し、過去の決定と矛盾しない実装を行うこと。

ADR フォーマットは `docs/adr/ADR-000-template.md` を参照。
`symphony-decompose.yml` がパースする「実装チケットへの分解」セクションは
フォーマット厳守 (フォーマット変更時は workflow も合わせて修正が必要)。

## 禁止事項

- シークレット・API キーをコードに直書きしない
- 本番データベースへの直接アクセスをしない
- 他のエージェントが作業中のブランチのファイルを変更しない
- `main` ブランチへの直接 push をしない
- テストを無効化・削除して通過させようとしない

## 不明点の扱い

実装中に判断できないことがあれば、**推測で進めず Issue にコメントして停止すること**。
コメントには以下を含めること:

- 何が不明か
- 判断するために必要な情報
- 考えられる選択肢 (あれば)

該当する典型ケース:
- 仕様の解釈に複数の妥当な選択肢がある
- 既存実装との整合が取れない
- 完了条件が満たせるかが事前に判断できない

## エージェント運用ルール (Symphony 連携)

このリポジトリは Symphony 同等のエージェントオーケストレーションを利用しています。
Issue ラベルがそのままステートマシンの状態を表します。

### Triage フェーズ

Issue が opened されると `symphony-triage.yml` が起動し、内容を LLM 分析して
3 ルートに自動振り分けする。

- `triage-pending` → 分類中
- `triage-A` → 即実装可能 (Route A)
- `triage-B` → 調査・設計先行 (Route B)
- `triage-C` → 人間主体 (Route C)

### Route A: 実装パイプライン

`claude-task` ラベルの付与で `symphony-dispatch.yml` が起動する。

ラベル遷移: `claude-task` → `claude-in-progress` → `claude-review` / `claude-failed`

### Route B: 調査・設計パイプライン

`investigation` ラベルの付与で `symphony-investigate.yml` が起動し、
ADR draft PR を作成する。

ラベル遷移: `investigation` → `claude-in-progress` → `adr-draft` / `claude-failed`

ADR PR が merge されると `symphony-decompose.yml` が「実装チケットへの分解」
セクションをパースし、実装チケット (Route A) または人間対応チケット (Route C) を
自動生成する。

### 対話モード

`@claude` メンションで `symphony-interactive.yml` 経由の対話的応答が可能。
write 権限ユーザーのみがトリガーできる (claude-code-action のデフォルト動作)。

### Cleanup

`claude-in-progress` のまま 2 時間以上更新がない Issue は `symphony-cleanup.yml`
で `claude-failed` に遷移する (GHA 側のサイレント失敗に対するセーフティネット)。
