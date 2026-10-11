#!/bin/bash
# Launch REA's stdio MCP server with the engines installed by session-start.sh.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TOOLS=/opt/tools

[ -x "$TOOLS/ghidra_12.1.4_PUBLIC/support/analyzeHeadless" ] &&
  export GHIDRA_INSTALL_DIR="$TOOLS/ghidra_12.1.4_PUBLIC"
if command -v javac >/dev/null; then
  export JAVA_HOME="$(dirname "$(dirname "$(readlink -f "$(command -v javac)")")")"
fi
[ -f "$TOOLS/jadx-headless-mcp-0.7.1-all.dedup.jar" ] &&
  export REA_JADX_MCP_JAR="$TOOLS/jadx-headless-mcp-0.7.1-all.dedup.jar"
[ -x "$TOOLS/pwntools-venv/bin/python" ] &&
  export REA_PWNTOOLS_PYTHON="$TOOLS/pwntools-venv/bin/python"
[ -x /opt/pw-browsers/chromium ] &&
  export REA_BROWSER_EXECUTABLE="$(readlink -f /opt/pw-browsers/chromium)"

# The first session can connect before the setup hook finishes building.
for _ in $(seq 1 20); do
  [ -f "$ROOT/rea/dist/main.js" ] && break
  sleep 1
done

exec node "$ROOT/rea/scripts/rea.mjs" mcp
