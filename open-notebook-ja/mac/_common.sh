# Open Notebook ランチャー共通処理（各 .command から source される）
# macOS 標準の bash 3.2 で動くように書いています。

# 呼び出し側（各 .command）が SCRIPT_DIR を解決してから source します。
: "${SCRIPT_DIR:?SCRIPT_DIR が未設定です}"
PROJECT_DIR="$(cd -P "$SCRIPT_DIR/.." && pwd)"

say()  { printf '%s\n' "$*"; }
ok()   { printf '  ✓ %s\n' "$*"; }
warn() { printf '  ! %s\n' "$*"; }

# エラーで終わるときは、ウィンドウが即閉じても内容が読めるように待つ
die() {
  printf '\n  ✗ %s\n' "$*"
  printf '\nEnter キーを押すと閉じます。'
  read -r _
  exit 1
}

finish() {
  printf '\nEnter キーを押すと閉じます。'
  read -r _
}

# --- 前提チェック --------------------------------------------------
require_project() {
  [ -f "$PROJECT_DIR/docker-compose.yml" ] || die "docker-compose.yml が見つかりません（探した場所: $PROJECT_DIR）
    デスクトップのアイコンはコピーではなくエイリアス（シンボリックリンク）である必要があります。
    「デスクトップにアイコンを作る.command」を実行し直してください。"
  cd "$PROJECT_DIR" || die "$PROJECT_DIR に移動できません"
}

require_docker_installed() {
  command -v docker >/dev/null 2>&1 || die "Docker が見つかりません。
    Docker Desktop をインストールしてください: https://www.docker.com/products/docker-desktop/"
}

# Docker Desktop が動いていなければ起動して待つ
require_docker_running() {
  if docker info >/dev/null 2>&1; then
    ok "Docker は起動しています"
    return 0
  fi

  say "  Docker Desktop を起動しています..."
  open -a Docker 2>/dev/null || die "Docker Desktop を起動できませんでした。手動で起動してから、もう一度お試しください。"

  local i
  for i in $(seq 1 60); do
    sleep 2
    if docker info >/dev/null 2>&1; then
      ok "Docker が起動しました"
      return 0
    fi
  done
  die "Docker Desktop の起動を 2 分待ちましたが応答しません。
    Docker Desktop を手動で起動し、クジラのアイコンが安定してから、もう一度お試しください。"
}

# .env が無ければ作り、暗号化キーを自動生成する
ensure_env_file() {
  [ -f "$PROJECT_DIR/.env" ] && return 0

  say "  初回起動のようです。.env を作成します..."
  [ -f "$PROJECT_DIR/.env.example" ] || die ".env.example が見つかりません"

  local key
  key="$(openssl rand -hex 32)" || die "暗号化キーを生成できませんでした"
  sed "s|^OPEN_NOTEBOOK_ENCRYPTION_KEY=.*|OPEN_NOTEBOOK_ENCRYPTION_KEY=${key}|" \
    "$PROJECT_DIR/.env.example" > "$PROJECT_DIR/.env" || die ".env を作成できませんでした"

  ok ".env を作成し、暗号化キーを自動生成しました"
  warn "この鍵は $PROJECT_DIR/.env にあります。"
  warn "別の PC にノートを持ち出す場合は同じ鍵が必要です。控えておいてください。"
}

# Web UI が応答するまで待つ
wait_for_ui() {
  local max="${1:-90}" i
  say "  Open Notebook の起動を待っています..."
  for i in $(seq 1 "$max"); do
    if curl -sf --max-time 3 http://localhost:8502 >/dev/null 2>&1; then
      ok "起動しました"
      return 0
    fi
    # 15 回（約 30 秒）ごとに経過を出す
    if [ $((i % 15)) -eq 0 ]; then
      say "  ...まだ準備中です（${i} 回目の確認）"
    fi
    sleep 2
  done
  return 1
}
