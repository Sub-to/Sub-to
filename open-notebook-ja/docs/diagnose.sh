#!/usr/bin/env bash
# Open Notebook の稼働状態を調べて、そのまま貼り付けられる形で出力します。
# APIキーや暗号化キーは出力しません。
#
# 使い方:  ./docs/diagnose.sh
set -u

cd "$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)" || exit 1

API=http://localhost:5055
UI=http://localhost:8502
PW="${OPEN_NOTEBOOK_PASSWORD:-}"
[ -z "$PW" ] && [ -f .env ] && PW="$(grep -E '^OPEN_NOTEBOOK_PASSWORD=' .env 2>/dev/null | cut -d= -f2-)"
AUTH=(); [ -n "$PW" ] && AUTH=(-H "Authorization: Bearer $PW")

hr() { printf '\n--- %s ---\n' "$1"; }
api() { curl -s --max-time 10 "${AUTH[@]}" "$API$1" 2>/dev/null; }
jq_or_raw() { python3 -c "
import json,sys
raw=sys.stdin.read().strip()
if not raw: print('  (応答なし)'); sys.exit()
try: d=json.loads(raw)
except Exception: print('  '+raw[:400]); sys.exit()
print(json.dumps(d, ensure_ascii=False, indent=2)[:$1])
" 2>/dev/null || echo "  (解析できませんでした)"; }

echo "==============================================="
echo "  Open Notebook 診断レポート"
echo "  $(date '+%Y-%m-%d %H:%M:%S')"
echo "==============================================="

if ! command -v docker >/dev/null 2>&1; then
  echo
  echo "  ✗ docker コマンドが見つかりません。"
  echo "    Docker Desktop が起動しているか確認してください。"
  echo "    （このスクリプトはコンテナの情報を取得できないため、以降は限定的な結果になります）"
fi

hr "1. コンテナの状態"
docker compose ps 2>&1 | head -10

hr "2. 使用中のイメージ"
docker compose images 2>&1 | head -6

hr "3. Web UI / API の応答"
show_http() {  # $1=ラベル $2=URL
  local code
  code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "${AUTH[@]}" "$2" 2>/dev/null)
  case "$code" in
    200) echo "  $1: 正常 (200)" ;;
    000|"") echo "  $1: 応答なし（まだ起動中か、停止しています）" ;;
    401|403) echo "  $1: 認証が必要 ($code) — パスワードを設定していますか？" ;;
    *) echo "  $1: HTTP $code" ;;
  esac
}
show_http "Web UI (8502)" "$UI"
show_http "REST API (5055)" "$API/api/models"

hr "4. 日本語プロンプト上書きが効いているか【重要】"
env_val=$(docker compose exec -T open_notebook printenv PROMPTS_PATH 2>/dev/null | tr -d '\r')
echo "  PROMPTS_PATH = ${env_val:-（未設定）}"
echo "  マウントされているファイル:"
docker compose exec -T open_notebook ls -1 /app/ja-prompts/chat /app/ja-prompts/ask /app/ja-prompts/source_chat 2>&1 | sed 's/^/    /' | head -12
echo "  中身の先頭（日本語の指示が入っていれば成功）:"
docker compose exec -T open_notebook head -1 /app/ja-prompts/chat/system.jinja 2>&1 | sed 's/^/    /'
echo "  ai-prompter が実際にどのファイルを選ぶか:"
docker compose exec -T open_notebook uv run --no-sync python -c "
from ai_prompter import Prompter
p = Prompter(prompt_template='chat/system')
print('    探索順:', p.prompt_folders[:2])
out = p.render(data={})
print('    採用されたのは日本語版か:', '出力言語（最優先ルール）' in out)
" 2>&1 | tail -4

hr "5. 拡張エンジンの導入状況（日本語PDF用の Docling など）"
api /api/capabilities | jq_or_raw 800

hr "6. 登録済みモデル（名前のみ。APIキーは出力されません）"
api /api/models | python3 -c "
import json,sys
raw=sys.stdin.read().strip()
if not raw: print('  (応答なし。API が起動していないか、パスワード保護されています)'); sys.exit()
try: d=json.loads(raw)
except Exception: print('  '+raw[:300]); sys.exit()
items = d if isinstance(d,list) else d.get('models',d.get('items',[]))
if not items: print('  (モデルが1つも登録されていません → 「モデル」ページで登録してください)'); sys.exit()
for m in items:
    if isinstance(m,dict):
        print(f\"  [{m.get('type','?')}] {m.get('provider','?')} / {m.get('name','?')}  (id: {m.get('id','?')})\")
" 2>&1 | head -20

hr "7. 既定モデルの割り当て（上のidと照合してください）"
api /api/models/defaults | jq_or_raw 600

hr "8. 設定（埋め込み・YouTube字幕言語）"
api /api/settings | jq_or_raw 700

hr "9. 直近のエラーログ"
errs=$(docker compose logs --tail=200 open_notebook 2>&1 | grep -iE "error|exception|traceback|failed" | tail -8)
if [ -n "$errs" ]; then echo "$errs" | sed 's/^/  /'; else echo "  (エラーなし)"; fi

hr "10. ディスク使用量"
du -sh surreal_data notebook_data 2>/dev/null | sed 's/^/  /' || echo "  (まだデータがありません)"

echo
echo "==============================================="
echo "  ここまでをコピーして貼り付けてください"
echo "  （APIキー・暗号化キーは含まれていません）"
echo "==============================================="
