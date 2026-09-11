#!/usr/bin/env bash
# Open Notebook の稼働状態を調べて、そのまま貼り付けられる形で出力します。
# APIキーや暗号化キーは出力しません。
#
# 使い方:  ./docs/diagnose.sh
set -u

# 稼働中の Open Notebook を特定する。
# このスクリプトがどこに置かれていても、実際に動いているコンテナを調べます。
CN="$(docker ps --format '{{.Names}}' 2>/dev/null | grep -i 'open.\?notebook' | grep -vi surreal | head -1)"

# 導入先ディレクトリ（compose の設定ファイルの場所）
PROJECT_DIR="$(docker compose ls --format json 2>/dev/null | python3 -c "
import json,sys,os
try: rows=json.load(sys.stdin)
except Exception: sys.exit()
for r in rows:
    for f in str(r.get('ConfigFiles','')).split(','):
        f=f.strip()
        if not f: continue
        try:
            if 'open_notebook' in open(f, encoding='utf-8').read():
                print(os.path.dirname(f)); sys.exit()
        except OSError: pass
" 2>/dev/null)"
[ -n "$PROJECT_DIR" ] && cd "$PROJECT_DIR" 2>/dev/null

API=http://localhost:5055
UI=http://localhost:8502
PW="${OPEN_NOTEBOOK_PASSWORD:-}"
[ -z "$PW" ] && [ -f .env ] && PW="$(grep -E '^OPEN_NOTEBOOK_PASSWORD=' .env 2>/dev/null | cut -d= -f2-)"

# 認証ヘッダの付け外し。配列は使わない
# （macOS 標準の bash 3.2 では set -u と空配列の組み合わせがエラーになるため）
cget() {  # $1=URL, 残りは curl の追加引数
  local url="$1"; shift
  if [ -n "$PW" ]; then
    curl -s --max-time 10 -H "Authorization: Bearer $PW" "$@" "$url" 2>/dev/null
  else
    curl -s --max-time 10 "$@" "$url" 2>/dev/null
  fi
}

# コンテナ内でコマンドを実行する（compose プロジェクトに依存しない）
# 注意: docker exec に -T は存在しない（compose exec 専用のフラグ）
inc() {
  [ -n "$CN" ] || return 1
  docker exec "$CN" "$@" 2>/dev/null
}

hr() { printf '\n--- %s ---\n' "$1"; }
api() { cget "$API$1"; }
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
docker ps --format '  {{.Names}}  {{.Status}}' 2>&1 | grep -i -E 'open.?notebook|surreal' || echo "  起動しているコンテナが見つかりません"
echo "  → 調査対象: ${CN:-なし}"
echo "  → 導入先:   ${PROJECT_DIR:-不明}"

hr "2. 使用中のイメージ"
docker ps --format '  {{.Names}}  {{.Image}}' 2>&1 | grep -i -E 'open.?notebook|surreal' || echo "  (取得できません)"

hr "3. Web UI / API の応答"
show_http() {  # $1=ラベル $2=URL
  local code
  code=$(cget "$2" -o /dev/null -w '%{http_code}')
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
if ! inc true >/dev/null 2>&1; then
  echo "  ✗ コンテナ内でコマンドを実行できません（対象: ${CN:-なし}）"
  echo "    以降のコンテナ内チェックは結果が出ません。"
fi
env_val=$(inc printenv PROMPTS_PATH 2>/dev/null | tr -d '\r')
echo "  PROMPTS_PATH = ${env_val:-（未設定）}"
echo "  マウントされているファイル:"
inc ls -1 /app/ja-prompts/chat /app/ja-prompts/ask /app/ja-prompts/source_chat 2>&1 | sed 's/^/    /' | head -12
echo "  中身の先頭（日本語の指示が入っていれば成功）:"
inc head -1 /app/ja-prompts/chat/system.jinja 2>&1 | sed 's/^/    /'
echo "  ai-prompter が実際にどのファイルを選ぶか:"
inc uv run --no-sync python -c "
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
errs=$(docker logs --tail 200 "$CN" 2>&1 | grep -iE "error|exception|traceback|failed" | tail -8)
if [ -n "$errs" ]; then echo "$errs" | sed 's/^/  /'; else echo "  (エラーなし)"; fi

hr "10. ディスク使用量"
du -sh surreal_data notebook_data 2>/dev/null | sed 's/^/  /' || echo "  (まだデータがありません)"

echo
echo "==============================================="
echo "  ここまでをコピーして貼り付けてください"
echo "  （APIキー・暗号化キーは含まれていません）"
echo "==============================================="

# ======================================================================
#  AI プロバイダ接続の診断
#  「Could not connect to the AI provider」が出たときはここを見ます
# ======================================================================

hr "11. 登録済みプロバイダと接続先URL（APIキーは出力されません）"
api /api/credentials | python3 -c "
import json,sys
raw=sys.stdin.read().strip()
if not raw: print('  (応答なし)'); sys.exit()
try: d=json.loads(raw)
except Exception: print('  '+raw[:300]); sys.exit()
items = d if isinstance(d,list) else d.get('items',[])
if not items: print('  (プロバイダが1つも登録されていません)'); sys.exit()
warn=[]
for c in items:
    if not isinstance(c,dict): continue
    urls = [c.get(k) for k in ('base_url','endpoint','endpoint_llm','endpoint_embedding','endpoint_tts','endpoint_stt') if c.get(k)]
    u = ', '.join(urls) if urls else '(既定のURL)'
    print(f\"  {c.get('provider','?')}  [{','.join(c.get('modalities',[]))}]  → {u}\")
    for x in urls:
        if 'localhost' in x or '127.0.0.1' in x:
            warn.append((c.get('provider','?'), x))
if warn:
    print()
    print('  ★ 原因の可能性が高い設定が見つかりました:')
    for p,x in warn:
        print(f'     {p} の接続先が {x} になっています。')
    print('     Open Notebook は Docker コンテナの中で動いているため、そこでの')
    print('     localhost は「コンテナ自身」を指し、Mac 本体には届きません。')
    print('     localhost / 127.0.0.1 を host.docker.internal に書き換えてください。')
    print('     例: http://localhost:11434 → http://host.docker.internal:11434')
" 2>&1 | head -30

hr "12. コンテナの中からインターネットに出られるか"
for host in https://api.openai.com/v1/models https://api.anthropic.com/v1/models; do
  code=$(inc curl -s -o /dev/null -w '%{http_code}' --max-time 10 "$host" 2>/dev/null | tr -d '\r')
  case "$code" in
    401|403) echo "  $host → 到達OK (認証エラー $code は正常。ネットワークは通っています)" ;;
    200) echo "  $host → 到達OK (200)" ;;
    000|"") echo "  $host → ✗ 到達できません（コンテナから外に出られていません）" ;;
    *) echo "  $host → HTTP $code" ;;
  esac
done

hr "13. コンテナの中から Mac 本体（host.docker.internal）に届くか"
for port in 11434 1234 11435 8969; do
  case $port in
    11434) label="Ollama" ;; 1234) label="LM Studio" ;;
    11435) label="oMLX" ;; 8969) label="ローカルTTS" ;;
  esac
  code=$(inc curl -s -o /dev/null -w '%{http_code}' --max-time 5 "http://host.docker.internal:$port" 2>/dev/null | tr -d '\r')
  if [ "$code" = "000" ] || [ -z "$code" ]; then
    echo "  :$port ($label) → 応答なし（そのソフトを使っていなければ正常です）"
  else
    echo "  :$port ($label) → 応答あり (HTTP $code) ★この場合 host.docker.internal を使ってください"
  fi
done

hr "14. プロキシ設定（社内ネットワークなどで問題になります）"
for v in HTTP_PROXY HTTPS_PROXY NO_PROXY; do
  val=$(inc printenv "$v" 2>/dev/null | tr -d '\r')
  echo "  $v = ${val:-（未設定）}"
done

hr "15. 実際に起きたエラーの中身【最重要】"
echo "  分類できなかった例外の元メッセージがここに出ます:"
logs=$(docker logs --tail 400 "$CN" 2>&1 | grep -iE "unclassified llm error|connecterror|connection refused|nodename|name or service not known|ssl|certificate|proxy" | tail -10)
if [ -n "$logs" ]; then echo "$logs" | sed 's/^/    /'; else echo "    (該当するログが見つかりません。エラーを再現してから、もう一度実行してください)"; fi
