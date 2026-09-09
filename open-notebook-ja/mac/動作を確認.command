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
  echo
  printf "Enter キーを押すと閉じます。"
  read -r _
  exit 1
fi
. "$SCRIPT_DIR/_common.sh"

require_project

DESKTOP="$HOME/Desktop"
[ -d "$DESKTOP" ] || DESKTOP="$HOME"
REPORT="$DESKTOP/open-notebook-診断.txt"

bash "$PROJECT_DIR/docs/diagnose.sh" 2>&1 | tee "$REPORT"

echo
echo "  この内容を $REPORT にも保存しました。"
echo "  ファイルを開いて全文をコピーできます。"
open -R "$REPORT" 2>/dev/null
finish
