#!/bin/bash
set -u

# デスクトップのエイリアス（シンボリックリンク）から起動されても、
# リポジトリ内にある本体の場所を突き止めます。
__src="${BASH_SOURCE[0]}"
while [ -L "$__src" ]; do
  __dir="$(cd -P "$(dirname "$__src")" && pwd)"
  __src="$(readlink "$__src")"
  case "$__src" in /*) ;; *) __src="$__dir/$__src" ;; esac
done
SCRIPT_DIR="$(cd -P "$(dirname "$__src")" && pwd)"

if [ ! -f "$SCRIPT_DIR/_common.sh" ]; then
  echo
  echo "  ✗ 必要なファイルが見つかりません（$SCRIPT_DIR/_common.sh）"
  echo
  echo "    このアイコンは「コピー」ではなく「エイリアス」である必要があります。"
  echo "    デスクトップのこのファイルを削除し、リポジトリの mac フォルダにある"
  echo "    「デスクトップにアイコンを作る.command」をダブルクリックしてください。"
  echo
  printf "Enter キーを押すと閉じます。"
  read -r _
  exit 1
fi
. "$SCRIPT_DIR/_common.sh"

echo "==============================================="
echo "  Open Notebook を起動します"
echo "==============================================="
echo

require_project
require_docker_installed
require_docker_running
ensure_env_file

echo
echo "  コンテナを起動しています..."
docker compose up -d || die "起動に失敗しました。上のエラーメッセージを確認してください。"
ok "コンテナを起動しました"
echo

# 初回は日本語 PDF 用 Docling のダウンロードがあるため長めに待つ
if [ -d "$PROJECT_DIR/notebook_data" ]; then
  wait_for_ui 90
  started=$?
else
  echo "  初回起動は日本語 PDF 用の Docling をダウンロードするため、"
  echo "  10 分ほどかかることがあります。そのままお待ちください。"
  wait_for_ui 360
  started=$?
fi

if [ $started -eq 0 ]; then
  echo
  echo "  ブラウザで開きます: http://localhost:8502"
  open http://localhost:8502
else
  echo
  warn "まだ応答がありませんが、起動処理はバックグラウンドで続いています。"
  warn "しばらくしてから http://localhost:8502 を開いてみてください。"
  warn "状況を見るには、ターミナルで次を実行します:"
  warn "  cd '$PROJECT_DIR' && docker compose logs -f open_notebook"
fi

echo
echo "  使い終わったら「Open Notebook を停止」をダブルクリックしてください。"
finish
