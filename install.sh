#!/bin/sh
set -eu

BASE_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
CONFIG_FILE="$BASE_DIR/aserv.yaml"

log() { printf '\n\033[1;32m== %s ==\033[0m\n' "$*"; }
warn() { printf '\n\033[1;33m!! %s\033[0m\n' "$*"; }
fail() { printf '\n\033[1;31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }

is_true() {
  key="$1"
  [ -f "$CONFIG_FILE" ] || return 1
  val="$(awk -F: -v k="$key" '$1==k {gsub(/[ \t]/,"",$2); print tolower($2)}' "$CONFIG_FILE" | tail -n1)"
  [ "$val" = "true" ] || [ "$val" = "yes" ] || [ "$val" = "1" ]
}

need_root() {
  if [ "$(id -u)" != "0" ]; then
    fail "Run this script inside Podroid/Alpine as root."
  fi
}

copy_bin() {
  src="$1"; dst="/usr/local/bin/$(basename "$src")"
  install -m 0755 "$src" "$dst"
}

install_service() {
  src="$1"; dst="/etc/init.d/$(basename "$src")"
  install -m 0755 "$src" "$dst"
  rc-update add "$(basename "$src")" default >/dev/null 2>&1 || true
}

# ── Secret Configuration Variables ─────────────────────────────────────────
# Initialised to empty so set -u never fires on unset variable references.
GIT_USER_NAME=""
GIT_USER_EMAIL=""
GITHUB_TOKEN=""
CLOUDFLARE_TUNNEL_NAME=""
CLOUDFLARE_HOSTNAME=""
CLOUDFLARE_TUNNEL_TOKEN=""
CLOUDFLARE_SSH_HOSTNAME=""
AZURE_SUBSCRIPTION_ID=""
SSH_PORT="22"
OPENCHAMBER_PORT="3210"
OPENCHAMBER_PASSWORD=""
OPENCODE_UI_PASSWORD=""
OPENCODE_PORT="3000"
OPENCODE_HOSTNAME="0.0.0.0"
TAILSCALE_AUTH_KEY=""

# Load and decrypt a config profile from config/*.enc
load_config_profile() {
  _cdir="$BASE_DIR/config"
  _list=""
  if [ -d "$_cdir" ]; then
    for _f in "$_cdir"/*.enc; do
      [ -f "$_f" ] && _list="$_list $_f"
    done
  fi
  _list="${_list# }"  # trim leading space

  if [ -z "$_list" ]; then
    warn "No encrypted config profiles found in config/. All secrets will be entered interactively."
    return 0
  fi

  printf '\n'
  log "Available config profiles"
  _i=0
  for _f in $_list; do
    _i=$((_i+1))
    printf '  %d) %s\n' "$_i" "$(basename "$_f" .enc)"
  done
  printf '  0) Skip — enter secrets interactively\n'
  printf '\nSelect profile [0]: '
  read _choice
  _choice="${_choice:-0}"
  [ "$_choice" = "0" ] && return 0

  _chosen=""
  _i=0
  for _f in $_list; do
    _i=$((_i+1))
    [ "$_i" = "$_choice" ] && _chosen="$_f"
  done
  if [ -z "$_chosen" ]; then
    warn "Invalid selection. Continuing without a config profile."
    return 0
  fi

  printf 'Decryption password for %s: ' "$(basename "$_chosen")"
  stty -echo 2>/dev/null || true
  read _pass
  stty echo  2>/dev/null || true
  printf '\n'
  # Strip \r sent by some Android terminals when pressing Enter
  _pass="$(printf '%s' "$_pass" | tr -d '\r')"

  # Write passphrase to a temp file to avoid shell quoting issues with
  # special characters (e.g. @ $ ! in passwords)
  _passfile="$(mktemp /tmp/aserv-pass-XXXXXX)"
  chmod 600 "$_passfile"
  printf '%s' "$_pass" > "$_passfile"

  _tmp="$(mktemp /tmp/aserv-cfg-XXXXXX)"
  _openssl_err="$(openssl enc -d -aes-256-cbc -pbkdf2 -iter 600000 \
      -in "$_chosen" -out "$_tmp" \
      -pass "file:$_passfile" 2>&1)"
  _openssl_rc=$?
  rm -f "$_passfile"

  if [ $_openssl_rc -ne 0 ]; then
    rm -f "$_tmp"
    warn "openssl error: $_openssl_err"
    fail "Decryption failed for $(basename "$_chosen"). Check password and that the file was committed with .gitattributes."
  fi

  # Source the decrypted config; relax -eu temporarily for safe include
  set +eu
  # shellcheck disable=SC1090
  . "$_tmp"
  set -eu
  rm -f "$_tmp"

  log "Config profile loaded: $(basename "$_chosen" .enc)"
}

# Prompt for a value if the named variable is currently empty.
# $1 = variable name   $2 = prompt text
ask_if_empty() {
  eval "_v=\${$1:-}"
  if [ -z "$_v" ]; then
    printf '%s: ' "$2"
    read _v
    eval "$1=\"\$_v\""
  fi
}

need_root
load_config_profile

log "Blade Server bootstrap"
mkdir -p /root/projects /root/models /root/logs /root/scripts /root/backup /etc/aserv
cp "$CONFIG_FILE" /etc/aserv/aserv.yaml

log "Updating Alpine packages"
apk update
apk upgrade

log "Base packages"
apk add --no-cache ca-certificates curl wget git openssh-client openssh-server tmux nano vim htop btop tree jq zip unzip rsync bash shadow sudo openrc util-linux coreutils grep sed gawk procps openssl

log "Git configuration"
ask_if_empty GIT_USER_NAME  "Git user name  (Enter to skip)"
ask_if_empty GIT_USER_EMAIL "Git user email (Enter to skip)"
if [ -n "$GIT_USER_NAME" ];  then git config --global user.name  "$GIT_USER_NAME";  fi
if [ -n "$GIT_USER_EMAIL" ]; then git config --global user.email "$GIT_USER_EMAIL"; fi

if is_true devtools; then
  log "Dev tools"
  apk add --no-cache build-base clang cmake make pkgconf linux-headers openssl-dev zlib-dev libffi-dev sqlite-dev
fi

if is_true node; then
  log "Node.js + npm"
  apk add --no-cache nodejs npm
fi

if is_true python; then
  log "Python"
  apk add --no-cache python3 py3-pip py3-virtualenv
fi

if is_true github; then
  log "GitHub CLI"
  apk add --no-cache github-cli || warn "github-cli not available in Alpine repo. Install manually or use apk edge/community."
fi

if is_true docker; then
  log "Docker"
  apk add --no-cache docker docker-cli docker-compose || warn "Docker not installed. If Podroid already includes it, ignore this."
  rc-update add docker default >/dev/null 2>&1 || true
  rc-service docker start >/dev/null 2>&1 || true
fi

if is_true podman; then
  log "Podman"
  apk add --no-cache podman fuse-overlayfs slirp4netns || warn "Podman not available in repo."
fi

if is_true lxc; then
  log "LXC"
  apk add --no-cache lxc lxc-templates || warn "LXC not available in repo."
fi

if is_true cloudflare; then
  log "Cloudflared"
  apk add --no-cache cloudflared || warn "cloudflared not available via apk. Use aserv-setup-cloudflare for alternative install."
  if [ -n "$CLOUDFLARE_TUNNEL_TOKEN" ]; then
    mkdir -p /etc/aserv
    printf '%s\n' "$CLOUDFLARE_TUNNEL_TOKEN" > /etc/aserv/cloudflare-token
    chmod 600 /etc/aserv/cloudflare-token
    log "Cloudflare tunnel token saved to /etc/aserv/cloudflare-token"
  fi
fi

if is_true tailscale; then
  log "Tailscale"
  apk add --no-cache tailscale || warn "tailscale not available via apk."
  rc-update add tailscale default >/dev/null 2>&1 || true
  if [ -n "$TAILSCALE_AUTH_KEY" ]; then
    tailscale up --authkey="$TAILSCALE_AUTH_KEY" || warn "Tailscale headless join failed. Run 'tailscale up' manually."
  fi
fi

if is_true rclone; then
  log "Rclone"
  apk add --no-cache rclone || warn "rclone not available via apk."
fi

if is_true opencode; then
  log "OpenCode"
  if command -v npm >/dev/null 2>&1; then
    npm install -g opencode-ai || warn "npm install of opencode-ai failed."
  fi
  ask_if_empty OPENCODE_UI_PASSWORD "OpenCode UI password (Enter to disable auth)"
  mkdir -p /etc/conf.d
  cat > /etc/conf.d/opencode <<CFG
OPENCODE_UI_PASSWORD="$OPENCODE_UI_PASSWORD"
OPENCODE_PORT="${OPENCODE_PORT:-3000}"
OPENCODE_HOSTNAME="${OPENCODE_HOSTNAME:-0.0.0.0}"
CFG
fi

if is_true openchamber; then
  log "OpenChamber"
  if command -v npm >/dev/null 2>&1; then
    npm install -g openchamber || warn "npm install of openchamber failed."
  fi
  ask_if_empty OPENCHAMBER_PASSWORD "OpenChamber UI password (Enter to disable auth)"
  mkdir -p /etc/conf.d
  cat > /etc/conf.d/openchamber <<CFG
OPENCHAMBER_PASSWORD="$OPENCHAMBER_PASSWORD"
OPENCHAMBER_PORT="${OPENCHAMBER_PORT:-3210}"
CFG
fi

if is_true azure; then
  log "Azure CLI"
  sh "$BASE_DIR/modules/azure.sh" || warn "Native Azure CLI install failed. The az wrapper will fall back to Docker."
fi

if is_true dotnet; then
  log ".NET SDK"
  sh "$BASE_DIR/modules/dotnet.sh" || warn ".NET SDK not installed: check the log above."
fi

if is_true llm; then
  log "LLM tools: llama.cpp prerequisites"
  apk add --no-cache git cmake make clang openblas-dev || true
fi

log "Installing aserv-* commands"
for f in "$BASE_DIR"/bin/*; do [ -f "$f" ] && copy_bin "$f"; done

log "Registering OpenRC services"
if is_true services; then
  [ -f "$BASE_DIR/openrc/openchamber" ] && install_service "$BASE_DIR/openrc/openchamber"
  [ -f "$BASE_DIR/openrc/cloudflared" ] && install_service "$BASE_DIR/openrc/cloudflared"
  if is_true opencode; then
    [ -f "$BASE_DIR/openrc/opencode" ] && install_service "$BASE_DIR/openrc/opencode"
  fi
fi

if is_true ssh; then
  log "SSH"
  if [ -n "$SSH_PORT" ] && [ "$SSH_PORT" != "22" ]; then
    sed -i "s/^#*Port .*/Port $SSH_PORT/" /etc/ssh/sshd_config 2>/dev/null || true
  fi
  rc-update add sshd default >/dev/null 2>&1 || true
  ssh-keygen -A >/dev/null 2>&1 || true
  rc-service sshd restart >/dev/null 2>&1 || true
fi

if is_true aliases; then
  log "Shell aliases"
  grep -q 'aserv aliases' /root/.profile 2>/dev/null || cat >> /root/.profile <<'PROFILE'

# aserv aliases
alias aserv-status='aserv-status'
alias aserv-update='aserv-update'
alias aserv-logs='aserv-logs'
alias aserv-restart='aserv-restart'
alias projects='cd /root/projects'
PROFILE
fi

log "Installation complete"
printf '%s\n' "Next steps:" \
  "  1) aserv-setup-cloudflare" \
  "  2) aserv-auth" \
  "  3) aserv-status" \
  "  4) Access OpenChamber at your configured domain or locally at port ${OPENCHAMBER_PORT}"
