#!/bin/bash
# Prepare REA for Claude Code cloud sessions: dependencies, build, and the
# bring-your-own engines that work on a Linux x64 sandbox.
set -euo pipefail

if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

ROOT="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"
REA="$ROOT/rea"
TOOLS=/opt/tools
mkdir -p "$TOOLS"

log() { echo "[rea-setup] $*" >&2; }

fetch_verified() { # url sha256 dest
  local url="$1" sha="$2" dest="$3" tmp
  if [ -f "$dest" ] && echo "$sha  $dest" | sha256sum -c --status; then return 0; fi
  tmp="$(mktemp "$dest.XXXXXX")"
  curl -fsSL --retry 4 --retry-delay 2 -o "$tmp" "$url"
  if ! echo "$sha  $tmp" | sha256sum -c --status; then
    rm -f "$tmp"; log "SHA-256 mismatch for $url"; return 1
  fi
  mv "$tmp" "$dest"
}

# 1. Node dependencies and build (turbo caches the build between runs).
# npm ci never rewrites the lockfile; the sandbox npm can differ from the
# repository's pinned npm and would otherwise drop fields from it.
if [ ! -f "$REA/node_modules/.package-lock.json" ] ||
  [ "$REA/package-lock.json" -nt "$REA/node_modules/.package-lock.json" ]; then
  log "installing npm dependencies"
  (cd "$REA" && npm ci --no-audit --no-fund --loglevel=error)
fi
log "building REA runtime and skill"
(cd "$REA" && npm run build:cached --silent >/dev/null)

# 2. Ghidra 12.1.4 (native decompiler). Hash recorded from the official release.
GHIDRA_DIR="$TOOLS/ghidra_12.1.4_PUBLIC"
if [ ! -x "$GHIDRA_DIR/support/analyzeHeadless" ]; then
  log "installing Ghidra 12.1.4"
  fetch_verified \
    "https://github.com/NationalSecurityAgency/ghidra/releases/download/Ghidra_12.1.4_build/ghidra_12.1.4_PUBLIC_20260921.zip" \
    ddac49f903da9d5bac833e5cc79395098b9c33cfd3279be5f31bd00387d2d4db \
    "$TOOLS/ghidra.zip"
  unzip -q -o "$TOOLS/ghidra.zip" -d "$TOOLS"
  rm -f "$TOOLS/ghidra.zip"
fi

# 3. Headless JADX for Android APKs. Hash matches rea/src/android/JadxRelease.ts.
JADX_JAR="$TOOLS/jadx-headless-mcp-0.7.1-all.jar"
fetch_verified \
  "https://github.com/1013503897/jadx-headless-mcp/releases/download/v0.7.1/jadx-headless-mcp-0.7.1-all.jar" \
  6e5eacf500b64292bfb73c49797c1958f6ee44646e43e868039ae7feb573ff75 \
  "$JADX_JAR"
# The upstream fat JAR repeats LICENSE entries, which REA's strict archive
# reader rejects ("Artifact path collision"). Keep the first copy of each entry;
# class files are unchanged. Evidence then reports source_revision null.
JADX_DEDUP="$TOOLS/jadx-headless-mcp-0.7.1-all.dedup.jar"
if [ ! -f "$JADX_DEDUP" ] || [ "$JADX_JAR" -nt "$JADX_DEDUP" ]; then
  python3 -W ignore - "$JADX_JAR" "$JADX_DEDUP" <<'PY'
import os, sys, zipfile
src, dst = sys.argv[1], sys.argv[2]
seen = set()
with zipfile.ZipFile(src) as zin, zipfile.ZipFile(dst + ".tmp", "w", zipfile.ZIP_DEFLATED) as zout:
    for info in zin.infolist():
        if info.filename not in seen:
            seen.add(info.filename)
            zout.writestr(info, zin.read(info))
os.replace(dst + ".tmp", dst)
PY
fi

# 4. Isolated pwntools for ELF layout and recorded-crash analysis.
PWN_VENV="$TOOLS/pwntools-venv"
if [ ! -x "$PWN_VENV/bin/python" ] || ! "$PWN_VENV/bin/python" -c "import pwn" 2>/dev/null; then
  log "installing pwntools 4.15.0"
  python3 -m venv "$PWN_VENV"
  "$PWN_VENV/bin/pip" install --quiet --disable-pip-version-check \
    pwntools==4.15.0 pyelftools==0.33 unicorn==2.1.2
fi

# 5. Session environment for the CLI. .claude/rea-mcp.sh sets the same values.
JAVA_HOME_DIR="$(dirname "$(dirname "$(readlink -f "$(command -v javac)")")")"
if [ -n "${CLAUDE_ENV_FILE:-}" ]; then
  {
    echo "export GHIDRA_INSTALL_DIR=$GHIDRA_DIR"
    echo "export JAVA_HOME=$JAVA_HOME_DIR"
    echo "export REA_JADX_MCP_JAR=$JADX_DEDUP"
    echo "export REA_PWNTOOLS_PYTHON=$PWN_VENV/bin/python"
    [ -x /opt/pw-browsers/chromium ] && echo "export REA_BROWSER_EXECUTABLE=$(readlink -f /opt/pw-browsers/chromium)"
    echo "alias rea='node $REA/scripts/rea.mjs'"
  } >> "$CLAUDE_ENV_FILE"
fi

log "ready"
