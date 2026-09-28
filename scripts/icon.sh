#!/bin/bash
# Regenerate the app icon from prototypes/app-icon.html.
#
# The prototype is the source of truth: its panel defaults ARE the icon's
# design, and `?png` makes it hand back the 1024 master as base64 with no
# click. The dark variant is the same drawing with the `DARK` override set
# applied (`#dark`), so both appearances stay in one file and can never
# drift apart. Anything tuned in the browser only ships once those defaults
# are updated in the file and this is re-run.
#
# Usage: scripts/icon.sh [palette]     e.g. scripts/icon.sh ember

set -euo pipefail
cd "$(dirname "$0")/.."

PALETTE="${1:-}"
PORT=8642
SET="Sky/Assets.xcassets/AppIcon.appiconset"
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
[[ -x "$CHROME" ]] || { echo "✗ Google Chrome not found at $CHROME" >&2; exit 1; }

# Serve prototypes/ if nothing is answering yet; stop it again on the way out.
SERVER_PID=""
if ! curl -fsS -o /dev/null "http://localhost:$PORT/app-icon.html" 2>/dev/null; then
  (cd prototypes && python3 -m http.server "$PORT" >/dev/null 2>&1) &
  SERVER_PID=$!
  trap '[[ -n "$SERVER_PID" ]] && kill "$SERVER_PID" 2>/dev/null' EXIT
  for _ in $(seq 20); do
    curl -fsS -o /dev/null "http://localhost:$PORT/app-icon.html" 2>/dev/null && break
    sleep 0.25
  done
fi

TMP=$(mktemp -d)
render() {              # render <out-file> <hash-flags…>
  local out="$1"; shift
  local hash=""
  for f in "$@"; do [[ -n "$f" ]] && hash="${hash:+$hash+}$f"; done
  local url="http://localhost:$PORT/app-icon.html?png=1${hash:+#$hash}"

  echo "▸ $(basename "$out")${hash:+  ($hash)}"
  "$CHROME" --headless --disable-gpu --virtual-time-budget=6000 --dump-dom "$url" \
    2>/dev/null > "$TMP/dom.html"

  # At this point the page body is nothing but the data URL.
  grep -o 'data:image/png;base64,[A-Za-z0-9+/=]*' "$TMP/dom.html" | head -1 |
    sed 's|data:image/png;base64,||' | base64 -d > "$TMP/out.png"

  local size
  size=$(python3 -c "import struct
d = open('$TMP/out.png','rb').read()
assert d[:8] == b'\x89PNG\r\n\x1a\n', 'not a png'
print('x'.join(map(str, struct.unpack('>II', d[16:24]))))")
  [[ "$size" == "1024x1024" ]] || { echo "✗ got $size, expected 1024x1024" >&2; exit 1; }
  mv "$TMP/out.png" "$out"
}

render "$SET/AppIcon.png"      "$PALETTE"
render "$SET/AppIcon-Dark.png" "$PALETTE" dark
rm -rf "$TMP"
echo "✓ $SET (light + dark)"
