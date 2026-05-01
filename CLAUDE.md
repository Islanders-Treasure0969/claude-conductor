# プロジェクトコンテキスト (Claude Code 共通ルール)

<!--
このファイルは Claude Code エージェント (ローカル実行・GitHub Actions 経由実行とも)
が常に参照する共通コンテキストです。
プロジェクト固有のルールはここに集約してください。
-->

## プロジェクト概要

<!-- リポジトリの目的・技術スタック・主要なドメインを 3〜5 行で記述 -->
TODO: プロジェクト固有の概要をここに記述

## ディレクトリ構成

<!-- 主要ディレクトリの役割。エージェントがコードベースを把握する手がかりになる -->
TODO: 主要ディレクトリと役割を記述

## 開発ルール

### ブランチ戦略
- `main` ブランチへの直接 push は禁止
- Issue 駆動の自走作業は `claude/issue-{N}` ブランチを使用
- それ以外は `feature/`, `fix/`, `chore/` プレフィックスを使用

### テスト
- PR は必ずテストをパスさせてから作成すること
- テストコマンド: TODO (例: `npm test` / `pytest` / `dbt test` 等)

### コミットメッセージ
- Conventional Commits に従う (`feat:` / `fix:` / `docs:` / `chore:` ...)

### 禁止事項
- シークレット・API キーをコードに直書きしない
- 本番データベースへの直接アクセスをしない
- 他のエージェントのワークスペース (別ブランチ) を変更しない

## 不明点の扱い

実装中に判断できないことがあれば、**推測で進めず Issue にコメントして停止すること**。
- 仕様の解釈に複数の妥当な選択肢がある
- 既存実装との整合が取れない
- 完了条件が満たせるかが事前に判断できない

これらに該当する場合は、判断材料を整理して Issue にコメントし、人間の判断を待つ。

## エージェント運用ルール (Symphony 連携)

- Issue ラベル `claude-task` の付与でこのリポジトリの `.github/workflows/symphony-dispatch.yml` が起動する
- ラベル遷移: `claude-task` → `claude-in-progress` → `claude-review` / `claude-failed`
- `@claude` メンションで `.github/workflows/symphony-interactive.yml` 経由の対話的応答が可能
- `claude-in-progress` のまま 2 時間以上更新がない Issue は cleanup ワークフローで `claude-failed` に遷移する
