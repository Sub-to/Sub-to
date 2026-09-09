#!/usr/bin/env bash
# 日本語の全文検索（BM25）が Open Notebook でどう振る舞うかを再現検証するスクリプト。
#
# Open Notebook のマイグレーション 1 が定義しているアナライザをそのまま使い、
# 日本語のキーワード検索がヒットしないことを確認します。
#
# 必要なもの: SurrealDB v2 のバイナリ（surreal）、curl、python3
# 使い方:  ./verify-japanese-search.sh
set -euo pipefail

PORT="${PORT:-8010}"
NS=test
DB=test

command -v surreal >/dev/null || { echo "surreal コマンドが見つかりません。https://surrealdb.com/install を参照してください"; exit 1; }

echo "▶ SurrealDB をメモリモードで起動 (127.0.0.1:${PORT})"
surreal start --user root --pass root --bind "127.0.0.1:${PORT}" memory >/tmp/surreal-verify.log 2>&1 &
SURREAL_PID=$!
trap 'kill "$SURREAL_PID" 2>/dev/null || true' EXIT

for _ in $(seq 1 15); do
  sleep 1
  curl -sf --max-time 2 "http://127.0.0.1:${PORT}/health" >/dev/null 2>&1 && break
done

q() {
  curl -s --max-time 30 -u root:root \
    -H "Accept: application/json" -H "surreal-ns: ${NS}" -H "surreal-db: ${DB}" \
    -H "Content-Type: text/plain" --data-binary "$1" "http://127.0.0.1:${PORT}/sql"
}
ids() { python3 -c "import json,sys;r=json.load(sys.stdin)[0]['result'];print([x.get('id') for x in r] if r else '(ヒットなし)')"; }

# Open Notebook の open_notebook/database/migrations/1.surrealql と同一の定義
q "DEFINE ANALYZER my_analyzer TOKENIZERS blank,class,camel,punct FILTERS snowball(english), lowercase;
   DEFINE TABLE doc SCHEMALESS;
   DEFINE INDEX idx_doc ON TABLE doc COLUMNS content SEARCH ANALYZER my_analyzer BM25 HIGHLIGHTS;
   CREATE doc:1 SET content = '機械学習は人工知能の一分野です。ディープラーニングも含まれます。';
   CREATE doc:2 SET content = 'Machine learning is a subfield of artificial intelligence.';" >/dev/null

echo
echo "▶ 日本語文がどうトークン分割されるか"
q "RETURN search::analyze('my_analyzer', '機械学習は人工知能の一分野です。ディープラーニングも含まれます。');" \
  | python3 -c "import json,sys;print(' ',json.load(sys.stdin)[0]['result'])"

echo
echo "▶ 検索結果"
printf "  日本語キーワード '人工知能'          -> "; q "SELECT id FROM doc WHERE content @1@ '人工知能';" | ids
printf "  日本語キーワード '機械学習'          -> "; q "SELECT id FROM doc WHERE content @1@ '機械学習';" | ids
printf "  文節まるごと '機械学習は人工知能の一分野です' -> "; q "SELECT id FROM doc WHERE content @1@ '機械学習は人工知能の一分野です';" | ids
printf "  英語キーワード 'artificial'（対照）  -> "; q "SELECT id FROM doc WHERE content @1@ 'artificial';" | ids

echo
echo "結論: 日本語は句読点や英数字の境界でしか分割されないため、"
echo "      文節と完全一致しない限りテキスト検索はヒットしません。"
echo "      日本語ではベクトル検索を使ってください（README.md 参照）。"
