#!/usr/bin/env bash
# =============================================================================
# claude-conductor installer (C-model: 既存リポジトリへの後付けインストール)
# -----------------------------------------------------------------------------
# 用途:
#   既存の git リポジトリに claude-conductor の scaffolding を導入する。
#   GitHub Template Repository (A モデル) を使えない場合の代替手段。
#
# 使い方:
#   curl -fsSL https://raw.githubusercontent.com/Islanders-Treasure0969/claude-conductor/main/install.sh | bash
#   # または
#   bash <(curl -fsSL https://raw.githubusercontent.com/Islanders-Treasure0969/claude-conductor/main/install.sh)
#
# オプション (環境変数):
#   SYMPHONY_REF=main           リリースタグ・ブランチ・commit hash で固定可
#   SYMPHONY_REPO=org/repo      フォークから取得する場合
#   SYMPHONY_TARGET=.           インストール先ディレクトリ (デフォルト: カレント)
#   SYMPHONY_FORCE=0            既存ファイルを上書きする (1 で有効)
#
# 安全性:
#   - 既存ファイルはデフォルトで上書きしない (バックアップ作成)
#   - git リポジトリ外では実行しない
#   - 必要な前提コマンド (git, curl, tar) をチェック
# =============================================================================
set -euo pipefail

# --- 設定 -------------------------------------------------------------------
SYMPHONY_REPO="${SYMPHONY_REPO:-Islanders-Treasure0969/claude-conductor}"
SYMPHONY_REF="${SYMPHONY_REF:-main}"
SYMPHONY_TARGET="${SYMPHONY_TARGET:-.}"
SYMPHONY_FORCE="${SYMPHONY_FORCE:-0}"

# 配布ファイル (アーカイブ内のパス)
FILES=(
  ".github/workflows/symphony-triage.yml"
  ".github/workflows/symphony-dispatch.yml"
  ".github/workflows/symphony-investigate.yml"
  ".github/workflows/symphony-decompose.yml"
  ".github/workflows/symphony-interactive.yml"
  ".github/workflows/symphony-cleanup.yml"
  ".github/ISSUE_TEMPLATE/claude-task.md"
  ".github/ISSUE_TEMPLATE/investigation.md"
  ".github/labels.yml"
  "docs/adr/ADR-000-template.md"
  "scripts/setup-labels.sh"
)

# CLAUDE.md は templates/ から導入先のルートに配置するため別扱い
TEMPLATE_FILE_SRC="templates/CLAUDE.md"
TEMPLATE_FILE_DST="CLAUDE.md"

# --- ロギング ---------------------------------------------------------------
log()  { printf '\033[1;34m▸\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m⚠\033[0m %s\n' "$*" >&2; }
err()  { printf '\033[1;31m✗\033[0m %s\n' "$*" >&2; }
ok()   { printf '\033[1;32m✓\033[0m %s\n' "$*"; }

# --- 前提チェック -----------------------------------------------------------
check_prereqs() {
  local missing=()
  for cmd in git curl tar; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      missing+=("$cmd")
    fi
  done
  if [ "${#missing[@]}" -gt 0 ]; then
    err "必要なコマンドが見つかりません: ${missing[*]}"
    exit 1
  fi
}

check_git_repo() {
  cd "$SYMPHONY_TARGET"
  if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    err "$SYMPHONY_TARGET は git リポジトリではありません。"
    err "先に 'git init' を実行するか、SYMPHONY_TARGET を指定してください。"
    exit 1
  fi
}

# --- ダウンロード -----------------------------------------------------------
download_archive() {
  local archive_url="https://codeload.github.com/${SYMPHONY_REPO}/tar.gz/${SYMPHONY_REF}"
  local tmpdir
  tmpdir=$(mktemp -d)
  trap 'rm -rf "$tmpdir"' EXIT

  log "アーカイブを取得中: $archive_url"
  if ! curl -fsSL "$archive_url" -o "$tmpdir/archive.tar.gz"; then
    err "アーカイブの取得に失敗しました。SYMPHONY_REPO / SYMPHONY_REF を確認してください。"
    exit 1
  fi

  log "アーカイブを展開中..."
  tar -xzf "$tmpdir/archive.tar.gz" -C "$tmpdir"

  # 展開後のディレクトリ名 (例: claude-conductor-main) を特定
  local extracted
  extracted=$(find "$tmpdir" -mindepth 1 -maxdepth 1 -type d | head -1)
  if [ -z "$extracted" ]; then
    err "アーカイブの展開に失敗しました。"
    exit 1
  fi

  echo "$extracted"
}

# --- インストール処理 -------------------------------------------------------
install_file() {
  local src="$1"
  local dst="$2"

  if [ ! -f "$src" ]; then
    warn "ソースが見つかりません (スキップ): $src"
    return
  fi

  if [ -f "$dst" ]; then
    if [ "$SYMPHONY_FORCE" = "1" ]; then
      cp -p "$dst" "${dst}.bak"
      log "既存ファイルをバックアップ: ${dst}.bak"
    else
      warn "既存ファイルが存在します (スキップ): $dst"
      warn "  上書きするには SYMPHONY_FORCE=1 で再実行してください。"
      return
    fi
  fi

  mkdir -p "$(dirname "$dst")"
  cp -p "$src" "$dst"
  ok "インストール: $dst"
}

main() {
  log "claude-conductor installer"
  log "  REPO:   $SYMPHONY_REPO"
  log "  REF:    $SYMPHONY_REF"
  log "  TARGET: $(cd "$SYMPHONY_TARGET" && pwd)"
  log "  FORCE:  $SYMPHONY_FORCE"
  echo

  check_prereqs
  check_git_repo

  local extracted
  extracted=$(download_archive)

  log "ファイルを配置中..."
  for f in "${FILES[@]}"; do
    install_file "$extracted/$f" "$f"
  done

  install_file "$extracted/$TEMPLATE_FILE_SRC" "$TEMPLATE_FILE_DST"

  # setup-labels.sh に実行権限を付与
  if [ -f scripts/setup-labels.sh ]; then
    chmod +x scripts/setup-labels.sh
  fi

  echo
  ok "インストール完了"
  echo
  cat <<'NEXT'
─────────────────────────────────────────────────────────────
  次のステップ:

  1. CLAUDE.md の TODO: プレースホルダを埋める
     (プロジェクト概要・ディレクトリ構成・テストコマンド)

  2. GitHub Secrets に ANTHROPIC_API_KEY を設定
     Settings → Secrets and variables → Actions

  3. ラベルを作成
     ./scripts/setup-labels.sh                 # カレントリポ
     ./scripts/setup-labels.sh owner/your-repo # 明示指定
     (要 gh CLI + yq)

  4. (推奨) Branch protection を設定
     main ブランチに 1 approve 必須を強制

  5. 動作確認
     "🔧 実装依頼 (Route A)" テンプレートで Issue を立ててみる
─────────────────────────────────────────────────────────────
NEXT
}

main "$@"
