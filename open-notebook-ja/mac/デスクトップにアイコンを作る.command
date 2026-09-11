#!/bin/bash
set -u

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
echo "  デスクトップにアイコンを作ります"
echo "==============================================="
echo

require_project

DESKTOP="$HOME/Desktop"
[ -d "$DESKTOP" ] || DESKTOP="$HOME/デスクトップ"
[ -d "$DESKTOP" ] || die "デスクトップのフォルダが見つかりませんでした（$HOME/Desktop）"

echo "  作成先: $DESKTOP"
echo

created=0
for name in "Open Notebook を起動" "Open Notebook を停止" "Open Notebook を更新"; do
  target="$SCRIPT_DIR/${name}.command"
  link="$DESKTOP/${name}.command"

  [ -f "$target" ] || { warn "本体が見つかりません: ${name}.command"; continue; }
  chmod +x "$target" 2>/dev/null

  if [ -e "$link" ] || [ -L "$link" ]; then
    if [ -L "$link" ] && [ "$(readlink "$link")" = "$target" ]; then
      ok "${name} … すでに作成済み"
      created=$((created + 1))
      continue
    fi
    warn "${name} … 同名のファイルがすでにあります。上書きせず飛ばしました。"
    warn "  （$link を確認してください）"
    continue
  fi

  if ln -s "$target" "$link"; then
    ok "${name} … 作成しました"
    created=$((created + 1))
  else
    warn "${name} … 作成できませんでした"
  fi
done

echo
if [ "$created" -gt 0 ]; then
  echo "  デスクトップの「Open Notebook を起動」をダブルクリックすると始まります。"
  echo
  echo "  ※ 初回だけ「開発元が未確認のため開けません」と出ることがあります。"
  echo "     その場合はアイコンを右クリック →「開く」→「開く」を選んでください。"
  echo "     2 回目以降はダブルクリックで開きます。"
  echo
  echo "  ※ アイコンの絵柄を変えたい場合は、アイコンを選んで ⌘I（情報を見る）を開き、"
  echo "     左上の小さなアイコンに好きな画像を貼り付けてください。"
else
  warn "アイコンを 1 つも作成できませんでした。"
fi
finish
