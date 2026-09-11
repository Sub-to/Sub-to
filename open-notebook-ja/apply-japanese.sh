#!/usr/bin/env bash
# 既存の Open Notebook に、日本語設定だけを後付けします。
#
# 元の docker-compose.yml には一切触りません。
# docker-compose.override.yml を追加するだけなので、
# やめたくなったらそのファイルを消せば完全に元通りです。
#
# 使い方:
#   ./apply-japanese.sh                 # 導入先を自動で探す
#   ./apply-japanese.sh /path/to/dir    # 導入先を指定する
#   ./apply-japanese.sh --undo          # 元に戻す
set -uo pipefail

SRC="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OVERRIDE_NAME="docker-compose.override.yml"

say()  { printf '%s\n' "$*"; }
ok()   { printf '  ✓ %s\n' "$*"; }
warn() { printf '  ! %s\n' "$*"; }
die()  { printf '\n  ✗ %s\n' "$*"; exit 1; }

# --- 導入先を決める ---------------------------------------------------
UNDO=0
TARGET=""
for a in "$@"; do
  case "$a" in
    --undo) UNDO=1 ;;
    -*) die "不明なオプション: $a" ;;
    *) TARGET="$a" ;;
  esac
done

if [ -z "$TARGET" ]; then
  say "稼働中の Open Notebook を探しています..."
  # docker compose ls の CONFIG FILES 列から、open_notebook を含むものを拾う
  TARGET=$(docker compose ls --format json 2>/dev/null | python3 -c "
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
" 2>/dev/null)
fi

[ -n "$TARGET" ] || die "導入先が見つかりませんでした。
    Open Notebook が起動しているか確認するか、パスを直接指定してください:
      $0 /Users/あなた/場所/open-notebook"

[ -d "$TARGET" ] || die "そのディレクトリがありません: $TARGET"
[ -f "$TARGET/docker-compose.yml" ] || die "docker-compose.yml が見つかりません: $TARGET"

say "導入先: $TARGET"
say

# --- 元に戻す ---------------------------------------------------------
if [ "$UNDO" -eq 1 ]; then
  say "日本語設定を取り外します..."
  [ -f "$TARGET/$OVERRIDE_NAME" ] && { rm "$TARGET/$OVERRIDE_NAME"; ok "$OVERRIDE_NAME を削除しました"; } || warn "$OVERRIDE_NAME はありません"
  [ -d "$TARGET/ja-prompts" ] && { rm -rf "$TARGET/ja-prompts"; ok "ja-prompts/ を削除しました"; } || warn "ja-prompts/ はありません"
  say
  say "次を実行すると元の状態で起動します:"
  say "  cd \"$TARGET\" && docker compose up -d"
  exit 0
fi

# --- 既存の override を保護 -------------------------------------------
if [ -f "$TARGET/$OVERRIDE_NAME" ]; then
  if grep -q "PROMPTS_PATH" "$TARGET/$OVERRIDE_NAME" 2>/dev/null; then
    warn "日本語設定はすでに適用されています。ja-prompts を更新して続行します。"
  else
    BK="$TARGET/$OVERRIDE_NAME.backup-$(date +%Y%m%d%H%M%S)"
    cp "$TARGET/$OVERRIDE_NAME" "$BK"
    warn "既存の $OVERRIDE_NAME がありました。$(basename "$BK") として退避します。"
    warn "内容が必要な場合は、手作業で統合してください。"
  fi
fi

# --- 日本語プロンプトを配置 -------------------------------------------
[ -d "$SRC/ja-prompts" ] || die "ja-prompts/ が見つかりません: $SRC"
rm -rf "$TARGET/ja-prompts"
cp -R "$SRC/ja-prompts" "$TARGET/ja-prompts" || die "ja-prompts のコピーに失敗しました"
ok "ja-prompts/ を配置しました（$(find "$TARGET/ja-prompts" -name '*.jinja' | wc -l | tr -d ' ') ファイル）"

# --- override を書く --------------------------------------------------
cat > "$TARGET/$OVERRIDE_NAME" <<'YAML'
# 日本語運用のための追加設定（open-notebook-ja が生成）
#
# 元の docker-compose.yml には手を加えていません。
# Docker Compose はこのファイルを自動で読み込んで設定を上書きします。
# 元に戻したいときは、このファイルと ja-prompts/ を削除してください。

services:
  open_notebook:
    environment:
      # AI の回答を日本語にするプロンプト上書き。
      # ai-prompter は PROMPTS_PATH を先に探し、無いテンプレートは
      # 本体の /app/prompts にフォールバックします。
      - PROMPTS_PATH=/app/ja-prompts

      # 日本語 PDF の抽出精度を上げる Docling を有効化。
      # 初回起動時に数 GB をダウンロードするため、最初だけ時間がかかります。
      # 不要ならこの行を削除してください。
      - OPEN_NOTEBOOK_ENABLE_DOCLING=true
    volumes:
      - ./ja-prompts:/app/ja-prompts:ro
YAML
ok "$OVERRIDE_NAME を作成しました"

# --- 検証 -------------------------------------------------------------
say
say "設定を検証しています..."
if (cd "$TARGET" && docker compose config >/dev/null 2>&1); then
  ok "docker compose の設定は正常です"
else
  warn "docker compose config が通りませんでした。詳細:"
  (cd "$TARGET" && docker compose config 2>&1 | tail -5 | sed 's/^/    /')
  die "適用を中止します。$OVERRIDE_NAME を削除して元に戻してください。"
fi

say
say "==============================================="
say "  適用しました。次を実行して反映してください:"
say ""
say "    cd \"$TARGET\""
say "    docker compose up -d"
say ""
say "  ノートもソースも API キーもそのまま残ります。"
say "  元に戻すには: $0 --undo"
say "==============================================="
