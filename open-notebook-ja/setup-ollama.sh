#!/usr/bin/env bash
# Ollama（ホスト側・GPU利用）を Open Notebook に登録します。
#
#   ./setup-ollama.sh                          既定のモデルで設定する
#   ./setup-ollama.sh --llm qwen2.5:14b --embed bge-m3
#   ./setup-ollama.sh --no-pull                すでに取得済みのモデルを登録するだけ
#
# 言語モデルと埋め込みモデルの取得・登録・接続テスト・既定設定までを行います。
set -uo pipefail

LLM="qwen2.5:14b"
EMBED="bge-m3"
PULL=1
OLLAMA_HOST_URL="${OLLAMA_HOST_URL:-http://localhost:11434}"
# コンテナから見たホスト側 Ollama の URL（compose の extra_hosts で解決される）
CONTAINER_URL="${CONTAINER_URL:-http://host.docker.internal:11434}"
API="${API:-http://localhost:5055}"

ok()   { printf '  ✓ %s\n' "$*"; }
warn() { printf '  ! %s\n' "$*"; }
die()  { printf '\n  ✗ %s\n' "$*"; exit 1; }

while [ $# -gt 0 ]; do
  case "$1" in
    --llm)   LLM="${2:?--llm にモデル名が必要です}"; shift 2 ;;
    --embed) EMBED="${2:?--embed にモデル名が必要です}"; shift 2 ;;
    --no-pull) PULL=0; shift ;;
    *) die "不明なオプション: $1" ;;
  esac
done

echo "==============================================="
echo "  Ollama を Open Notebook に登録します"
echo "==============================================="
echo "  言語モデル  : $LLM"
echo "  埋め込み    : $EMBED"
echo

# --- 1. Ollama の確認 -------------------------------------------------
command -v ollama >/dev/null 2>&1 || die "ollama が見つかりません。先に導入してください:
    curl -fsSL https://ollama.com/install.sh | sh"

curl -sf --max-time 5 "$OLLAMA_HOST_URL/api/tags" >/dev/null 2>&1 \
  || die "Ollama が応答しません（$OLLAMA_HOST_URL）。
    サービスを起動してください:  sudo systemctl enable --now ollama
    （手動なら別ターミナルで: ollama serve）"
ok "Ollama は動いています"

# --- 2. GPU の確認 ----------------------------------------------------
if command -v nvidia-smi >/dev/null 2>&1; then
  nvidia-smi --query-gpu=name,memory.total --format=csv,noheader 2>/dev/null \
    | sed 's/^/    GPU: /' || warn "nvidia-smi が実行できませんでした"
else
  warn "nvidia-smi が見つかりません。CPU で動作します（かなり遅くなります）"
fi

# --- 3. モデルの取得 --------------------------------------------------
if [ "$PULL" -eq 1 ]; then
  for m in "$LLM" "$EMBED"; do
    echo
    echo "  $m を取得しています（初回は時間がかかります）..."
    ollama pull "$m" || die "$m の取得に失敗しました。
    モデル名が正しいか https://ollama.com/library で確認してください。"
    ok "$m を取得しました"
  done
fi

echo
echo "  Ollama が持っているモデル:"
ollama list 2>/dev/null | tail -n +2 | awk '{print "    " $1}'

# --- 4. Open Notebook への登録 ---------------------------------------
echo
curl -sf --max-time 10 "$API/api/models" >/dev/null 2>&1 \
  || die "Open Notebook の API が応答しません（$API）。
    先に ./setup-linux.sh で起動してください。"

# --- 事前確認: コンテナから Ollama に届くか ---------------------------
# Linux では Ollama が既定で 127.0.0.1 のみを待ち受けるため、
# ここを確認せずに登録すると接続テストで初めて失敗が分かる。
CN="$(docker ps --format '{{.Names}}' 2>/dev/null | grep -i 'open.\?notebook' | grep -vi surreal | head -1)"
if [ -n "$CN" ]; then
  code="$(docker exec "$CN" curl -s -o /dev/null -w '%{http_code}' --max-time 5 \
          "$CONTAINER_URL/api/tags" 2>/dev/null)"
  if [ "$code" != "200" ]; then
    listen="$(ss -tlnp 2>/dev/null | grep 11434 | head -1)"
    extra=""
    case "$listen" in
      *127.0.0.1*) extra="
    Ollama が 127.0.0.1 だけを待ち受けています（$listen）。
    コンテナからは別アドレス（172.17.0.1 など）で来るため受け付けられません。" ;;
    esac
    die "Open Notebook のコンテナから Ollama に届きません。
    $CONTAINER_URL/api/tags → ${code:-到達できず}（200 が必要）
$extra
    全インターフェースで待ち受けるようにしてください:

      sudo mkdir -p /etc/systemd/system/ollama.service.d
      sudo tee /etc/systemd/system/ollama.service.d/override.conf > /dev/null <<'CONF'
      [Service]
      Environment=\"OLLAMA_HOST=0.0.0.0:11434\"
      CONF
      sudo systemctl daemon-reload && sudo systemctl restart ollama

    元の ollama.service は変更しません。戻すには override.conf を削除してください。
    そのあと、このスクリプトをもう一度実行してください。"
  fi
  ok "コンテナから Ollama に届いています"
else
  warn "Open Notebook のコンテナが見つかりません。接続確認を飛ばします。"
fi

LLM="$LLM" EMBED="$EMBED" CONTAINER_URL="$CONTAINER_URL" API="$API" python3 - <<'PY'
import json, os, urllib.request, urllib.error

API = os.environ["API"]
LLM, EMBED, URL = os.environ["LLM"], os.environ["EMBED"], os.environ["CONTAINER_URL"]

def call(path, method="GET", body=None, timeout=180):
    data = json.dumps(body).encode() if body is not None else (b"" if method == "POST" else None)
    req = urllib.request.Request(API + path, data=data, method=method)
    if body is not None: req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            t = r.read().decode()
            return json.loads(t) if t.strip() else {}
    except urllib.error.HTTPError as e:
        return {"__error__": f"HTTP {e.code}: {e.read().decode()[:200]}"}
    except Exception as e:
        return {"__error__": str(e)}

def lst(x): return x if isinstance(x, list) else []

# 資格情報（同じ base_url があれば再利用）
cred = next((c for c in lst(call("/api/credentials"))
             if c.get("provider") == "ollama" and (c.get("base_url") or "").rstrip("/") == URL.rstrip("/")), None)
if cred:
    print(f"  既存の Ollama 接続先を使います: {cred['id']}")
else:
    cred = call("/api/credentials", "POST", {
        "name": "Ollama (local GPU)", "provider": "ollama",
        "modalities": ["language", "embedding"], "base_url": URL,
    })
    if "__error__" in cred:
        raise SystemExit(f"  ✗ 接続先の登録に失敗: {cred['__error__']}")
    print(f"  ✓ 接続先を登録しました: {URL}")

existing = lst(call("/api/models"))
def ensure(name, mtype):
    hit = next((m for m in existing if m.get("name") == name and m.get("type") == mtype
                and m.get("credential") == cred["id"]), None)
    if hit:
        print(f"  登録済み: {name}")
        return hit
    r = call("/api/models", "POST", {"name": name, "provider": "ollama",
                                     "type": mtype, "credential": cred["id"]})
    if "__error__" in r:
        raise SystemExit(f"  ✗ {name} の登録に失敗: {r['__error__']}")
    print(f"  ✓ 登録しました: {name}  [{mtype}]")
    return r

m_llm = ensure(LLM, "language")
m_emb = ensure(EMBED, "embedding")

print()
print("  接続テスト（モデルの読み込みに時間がかかります）:")
allok = True
for m in (m_llm, m_emb):
    t = call(f"/api/models/{m['id']}/test", "POST")
    good = t.get("success")
    allok = allok and bool(good)
    print(f"    {'✓' if good else '✗'} {m['name']}: {str(t.get('message') or t.get('__error__'))[:150]}")

print()
d = call("/api/models/defaults", "PUT", {
    "default_chat_model": m_llm["id"],
    "default_transformation_model": m_llm["id"],
    "default_embedding_model": m_emb["id"],
})
print("  既定モデルの設定:", "失敗 " + str(d.get("__error__")) if "__error__" in d else "OK")

s = call("/api/settings", "PUT", {"default_embedding_option": "always"})
print("  新規ソースの自動ベクトル化:", "失敗 " + str(s.get("__error__")) if "__error__" in s else "OK")

print()
print("  すべて完了しました。" if allok else "  ! テストに失敗したモデルがあります。上のメッセージを確認してください。")
PY

echo
echo "==============================================="
echo "  http://localhost:8502 で使えます"
echo "  既存のノートをベクトル化するには、UI の"
echo "  設定 → Embeddingと検索 →「Embeddingを再構築」"
echo "==============================================="
