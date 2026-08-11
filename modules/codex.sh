#!/bin/sh
set -eu

log() { printf '\n\033[1;32m== %s ==\033[0m\n' "$*"; }
warn() { printf '\n\033[1;33m!! %s\033[0m\n' "$*"; }

CODEX_BIN="/usr/local/bin/codex"
PROXY_BIN="/usr/local/bin/openai-api-server-via-codex"
UV_BIN="/usr/local/bin/uv"
UVX_BIN="/usr/local/bin/uvx"

if ! command -v codex >/dev/null 2>&1; then
  log "Codex CLI"
  curl -fsSL https://chatgpt.com/codex/install.sh | bash
  if [ -x /root/.local/bin/codex ]; then
    ln -sf /root/.local/bin/codex "$CODEX_BIN"
  fi
fi

if ! command -v codex >/dev/null 2>&1; then
  warn "Codex CLI was not installed. Authenticate manually after checking the supported architecture."
  exit 1
fi

printf 'codex: %s\n' "$(codex --version 2>/dev/null || echo installed)"

if ! command -v uv >/dev/null 2>&1; then
  log "uv"
  curl -LsSf https://astral.sh/uv/install.sh | sh
  if [ -x /root/.local/bin/uv ]; then
    ln -sf /root/.local/bin/uv "$UV_BIN"
  fi
  if [ -x /root/.local/bin/uvx ]; then
    ln -sf /root/.local/bin/uvx "$UVX_BIN"
  fi
fi

if ! command -v uvx >/dev/null 2>&1; then
  warn "uvx was not installed; cannot install the Codex proxy."
  exit 1
fi

log "Codex OpenAI-compatible proxy"
uv tool install --force openai-api-server-via-codex
if [ -x /root/.local/bin/openai-api-server-via-codex ]; then
  ln -sf /root/.local/bin/openai-api-server-via-codex "$PROXY_BIN"
fi

if ! command -v openai-api-server-via-codex >/dev/null 2>&1; then
  warn "openai-api-server-via-codex was not installed."
  exit 1
fi

printf 'openai-api-server-via-codex: %s\n' "$(openai-api-server-via-codex --version 2>/dev/null || echo installed)"
