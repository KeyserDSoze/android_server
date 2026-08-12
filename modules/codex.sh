#!/bin/sh
set -eu

log() { printf '\n\033[1;32m== %s ==\033[0m\n' "$*"; }
warn() { printf '\n\033[1;33m!! %s\033[0m\n' "$*"; }

CODEX_BIN="/usr/local/bin/codex"
PROXY_BIN="/usr/local/bin/openai-api-server-via-codex"
UV_BIN="/usr/local/bin/uv"
UVX_BIN="/usr/local/bin/uvx"
export PATH="/root/.local/bin:/usr/local/bin:$PATH"

install_codex_cli() {
  _codex_arch="$(uname -m 2>/dev/null || echo unknown)"
  printf '[codex] Detected architecture: %s\n' "$_codex_arch"
  _codex_installer="$(mktemp /tmp/codex-install.XXXXXX.sh)"
  trap 'rm -f "$_codex_installer"' EXIT HUP INT TERM

  if ! curl -fL --retry 5 --retry-delay 5 --retry-all-errors \
      --connect-timeout 30 --max-time 120 \
      https://releases.openai.com/codex/install.sh -o "$_codex_installer"; then
    warn "Could not download the Codex installer from releases.openai.com."
    rm -f "$_codex_installer"
    return 1
  fi

  chmod 700 "$_codex_installer"
  _codex_attempt=1
  while [ "$_codex_attempt" -le 3 ]; do
    printf '[codex] Installation attempt %s/3 (asset timeout is 300 seconds)...\n' "$_codex_attempt"
    if [ "$_codex_attempt" -eq 1 ]; then
        if CODEX_NON_INTERACTIVE=true CODEX_INSTALLER_USE_RELEASES_OPENAI_COM=true \
          CODEX_INSTALL_DIR=/usr/local/bin \
          bash "$_codex_installer"; then
        rm -f "$_codex_installer"
        trap - EXIT HUP INT TERM
        return 0
      fi
      warn "OpenAI release download failed; the next attempt will use GitHub Releases."
    else
        if CODEX_NON_INTERACTIVE=true CODEX_INSTALLER_USE_RELEASES_OPENAI_COM=false \
          CODEX_INSTALL_DIR=/usr/local/bin \
          bash "$_codex_installer"; then
        rm -f "$_codex_installer"
        trap - EXIT HUP INT TERM
        return 0
      fi
      warn "Codex installation attempt $_codex_attempt failed."
    fi
    _codex_attempt=$((_codex_attempt + 1))
  done

  rm -f "$_codex_installer"
  trap - EXIT HUP INT TERM
  return 1
}

log "Codex CLI"
install_codex_cli || true
if [ -x /root/.local/bin/codex ] && [ ! -x "$CODEX_BIN" ]; then
  ln -sf /root/.local/bin/codex "$CODEX_BIN"
fi

if ! command -v codex >/dev/null 2>&1; then
  warn "Codex CLI was not installed. Authenticate manually after checking the supported architecture."
  _codex_cli_ok=0
else
  _codex_cli_ok=1
fi

if [ "${_codex_cli_ok:-0}" = "1" ]; then
  printf 'codex: %s\n' "$(codex --version 2>/dev/null || echo installed)"
fi

if ! command -v uv >/dev/null 2>&1; then
  log "uv"
  curl -LsSf https://astral.sh/uv/install.sh | sh
  if [ -x /root/.local/bin/uv ]; then
    ln -sf /root/.local/bin/uv "$UV_BIN"
  fi
  if [ -x /root/.local/bin/uvx ]; then
    ln -sf /root/.local/bin/uvx "$UVX_BIN"
  fi
  export PATH="/root/.local/bin:/usr/local/bin:$PATH"
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
if [ "${_codex_cli_ok:-0}" != "1" ]; then
  warn "Codex CLI is unavailable; the proxy is installed but requires a working Codex CLI and login before it can serve requests."
fi
