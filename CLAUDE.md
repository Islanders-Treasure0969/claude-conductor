# claude-conductor — 開発ルール

## このリポジトリについて

OpenAI Symphony 相当のエージェントオーケストレーションを **Claude Code + GitHub Actions + GitHub Issues** で再現するための **scaffolding (雛形)** リポジトリ。

このリポジトリ自体は業務ロジックを持たず、`.github/`、`templates/`、`scripts/`、`docs/adr/` を導入先リポジトリへ配布することが目的。

OSS として公開する前提で、配布形態は **GitHub Template Repository** を一次導線とし、
既存リポへの後付けは **`install.sh` (curl bash)** を補助手段として提供する。

## ディレクトリ構成

```
.
├── .github/
│   ├── workflows/
│   │   ├── symphony-triage.yml        # ① Issue opened → 3 ルートに自動振り分け
│   │   ├── symphony-dispatch.yml      # ② claude-task → 実装エージェント起動
│   │   ├── symphony-investigate.yml   # ③ investigation → 調査エージェント (ADR draft)
│   │   ├── symphony-decompose.yml     # ④ ADR merge → 実装チケット自動生成
│   │   ├── symphony-interactive.yml   # ⑤ @claude メンション対応
│   │   └── symphony-cleanup.yml       # ⑥ 停滞 Issue のタイムアウト処理
│   ├── ISSUE_TEMPLATE/
│   │   ├── claude-task.md             # Route A 用 Issue テンプレート
│   │   └── investigation.md           # Route B 用 Issue テンプレート
│   └── labels.yml                     # ステートマシン用ラベル定義
├── docs/
│   └── adr/
│       └── ADR-000-template.md        # ADR テンプレート (decompose のパース対象)
├── scripts/
│   └── setup-labels.sh                # labels.yml を gh CLI で同期するスクリプト
├── templates/
│   └── CLAUDE.md                      # 導入先リポジトリ用 CLAUDE.md テンプレート
├── CLAUDE.md                          # ← このファイル (本リポジトリ用)
├── DESIGN.md                          # アーキテクチャ設計資料
├── README.md                          # セットアップ手順・セキュリティ要点
├── LICENSE                            # Apache-2.0
└── .gitignore
```

## アーキテクチャ概観

```
Issue opened
   │
   ▼
[symphony-triage.yml]  LLM が 3 ルートに自動振り分け
   │
   ├─ triage-A → 人間が claude-task ラベル付与
   │             [symphony-dispatch.yml] → PR 作成 → 1 approve → merge
   │
   ├─ triage-B → 人間が investigation ラベル付与
   │             [symphony-investigate.yml] → ADR draft PR
   │             → 人間が ADR を編集・approve・merge
   │             [symphony-decompose.yml] → 実装チケット自動生成
   │             (Route A: claude-task / Route C: triage-C)
   │
   └─ triage-C → 人間がアサイン・対応 (エージェントは関与しない)
```

詳細は [DESIGN.md](DESIGN.md) を参照。

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
- gh CLI 経由のコメント本文は実改行が必要なため、シェルリテラルの `\n` は使わず
  `printf` またはヒアドキュメントで生成する (zip 由来 workflow の典型バグ)

### ADR フォーマット依存
- `symphony-decompose.yml` は `docs/adr/ADR-NNN-*.md` の「実装チケットへの分解」
  セクションを `awk` でパースする
- ADR テンプレート (`docs/adr/ADR-000-template.md`) のセクション見出しを変更する
  場合は `symphony-decompose.yml` も合わせて修正すること

### テンプレート編集時の注意
- `templates/CLAUDE.md` は導入先で `TODO:` を埋める前提のテンプレート
- `TODO:` プレースホルダは消さないこと

## 不明点の扱い

実装中に判断できない仕様があれば、**推測で進めず Issue にコメントして停止する**。
特に workflow のセキュリティ関連 (権限・トークン・トリガー条件) は独断で変更しない。

## 参照リソース

- claude-code-action 公式: https://github.com/anthropics/claude-code-action
- claude-code-action Security Docs: https://github.com/anthropics/claude-code-action/blob/main/docs/security.md
- OpenAI Symphony: https://github.com/openai/symphony
