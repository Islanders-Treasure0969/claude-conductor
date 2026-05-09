# ADR-001: CodeRabbit bot-author PR 自動レビュー有効化

## ステータス

Proposed

## コンテキスト

Closes #24

Symphony Dispatch (`anthropics/claude-code-action@v1`) が作成する PR は author が **`app/claude`** (GitHub App、`is_bot: true`) になる。CodeRabbit はデフォルトで bot author の PR を自動レビューしない動作をとるため、#20 / #23 の live E2E では毎回手動で `@coderabbitai review` コメントを投稿してからレビューが起動した。

Symphony scaffold の主要 use case は Symphony が PR を量産することであり、bot author PR でレビューが自動起動しないと二段レビュー体制 (Symphony Dispatch → CodeRabbit → 人間 merge) の中間ステップが機能しない。

関連:
- #15 (cost griefing 対策の延長としてのレビュー自動化)
- #21 (`.coderabbit.yaml` 初期設定)

## 調査した選択肢

### 選択肢 1: Symphony Dispatch 側で `@coderabbitai review` 自動コメント (案 A)

- **概要**: `symphony-dispatch.yml` の `Verify Claude produced output` ステップ直後に、PR が見つかった場合に `gh pr comment <PR_NUMBER> --body "@coderabbitai review"` を追加する。
- **メリット**: CodeRabbit のバージョン・内部設定に依存しない確実な方法。scaffold 利用者全員に自動適用される。既存のフロー (`HAS_PR` チェック済みの変数) を再利用できる。
- **デメリット**: CodeRabbit を導入していない scaffold 利用者のリポジトリに無意味なコメントが残る (実害はない)。CodeRabbit が応答しない場合でもコメントだけ投稿される。
- **参考**: [symphony-dispatch.yml L158-L189](../../.github/workflows/symphony-dispatch.yml)

### 選択肢 2: `.coderabbit.yaml` の設定変更で bot author を許可 (案 B)

- **概要**: `.coderabbit.yaml` の `reviews.auto_review` セクションに `ignore_authors: []` 等の設定を追加し、bot author の PR も自動レビュー対象にする。CodeRabbit Web UI (https://app.coderabbit.ai/) での repo 単位設定も合わせて確認する。
- **メリット**: workflow に変更を加えずに済む。設定ファイルの変更のみで対応できる。CodeRabbit 側で制御されるため、将来的な挙動変更にも追随しやすい。
- **デメリット**: CodeRabbit のドキュメント (https://docs.coderabbit.ai/configuration) に bot author を許可する明示的なオプションが記載されているか未確認。内部的な bot 判定ロジックを設定ファイルでオーバーライドできない可能性がある。
- **参考**: [CodeRabbit 設定ドキュメント](https://docs.coderabbit.ai/configuration)、[現在の .coderabbit.yaml](../../.coderabbit.yaml)

### 選択肢 3: 案 A と案 B の組み合わせ (Defense in depth)

- **概要**: 選択肢 1 と選択肢 2 を両方適用する。
- **メリット**: どちらかが機能しなくても他方がフォールバックとして動作する。案 B の設定有効性が不確かでも案 A が保証する。
- **デメリット**: 実装コストが倍増する。将来的に一方が不要になった場合に保守コストが残る可能性がある。
- **参考**: 選択肢 1・2 の参考資料を参照。

## 決定

<!-- Approve する前にレビュアーがここを記入する -->
<!-- どの選択肢を選ぶか、その理由を記述する -->

(Approve 時にレビュアーが記入してください)

## 実装チケットへの分解

<!-- ⚠️ このセクションは symphony-decompose.yml が自動パースします -->
<!-- フォーマット: `- [ ] {タイトル} <!-- Route A -->` または `<!-- Route C: {理由} -->` -->
<!-- Route A: エージェントが実装する (claude-task ラベルが自動付与される) -->
<!-- Route C: 人間が主体で対応する (triage-C ラベルが付与される) -->

- [ ] symphony-dispatch.yml の Verify Claude produced output ステップ直後に @coderabbitai review 自動コメント step を追加 <!-- Route A -->
- [ ] .coderabbit.yaml の bot author 自動レビュー設定を調査して有効化 <!-- Route C: CodeRabbit ドキュメントの該当オプション有無を人間が確認してから変更要否を判断する必要がある -->

## 影響範囲

- `.github/workflows/symphony-dispatch.yml` — `@coderabbitai review` 自動コメント step 追加 (選択肢 1 または 3 を選んだ場合)
- `.coderabbit.yaml` — bot author 許可設定追加 (選択肢 2 または 3 を選んだ場合)
- scaffold 利用者: CodeRabbit を使わないユーザーのリポジトリに余分なコメントが残る可能性 (選択肢 1 または 3 の場合)
