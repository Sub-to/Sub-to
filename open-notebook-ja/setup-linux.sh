#!/usr/bin/env bash
# Linux に Open Notebook（日本語設定つき）を導入します。
#
#   ./setup-linux.sh              導入して起動する
#   ./setup-linux.sh --icons      デスクトップとアプリ一覧にアイコンを追加する
#   ./setup-linux.sh --no-docling Docling を無効にして導入する（軽量・高速起動）
set -uo pipefail

HERE="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$HERE" || exit 1

say()  { printf '%s\n' "$*"; }
ok()   { printf '  ✓ %s\n' "$*"; }
warn() { printf '  ! %s\n' "$*"; }
die()  { printf '\n  ✗ %s\n' "$*"; exit 1; }

ICONS=0; NO_DOCLING=0
for a in "$@"; do
  case "$a" in
    --icons) ICONS=1 ;;
    --no-docling) NO_DOCLING=1 ;;
    *) die "不明なオプション: $a（使えるのは --icons / --no-docling）" ;;
  esac
done

say "==============================================="
say "  Open Notebook 導入（Linux / 日本語設定つき）"
say "==============================================="
say

# --- 1. Docker の確認 -------------------------------------------------
command -v docker >/dev/null 2>&1 || die "docker が見つかりません。先に Docker Engine を入れてください:
    curl -fsSL https://get.docker.com | sudo sh
    sudo usermod -aG docker \"\$USER\"    # 実行後は一度ログアウト／ログインしてください"

docker compose version >/dev/null 2>&1 || die "docker compose (v2) が使えません。
    docker-compose-plugin を導入してください。"

if ! docker info >/dev/null 2>&1; then
  # 原因を具体的に切り分けてから終わる
  if [ "$(systemctl is-active docker 2>/dev/null)" != "active" ]; then
    die "Docker サービスが動いていません。次を実行してください:

      sudo systemctl enable --now docker

    そのあと、このスクリプトをもう一度実行してください。"
  fi

  if ! id -nG 2>/dev/null | tr ' ' '\n' | grep -qx docker; then
    me="$(id -un)"
    hint="    一度ログアウトしてログインし直してから、もう一度実行してください。"
    command -v newgrp >/dev/null 2>&1 && hint="    newgrp docker    ← 新しいシェルに切り替わります
    そのシェルで、もう一度このスクリプトを実行してください。
    （ログアウト／ログインでも同じです）"
    die "あなた（$me）が docker グループに入っていないため、Docker を操作できません。
    サービス自体は動いています（/var/run/docker.sock は root:docker 所有）。

    1) グループに追加する:

      sudo usermod -aG docker $me

    2) それを今のセッションに反映させる:

$hint"
  fi

  die "Docker デーモンに接続できません。サービスもグループも問題なさそうですが、
    docker info が失敗します。次の出力を確認してください:

      docker info
      systemctl status docker"
fi
ok "Docker は使えます（$(docker --version | cut -d, -f1)）"

# --- 2. .env を用意 ---------------------------------------------------
if [ -f .env ]; then
  ok ".env はすでにあります（作り直しません）"
else
  [ -f .env.example ] || die ".env.example がありません"
  key="$(openssl rand -hex 32 2>/dev/null)" || key="$(head -c32 /dev/urandom | od -An -tx1 | tr -d ' \n')"
  [ -n "$key" ] || die "暗号化キーを生成できませんでした"
  sed "s|^OPEN_NOTEBOOK_ENCRYPTION_KEY=.*|OPEN_NOTEBOOK_ENCRYPTION_KEY=${key}|" .env.example > .env || die ".env を作成できません"
  ok ".env を作成し、暗号化キーを自動生成しました"
  warn "別の PC にノートを持ち出す場合はこの鍵が必要です（$HERE/.env）"
fi

# --- 3. Docling の扱い ------------------------------------------------
if [ "$NO_DOCLING" -eq 1 ]; then
  if [ ! -f docker-compose.override.yml ]; then
    cat > docker-compose.override.yml <<'YAML'
# Docling を無効にする（setup-linux.sh --no-docling が生成）
# 有効に戻したいときは、このファイルを削除してください。
services:
  open_notebook:
    environment:
      - OPEN_NOTEBOOK_ENABLE_DOCLING=false
YAML
    ok "Docling を無効にしました（起動が速くなります）"
  fi
else
  say "  Docling（日本語 PDF の抽出精度向上）を有効にしたまま導入します。"
  say "  初回起動は数 GB のダウンロードで 5〜15 分かかります。"
  say "  不要なら Ctrl+C で中断し、--no-docling を付けて実行し直してください。"
fi

# --- 4. 起動 ----------------------------------------------------------
say
say "  コンテナを起動しています..."
docker compose up -d || die "起動に失敗しました。上のメッセージを確認してください。"
ok "コンテナを起動しました"

say
say "  Open Notebook の起動を待っています（初回は長くかかります）..."
started=1
for i in $(seq 1 240); do
  if curl -sf --max-time 3 http://localhost:5055/api/models >/dev/null 2>&1; then
    started=0; break
  fi
  [ $((i % 20)) -eq 0 ] && say "    ...まだ準備中です（$((i * 3)) 秒経過）"
  sleep 3
done

if [ "$started" -eq 0 ]; then
  ok "起動しました"
else
  warn "12 分待っても応答がありません。進行状況を確認してください:"
  warn "  docker compose logs -f open_notebook"
fi

# --- 5. アイコン ------------------------------------------------------
if [ "$ICONS" -eq 1 ]; then
  say
  if [ -x "$HERE/linux/install-icons.sh" ]; then
    "$HERE/linux/install-icons.sh"
  else
    warn "linux/install-icons.sh が見つかりません"
  fi
fi

# --- 6. 案内 ----------------------------------------------------------
say
say "==============================================="
say "  導入しました"
say ""
say "    Web UI : http://localhost:8502"
say "    API    : http://localhost:5055"
say ""
say "  次にやること:"
say "    1. ブラウザで開き、左サイドバーの言語を日本語に"
say "    2. 「モデル」ページで AI プロバイダの API キーを登録"
say "    3. 埋め込みモデルを必ず設定（日本語検索に必須）"
say ""
say "  詳しくは README.md を見てください。"
say "  停止: docker compose stop     状態確認: ./docs/diagnose.sh"
say "==============================================="
