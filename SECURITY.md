# Security Policy

このリポジトリは LLM エージェント (Claude Code) を GitHub Actions で実行する性質上、
通常のソフトウェア以上に **prompt injection / コマンドインジェクション / シークレット漏洩**
に対する配慮が必要です。

## サポートしているバージョン

| バージョン | サポート状況 |
|---|---|
| `main` (最新) | ✅ サポート |
| それ以外 | ❌ サポート対象外 |

## 脆弱性の報告

セキュリティ脆弱性を発見した場合、**公開 Issue ではなく** 以下のいずれかの方法で
報告してください。

### 推奨: GitHub Private Vulnerability Reporting

1. リポジトリの **Security** タブを開く
2. **Report a vulnerability** をクリック
3. 必要事項を記入して送信

### 代替: メール

[hyuujm812@icloud.com](mailto:hyuujm812@icloud.com) 宛に下記情報を含めて送信してください。

- 影響を受けるバージョン (commit hash 推奨)
- 再現手順
- 想定される影響範囲
- (可能であれば) 修正案

## 対応プロセス

| ステップ | 期間目安 |
|---|---|
| 受領確認 | 営業日 2 日以内 |
| 影響評価・トリアージ | 1 週間以内 |
| 修正版リリース or 緩和策の提示 | 重大度に応じて 30 日以内 |

## 設計上のセキュリティ前提

このリポジトリの workflow を導入する際、以下が **前提条件** として満たされている
必要があります。これらが満たされていない環境ではセキュリティ保証ができません。

### 必須要件

- ✅ `ANTHROPIC_API_KEY` は GitHub Secrets に格納 (リポジトリやコードに直書きしない)
- ✅ `GITHUB_TOKEN` (短命) のみを使用 (PAT を使わない)
- ✅ `permissions:` は各 workflow で必要最小限のみ宣言 (本リポはこの方針で実装済み)
- ✅ `--allowedTools` でエージェントが触れるツールを明示的に制限 (本リポ実装済み)
- ✅ Issue title / body 等のユーザー制御値は **必ず `env:` 経由** で `prompt` に渡す
  (`run:` ブロックへの直接展開はコマンドインジェクションを許す)
- ✅ `@claude` メンションは write 権限ユーザーのみがトリガー可能
  (claude-code-action のデフォルト動作 — 変更しないこと)
- ✅ Pull request の merge には **1 approve 以上必須** (Branch Protection で強制)

### Prompt Injection への対応

エージェントが扱う Issue / PR コメントは、外部ユーザーが改変可能な信頼できない入力です。
以下の防御策を実装しています。

1. **入力経路の限定**: Issue title / body は `env:` 経由のみで渡し、シェル展開を排除
2. **権限の最小化**: `--allowedTools` で MCP ツールを明示列挙 (例: `mcp__github__create_pull_request` は許可、`mcp__github__delete_repository` は不許可)
3. **アクション制御**: `permissions:` で workflow ごとに最小権限を宣言
4. **Triage の分類**: セキュリティ・認証関連の変更は Route C (人間主体) に振り分けるよう
   `symphony-triage.yml` のプロンプトに明記

### 残存リスクと運用上の注意

- Issue 本文に「ファイル X を削除してください」と書かれた場合、エージェントは指示通りに
  削除する可能性があります。**信頼できないユーザーから write 権限を奪われると危険**です
- PR レビュー時、エージェントが提案するコードは必ず人間がレビューしてください
  (1 approve 必須を Branch Protection で強制)
- `--max-turns 30` を超えた場合、エージェントは途中停止します。再実行の判断は人間が行ってください
- `symphony-decompose.yml` は ADR の markdown を信頼してパースします。ADR の merge 自体に
  人間 approve を必須にすることで、悪意ある ADR を排除してください

## 参考資料

- [claude-code-action Security Documentation](https://github.com/anthropics/claude-code-action/blob/main/docs/security.md)
- [GitHub Security Advisories](https://docs.github.com/en/code-security/security-advisories)
- [OWASP Top 10 for LLM Applications](https://owasp.org/www-project-top-10-for-large-language-model-applications/)
