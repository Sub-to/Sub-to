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
echo "  Open Notebook を最新版に更新します"
echo "==============================================="
echo
echo "  ノートやソース、登録済みの API キーはそのまま残ります。"
echo

require_project
require_docker_installed
require_docker_running
ensure_env_file

echo
echo "  最新のイメージを取得しています（数分かかることがあります）..."
docker compose pull || die "イメージの取得に失敗しました。ネットワーク接続を確認してください。"
ok "取得しました"

echo
echo "  新しいイメージでコンテナを入れ替えています..."
docker compose up -d || die "起動に失敗しました。上のエラーメッセージを確認してください。"
ok "入れ替えました"

echo
if wait_for_ui 120; then
  echo
  echo "  ブラウザで開きます: http://localhost:8502"
  open http://localhost:8502
else
  echo
  warn "まだ応答がありませんが、起動処理は続いています。"
  warn "しばらくしてから http://localhost:8502 を開いてみてください。"
fi

echo
echo "  使わなくなった古いイメージを消してディスクを空けるには、"
echo "  ターミナルで次を実行します: docker image prune"
finish
