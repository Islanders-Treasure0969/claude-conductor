#!/usr/bin/env bash
# =============================================================================
# Symphony ラベル一括セットアップ
# -----------------------------------------------------------------------------
# 用途:
#   .github/labels.yml に定義された 4 つのラベルを GitHub リポジトリに作成
#   または更新する。Symphony ワークフロー導入時の必須セットアップ。
#
# 前提:
#   - gh CLI がインストール・認証済み (`gh auth status` が通る)
#   - yq (mikefarah/yq v4+) がインストール済み
#       brew install yq
#   - 引数: 対象リポジトリ (owner/repo)。省略時はカレントリポジトリ。
#
# 使い方:
#   ./scripts/setup-labels.sh                    # カレント repo
#   ./scripts/setup-labels.sh owner/repo         # 明示指定
# =============================================================================
set -euo pipefail

REPO="${1:-}"
LABELS_FILE="$(cd "$(dirname "$0")/.." && pwd)/.github/labels.yml"

if [[ ! -f "$LABELS_FILE" ]]; then
  echo "Error: $LABELS_FILE が見つかりません" >&2
  exit 1
fi

if ! command -v yq >/dev/null 2>&1; then
  echo "Error: yq がインストールされていません (brew install yq)" >&2
  exit 1
fi

if ! command -v gh >/dev/null 2>&1; then
  echo "Error: gh CLI がインストールされていません" >&2
  exit 1
fi

REPO_ARG=()
if [[ -n "$REPO" ]]; then
  REPO_ARG=(--repo "$REPO")
  echo "==> Target: $REPO"
else
  echo "==> Target: (current repository)"
fi

count=$(yq '. | length' "$LABELS_FILE")
for i in $(seq 0 $((count - 1))); do
  name=$(yq ".[$i].name" "$LABELS_FILE")
  color=$(yq ".[$i].color" "$LABELS_FILE")
  description=$(yq ".[$i].description" "$LABELS_FILE")

  if gh label list "${REPO_ARG[@]}" --json name --jq '.[].name' | grep -qx "$name"; then
    echo "==> Update: $name"
    gh label edit "$name" \
      "${REPO_ARG[@]}" \
      --color "$color" \
      --description "$description"
  else
    echo "==> Create: $name"
    gh label create "$name" \
      "${REPO_ARG[@]}" \
      --color "$color" \
      --description "$description"
  fi
done

echo "==> Done."
