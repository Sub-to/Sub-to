#!/usr/bin/env bash
# Open Notebook の起動・停止・更新・診断。.desktop から呼ばれます。
set -uo pipefail
PROJECT_DIR="$(cd -P "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)"
cd "$PROJECT_DIR" || { echo "プロジェクトが見つかりません"; read -r -p "Enter で閉じます"; exit 1; }

pause() { echo; read -r -p "Enter キーで閉じます "; }
open_ui() { command -v xdg-open >/dev/null && xdg-open http://localhost:8502 >/dev/null 2>&1 & }

wait_ui() {
  echo "  起動を待っています..."
  for i in $(seq 1 "${1:-100}"); do
    curl -sf --max-time 3 http://localhost:5055/api/models >/dev/null 2>&1 && { echo "  ✓ 起動しました"; return 0; }
    [ $((i % 20)) -eq 0 ] && echo "    ...まだ準備中です（$((i * 3)) 秒経過）"
    sleep 3
  done
  return 1
}

case "${1:-}" in
  start)
    echo "=== Open Notebook を起動します ==="
    docker info >/dev/null 2>&1 || { echo "  ✗ Docker が動いていません: sudo systemctl start docker"; pause; exit 1; }
    docker compose up -d || { echo "  ✗ 起動に失敗しました"; pause; exit 1; }
    if wait_ui 240; then open_ui; else
      echo "  ! まだ応答がありません。ログ: docker compose logs -f open_notebook"
    fi
    pause ;;
  stop)
    echo "=== Open Notebook を停止します ==="
    docker compose stop && echo "  ✓ 停止しました（ノートはそのまま残ります）"
    pause ;;
  update)
    echo "=== 最新版に更新します ==="
    docker compose pull && docker compose up -d && echo "  ✓ 更新しました"
    wait_ui 180 && open_ui
    pause ;;
  diagnose)
    echo "=== 診断 ==="
    bash "$PROJECT_DIR/docs/diagnose.sh"
    pause ;;
  *)
    echo "使い方: $0 {start|stop|update|diagnose}"; exit 2 ;;
esac
