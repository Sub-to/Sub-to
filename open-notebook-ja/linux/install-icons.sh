#!/usr/bin/env bash
# デスクトップとアプリ一覧に Open Notebook のアイコンを登録します。
#   ./install-icons.sh           登録する
#   ./install-icons.sh --remove  取り消す
set -uo pipefail

HERE="$(cd -P "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
RUNNER="$HERE/on.sh"
APPS="$HOME/.local/share/applications"
DESKTOP="$(xdg-user-dir DESKTOP 2>/dev/null || echo "$HOME/Desktop")"

ok()   { printf '  ✓ %s\n' "$*"; }
warn() { printf '  ! %s\n' "$*"; }

ids="open-notebook-start open-notebook-stop open-notebook-update open-notebook-diagnose"

if [ "${1:-}" = "--remove" ]; then
  for id in $ids; do
    rm -f "$APPS/$id.desktop" "$DESKTOP/$id.desktop"
  done
  command -v update-desktop-database >/dev/null && update-desktop-database "$APPS" 2>/dev/null
  ok "アイコンを削除しました"
  exit 0
fi

[ -x "$RUNNER" ] || { warn "on.sh が実行できません: $RUNNER"; exit 1; }
mkdir -p "$APPS" "$DESKTOP"

make_entry() {  # $1=id $2=表示名 $3=コマンド $4=アイコン $5=説明
  cat > "$APPS/$1.desktop" <<EOF
[Desktop Entry]
Type=Application
Version=1.0
Name=$2
Comment=$5
Exec=$RUNNER $3
Icon=$4
Terminal=true
Categories=Utility;Development;
StartupNotify=true
EOF
  chmod +x "$APPS/$1.desktop"
  cp "$APPS/$1.desktop" "$DESKTOP/$1.desktop"
  chmod +x "$DESKTOP/$1.desktop"
  # GNOME はデスクトップ上のランチャーに「信頼」の印が必要
  gio set "$DESKTOP/$1.desktop" metadata::trusted true 2>/dev/null
  ok "$2"
}

make_entry open-notebook-start    "Open Notebook を起動"   start    system-run          "Open Notebook を起動してブラウザで開きます"
make_entry open-notebook-stop     "Open Notebook を停止"   stop     process-stop        "Open Notebook を停止します（ノートは残ります）"
make_entry open-notebook-update   "Open Notebook を更新"   update   system-software-update "最新版に更新します"
make_entry open-notebook-diagnose "Open Notebook の診断"   diagnose dialog-information   "稼働状況を調べてレポートを表示します"

command -v update-desktop-database >/dev/null && update-desktop-database "$APPS" 2>/dev/null

echo
echo "  デスクトップとアプリ一覧に追加しました。"
echo "  デスクトップのアイコンは、初回だけ右クリック →「起動を許可する」が"
echo "  必要な場合があります（GNOME の仕様）。"
echo "  取り消すには: $0 --remove"
