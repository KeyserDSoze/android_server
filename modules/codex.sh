#!/bin/sh
set -eu

log() { printf '\n\033[1;32m== %s ==\033[0m\n' "$*"; }
warn() { printf '\n\033[1;33m!! %s\033[0m\n' "$*"; }

CODEX_BIN="/usr/local/bin/codex"
PROXY_BIN="/usr/local/bin/openai-api-server-via-codex"
UV_BIN="/usr/local/bin/uv"
UVX_BIN="/usr/local/bin/uvx"
CODEX_USER_HOME="${HOME:-/root}"
CODEX_LOCAL_BIN="$CODEX_USER_HOME/.local/bin"
CODEX_PROFILE="$CODEX_USER_HOME/.profile"
export PATH="$CODEX_LOCAL_BIN:/usr/local/bin:$PATH"

ensure_codex_path() {
  if ! grep -q 'aserv Codex PATH' "$CODEX_PROFILE" 2>/dev/null; then
    cat >> "$CODEX_PROFILE" <<PROFILE

# aserv Codex PATH
export PATH="/usr/local/bin:$CODEX_LOCAL_BIN:\$PATH"
PROFILE
  fi
  if [ -d /etc/profile.d ]; then
    cat > /etc/profile.d/aserv-codex.sh <<PROFILE
# aserv Codex PATH
export PATH="/usr/local/bin:$CODEX_LOCAL_BIN:\$PATH"
PROFILE
    chmod 0644 /etc/profile.d/aserv-codex.sh
  fi
}

codex_version_ok() {
  [ -x "$CODEX_BIN" ] && "$CODEX_BIN" --version >/dev/null 2>&1
}

install_codex_cli() {
  _codex_arch="$(uname -m 2>/dev/null || echo unknown)"
  printf '[codex] Detected architecture: %s\n' "$_codex_arch"
  case "$_codex_arch" in
    x86_64|amd64|aarch64|arm64) ;;
    *)
      warn "Codex CLI official binaries support Linux x64 and ARM64, not $_codex_arch."
      return 1
      ;;
  esac
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
          CODEX_INSTALL_DIR=/usr/local/bin HOME="$CODEX_USER_HOME" \
          bash "$_codex_installer"; then
        rm -f "$_codex_installer"
        trap - EXIT HUP INT TERM
        return 0
      fi
      warn "OpenAI release download failed; the next attempt will use GitHub Releases."
    else
        if CODEX_NON_INTERACTIVE=true CODEX_INSTALLER_USE_RELEASES_OPENAI_COM=false \
          CODEX_INSTALL_DIR=/usr/local/bin HOME="$CODEX_USER_HOME" \
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
if [ ! -x "$CODEX_BIN" ]; then
  for _codex_candidate in \
    "$CODEX_LOCAL_BIN/codex" \
    /root/.local/bin/codex \
    /home/*/.local/bin/codex; do
    if [ -x "$_codex_candidate" ]; then
      ln -sf "$_codex_candidate" "$CODEX_BIN"
      break
    fi
  done
fi
ensure_codex_path

if ! codex_version_ok; then
  warn "Codex CLI is not usable at $CODEX_BIN. Installation is incomplete; check: ls -l /usr/local/bin/codex /root/.local/bin/codex /home/*/.local/bin/codex"
  _codex_cli_ok=0
else
  _codex_cli_ok=1
fi

if [ "${_codex_cli_ok:-0}" = "1" ]; then
  printf 'codex: %s\n' "$($CODEX_BIN --version 2>/dev/null || echo installed)"
fi

if ! command -v uv >/dev/null 2>&1; then
  log "uv"
  curl -LsSf https://astral.sh/uv/install.sh | sh
  if [ -x "$CODEX_LOCAL_BIN/uv" ]; then
    ln -sf "$CODEX_LOCAL_BIN/uv" "$UV_BIN"
  fi
  if [ -x "$CODEX_LOCAL_BIN/uvx" ]; then
    ln -sf "$CODEX_LOCAL_BIN/uvx" "$UVX_BIN"
  fi
  export PATH="$CODEX_LOCAL_BIN:/usr/local/bin:$PATH"
fi

if ! command -v uvx >/dev/null 2>&1; then
  warn "uvx was not installed; cannot install the Codex proxy."
  exit 1
fi

log "Codex OpenAI-compatible proxy"
uv tool install --force openai-api-server-via-codex
if [ -x "$CODEX_LOCAL_BIN/openai-api-server-via-codex" ]; then
  ln -sf "$CODEX_LOCAL_BIN/openai-api-server-via-codex" "$PROXY_BIN"
fi

if ! command -v openai-api-server-via-codex >/dev/null 2>&1; then
  warn "openai-api-server-via-codex was not installed."
  exit 1
fi

printf 'openai-api-server-via-codex: %s\n' "$(openai-api-server-via-codex --version 2>/dev/null || echo installed)"
if [ "${_codex_cli_ok:-0}" != "1" ]; then
  warn "Codex CLI is unavailable; the proxy is installed but requires a working Codex CLI and login before it can serve requests."
fi
