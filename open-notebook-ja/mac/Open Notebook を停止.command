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
echo "  Open Notebook を停止します"
echo "==============================================="
echo

require_project
require_docker_installed

if ! docker info >/dev/null 2>&1; then
  ok "Docker が動いていないため、すでに停止しています"
  finish
  exit 0
fi

echo "  コンテナを停止しています..."
docker compose stop || die "停止に失敗しました。上のエラーメッセージを確認してください。"
ok "停止しました"

echo
echo "  ノートやソースはそのまま保存されています。"
echo "  次に使うときは「Open Notebook を起動」をダブルクリックしてください。"
finish
