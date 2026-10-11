#!/bin/bash
# Start a headless Chromium that routes through the sandbox proxy and expose it
# over CDP. REA's "launch" mode has no proxy option, so public sites need
# {"browser": {"mode": "connect", "cdp_endpoint": ..., "target_id": ...}}.
# Usage: .claude/rea-browser.sh [port]   (prints the endpoint and page target id)
set -euo pipefail
PORT="${1:-9333}"
CHROME="${REA_BROWSER_EXECUTABLE:-$(readlink -f /opt/pw-browsers/chromium)}"
PROFILE="${TMPDIR:-/tmp}/rea-chromium-$PORT"

if ! curl -fs "http://127.0.0.1:$PORT/json/version" >/dev/null; then
  proxy=()
  [ -n "${HTTPS_PROXY:-}" ] && proxy=(--proxy-server="$HTTPS_PROXY")
  nohup "$CHROME" --headless=new --no-sandbox --no-first-run \
    --remote-debugging-port="$PORT" --user-data-dir="$PROFILE" \
    "${proxy[@]}" about:blank >"$PROFILE.log" 2>&1 &
  for _ in $(seq 1 30); do
    curl -fs "http://127.0.0.1:$PORT/json/version" >/dev/null && break
    sleep 0.5
  done
fi

echo "cdp_endpoint=http://127.0.0.1:$PORT"
curl -fs "http://127.0.0.1:$PORT/json/list" | python3 -c \
  'import json,sys; [print("target_id=" + t["id"]) for t in json.load(sys.stdin) if t["type"] == "page"][:1]'
