# symphony-claude-gha — 開発ルール

## このリポジトリについて

OpenAI Symphony 相当のエージェントオーケストレーションを **Claude Code + GitHub Actions + GitHub Issues** で再現するための **scaffolding (雛形)** リポジトリ。

このリポジトリ自体は業務ロジックを持たず、`.github/workflows/` と `templates/CLAUDE.md` を社内プロジェクトへ配布することが目的。

## ディレクトリ構成

```
.
├── .github/
│   ├── workflows/
│   │   ├── symphony-dispatch.yml      # Issue ラベル検知 → エージェント起動 (核心)
│   │   ├── symphony-interactive.yml   # @claude メンション対応
│   │   └── symphony-cleanup.yml       # 停滞 Issue のタイムアウト処理
│   └── ISSUE_TEMPLATE/
│       └── claude-task.md             # 作業依頼テンプレート
├── templates/
│   └── CLAUDE.md                      # 導入先リポジトリ用 CLAUDE.md テンプレート
├── CLAUDE.md                          # ← このファイル (本リポジトリ用)
├── README.md                          # セットアップ手順・セキュリティ要点
└── .gitignore
```

## 開発ルール

### ブランチ戦略
- `main` への直接 push は禁止
- 機能追加/修正は `feature/` `fix/` `chore/` `docs/` プレフィックスを使用
- workflow の変更は実 GHA で動作確認するまで PR を merge しない

### コミットメッセージ
- Conventional Commits (`feat:` / `fix:` / `docs:` / `chore:` / `refactor:`)

### workflow 編集時のチェック
- YAML 構文検証:
  ```bash
  python3 -c "import yaml,glob; [yaml.safe_load(open(p)) for p in glob.glob('.github/workflows/*.yml')]" \
    && echo OK
  ```
- (推奨) actionlint インストール後:
  ```bash
  actionlint .github/workflows/*.yml
  ```

### セキュリティ要件 (workflow 変更時に必ず確認)
- Issue title/body 等のユーザー制御値は **必ず `env:` 経由**で `prompt` に渡す (run ブロックへの直接展開禁止)
- `permissions:` は最小権限のみ宣言
- `--allowedTools` でエージェントが触れるツールを明示的に制限
- `ANTHROPIC_API_KEY` は GitHub Secrets のみ。コードに直書きしない
- `GITHUB_TOKEN` を使用 (PAT は使わない)

### テンプレート編集時の注意
- `templates/CLAUDE.md` は導入先で `TODO:` を埋める前提のテンプレート。
  `TODO:` プレースホルダは消さないこと。

## 不明点の扱い

実装中に判断できない仕様があれば、**推測で進めず Issue にコメントして停止する**。
特に workflow のセキュリティ関連 (権限・トークン・トリガー条件) は独断で変更しない。

## 参照リソース

- 元設計資料: `/Users/iwashita/Downloads/symphony-claude-code-gha-design.md`
- claude-code-action 公式: https://github.com/anthropics/claude-code-action
- claude-code-action Security Docs: https://github.com/anthropics/claude-code-action/blob/main/docs/security.md
- OpenAI Symphony: https://github.com/openai/symphony
