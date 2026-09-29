#!/bin/sh
set -eu

log()  { printf '\n\033[1;32m== %s ==\033[0m\n' "$*"; }
warn() { printf '\n\033[1;33m!! %s\033[0m\n' "$*" >&2; }
fail() { printf '\n\033[1;31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }

[ "$(id -u)" = "0" ] || fail "Run this module as root."

for _dep in curl bash tar; do
  command -v "$_dep" >/dev/null 2>&1 || fail "Required command not found: $_dep"
done

OPENCODE_INSTALL_HOME="${OPENCODE_INSTALL_HOME:-/root}"
OPENCODE_INSTALL_URL="${OPENCODE_INSTALL_URL:-https://opencode.ai/v2/install}"
OPENCODE_INSTALL_DIR="$OPENCODE_INSTALL_HOME/.opencode/bin"
OPENCODE_INSTALL_BIN="$OPENCODE_INSTALL_DIR/opencode"

export HOME="$OPENCODE_INSTALL_HOME"
mkdir -p "$OPENCODE_INSTALL_DIR" /usr/local/bin

_old_path="$(command -v opencode 2>/dev/null || true)"
_old_version=""
if [ -n "$_old_path" ]; then
  _old_version="$(opencode --version 2>/dev/null | head -1 || true)"
  printf '[opencode] Current: %s%s\n' "${_old_version:-unknown}" " ($_old_path)"
fi

_tmp_installer="$(mktemp /tmp/opencode-v2-install-XXXXXX)"
trap 'rm -f "$_tmp_installer"' 0 HUP INT TERM

log "Installing/updating OpenCode 2"
curl -fsSL "$OPENCODE_INSTALL_URL" -o "$_tmp_installer" \
  || fail "Could not download the OpenCode 2 installer from $OPENCODE_INSTALL_URL"

HOME="$OPENCODE_INSTALL_HOME" bash "$_tmp_installer" --no-modify-path \
  || fail "OpenCode 2 official installer failed."

[ -x "$OPENCODE_INSTALL_BIN" ] \
  || fail "OpenCode 2 installer completed but binary was not found at $OPENCODE_INSTALL_BIN"

_new_version="$("$OPENCODE_INSTALL_BIN" --version 2>/dev/null | head -1 || true)"
[ -n "$_new_version" ] || fail "Installed OpenCode 2 binary did not return a version."

# V1 and early V2 beta package names can leave another opencode earlier/later
# in PATH. Remove package-managed copies only after the V2 binary is verified.
if command -v npm >/dev/null 2>&1; then
  npm uninstall -g opencode-ai @opencode-ai/cli @opencode/cli >/dev/null 2>&1 || true
fi

# aserv services use a stable system-wide path. The official V2 installer
# remains the owner of the real binary under /root/.opencode/bin.
rm -f /usr/local/bin/opencode
ln -s "$OPENCODE_INSTALL_BIN" /usr/local/bin/opencode
hash -r 2>/dev/null || true

_final_version="$(/usr/local/bin/opencode --version 2>/dev/null | head -1 || true)"
[ -n "$_final_version" ] || fail "OpenCode 2 is installed but /usr/local/bin/opencode is not usable."

printf '[opencode] Installed: %s\n' "$_final_version"
printf '[opencode] Binary: %s -> %s\n' "/usr/local/bin/opencode" "$OPENCODE_INSTALL_BIN"
