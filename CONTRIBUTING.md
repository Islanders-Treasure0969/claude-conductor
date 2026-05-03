# Contributing to claude-conductor

Thanks for your interest in contributing!
このリポジトリは Claude Code エージェントを GitHub Actions で動かすための
scaffolding を提供しています。

## 開発の流れ

### 1. Issue で議論する

まず Issue を立てて、何を変更したいかを記述してください。
本リポジトリ自身が Symphony を運用しているため、**Issue を立てると Triage エージェントが
自動分類**します。

- Route A (実装): 仕様が明確な小さな変更 → そのまま PR まで自走
- Route B (調査・設計): アーキテクチャ判断を伴う変更 → ADR draft を作成
- Route C (人間主体): セキュリティや要件定義 → 人間で議論

### 2. ブランチ戦略

`main` への直接 push は禁止です。

| プレフィックス | 用途 |
|---|---|
| `feature/` | 新機能 |
| `fix/` | バグ修正 |
| `chore/` | ビルド・CI・リファクタリング |
| `docs/` | ドキュメントのみ |
| `claude/issue-{N}` | 実装エージェント用 (自動付与) |
| `adr/issue-{N}` | ADR draft 用 (自動付与) |

### 3. コミットメッセージ

[Conventional Commits](https://www.conventionalcommits.org/) に従ってください。

```
feat(workflows): add new triage rule for security issues

Issue 内に "security" ラベルが含まれている場合、Route C へ自動振り分けるよう
判定基準を強化。
```

主なプレフィックス:
- `feat:` 新機能
- `fix:` バグ修正
- `docs:` ドキュメントのみ
- `refactor:` 機能変更を伴わないリファクタリング
- `test:` テストの追加・修正
- `chore:` ビルド・CI・依存関係

### 4. PR の作成

- 1 Issue = 1 PR を原則
- PR 本文に `Closes #{Issue番号}` を含める
- **すべての PR に 1 approve 以上が必須** (エージェント PR も例外なし)

## コードレビューの観点

### Workflow 編集時に必ず確認

- ✅ Issue title / body 等のユーザー制御値は **必ず `env:` 経由**で `prompt` に渡す
  (`run:` ブロックへの直接展開禁止)
- ✅ `permissions:` は最小権限のみ宣言
- ✅ `--allowedTools` でエージェントが触れるツールを明示的に制限
- ✅ `ANTHROPIC_API_KEY` は GitHub Secrets のみ。コード直書き禁止
- ✅ `GITHUB_TOKEN` (短命) を使用、PAT は使わない
- ✅ gh CLI 経由のコメント本文は `printf` またはヒアドキュメントで実改行を生成
  (シェルリテラル `\n` は GitHub UI で文字列として表示されてしまう)

### ADR フォーマット依存

`symphony-decompose.yml` は `docs/adr/ADR-NNN-*.md` の「実装チケットへの分解」
セクションを `awk` でパースしています。ADR テンプレート (`docs/adr/ADR-000-template.md`) の
セクション見出しを変更する場合は `symphony-decompose.yml` も合わせて修正してください。

## ローカル検証

### Workflow YAML の構文検証

```bash
python3 -c "import yaml,glob; [yaml.safe_load(open(p)) for p in glob.glob('.github/workflows/*.yml')]" \
  && echo OK
```

### actionlint (推奨)

```bash
brew install actionlint
actionlint .github/workflows/*.yml
```

CI でも自動実行されるため、ローカルで通せば PR で再びチェックされます。

### labels.yml の構文検証

```bash
python3 -c "import yaml; yaml.safe_load(open('.github/labels.yml'))" && echo OK
```

### scripts/setup-labels.sh の dry-run

```bash
bash -n scripts/setup-labels.sh   # 構文チェック
```

実環境への適用は対象リポジトリで `gh auth status` を確認してから実行してください。

## ライセンス

貢献は Apache License 2.0 のもとで受け入れられます。
PR を提出することで、Apache-2.0 ライセンスのもとであなたの貢献を配布することに
同意したものとみなします。

## 不明点があれば

実装中に判断できないことがあれば、**推測で進めず Issue にコメントして停止すること**。
特に workflow のセキュリティ関連 (権限・トークン・トリガー条件) は独断で変更しないでください。
