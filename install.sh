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
  printf '\n[config] Looking for encrypted profiles in %s ...\n' "$_cdir"
  if [ -d "$_cdir" ]; then
    for _f in "$_cdir"/*.enc; do
      [ -f "$_f" ] && _list="$_list $_f"
    done
  fi
  _list="${_list# }"

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
  [ "$_choice" = "0" ] && { printf '[config] Skipped.\n'; return 0; }

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

  printf '[config] Selected: %s\n' "$(basename "$_chosen")"
  printf 'Decryption password: '
  stty -echo 2>/dev/null || true
  read _pass
  stty echo  2>/dev/null || true
  printf '\n'
  _pass="$(printf '%s' "$_pass" | tr -d '\r')"
  printf '[config] Password read (%d chars). Decrypting...\n' "$(printf '%s' "$_pass" | wc -c)"

  _passfile="$(mktemp /tmp/aserv-pass-XXXXXX)"
  chmod 600 "$_passfile"
  printf '%s' "$_pass" > "$_passfile"

  _tmp="$(mktemp /tmp/aserv-cfg-XXXXXX)"
  _openssl_rc=0
  _openssl_err="$(openssl enc -d -aes-256-cbc -pbkdf2 -iter 600000 \
      -in "$_chosen" -out "$_tmp" \
      -pass "file:$_passfile" 2>&1)" || _openssl_rc=$?
  rm -f "$_passfile"

  if [ $_openssl_rc -ne 0 ]; then
    rm -f "$_tmp"
    printf '\n\033[1;31m-- Decryption error --\033[0m\n'
    printf 'File    : %s\n' "$(basename "$_chosen")"
    printf 'openssl : %s\n' "$_openssl_err"
    printf '\nPossible causes:\n'
    printf '  - Wrong password (check CONFIG_PASSWORD in your .conf file)\n'
    printf '  - File corrupted by Git (commit .gitattributes first, re-encrypt)\n'
    printf '  - openssl version mismatch (run: openssl version)\n'
    printf '\nTest manually:\n'
    printf '  openssl enc -d -aes-256-cbc -pbkdf2 -iter 600000 \\\n'
    printf '    -in %s -out /tmp/test.conf \\\n' "$_chosen"
    printf '    -pass "pass:YOUR_PASSWORD" && head -3 /tmp/test.conf\n\n'
    fail "Decryption failed — see details above."
  fi

  # Source the decrypted config; relax -eu temporarily for safe include
  set +eu
  # shellcheck disable=SC1090
  . "$_tmp"
  set -eu
  rm -f "$_tmp"

  printf '\033[1;32m[config] Profile loaded successfully: %s\033[0m\n' "$(basename "$_chosen" .enc)"
  printf '[config] Git: %s <%s>\n' "$GIT_USER_NAME" "$GIT_USER_EMAIL"
  if [ -n "$CLOUDFLARE_TUNNEL_TOKEN" ]; then printf '[config] Cloudflare token: set\n'; fi
  if [ -n "$OPENCODE_UI_PASSWORD" ];    then printf '[config] OpenCode password: set\n'; fi
  if [ -n "$OPENCHAMBER_PASSWORD" ];    then printf '[config] OpenChamber password: set\n'; fi
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

# ── Installation tracking ─────────────────────────────────────────────────────────────────────
_ok=""; _fail=""; _skip=""
track_ok()   { _ok="${_ok}  OK   $*\n"; }
track_fail() { _fail="${_fail}  FAIL $*\n"; }
track_skip() { _skip="${_skip}  SKIP $*\n"; }

need_root
# openssl must be available before load_config_profile runs
apk add --no-cache openssl >/dev/null 2>&1 || true
load_config_profile

log "Blade Server bootstrap"
printf 'Base dir : %s\n' "$BASE_DIR"
printf 'Config   : %s\n' "$CONFIG_FILE"
mkdir -p /root/projects /root/models /root/logs /root/scripts /root/backup /etc/aserv
cp "$CONFIG_FILE" /etc/aserv/aserv.yaml
printf 'Workspace directories created.\n'

log "Updating Alpine packages"
apk update && printf 'Index updated.\n'
apk upgrade && printf 'Packages upgraded.\n'

log "Base packages"
apk add --no-cache ca-certificates curl wget git openssh-client openssh-server tmux nano vim htop btop tree jq zip unzip rsync bash shadow sudo openrc util-linux coreutils grep sed gawk procps openssl
printf 'Base packages installed.\n'

log "Git configuration"
ask_if_empty GIT_USER_NAME  "Git user name  (Enter to skip)"
ask_if_empty GIT_USER_EMAIL "Git user email (Enter to skip)"
if [ -n "$GIT_USER_NAME" ];  then git config --global user.name  "$GIT_USER_NAME";  fi
if [ -n "$GIT_USER_EMAIL" ]; then git config --global user.email "$GIT_USER_EMAIL"; fi

if is_true devtools; then
  log "Dev tools"
  apk add --no-cache build-base clang cmake make pkgconf linux-headers openssl-dev zlib-dev libffi-dev sqlite-dev
  printf 'Dev tools installed.\n'
else
  printf '[skip] devtools disabled in aserv.yaml\n'
fi

if is_true node; then
  log "Node.js + npm"
  # Try Node.js 22 LTS, then 20 LTS, then whatever Alpine has
  apk add --no-cache nodejs npm || \
  apk add --no-cache nodejs22 npm || \
  apk add --no-cache nodejs20 npm || \
  warn "Node.js installation failed."
  NODE_VER="$(node -v 2>/dev/null || echo unknown)"
  NPM_VER="$(npm -v 2>/dev/null || echo unknown)"
  printf 'Node.js %s / npm %s\n' "$NODE_VER" "$NPM_VER"
  # Warn if node is too old for opencode/openchamber
  NODE_MAJOR="$(printf '%s' "$NODE_VER" | sed 's/v//;s/\..*//;s/unknown/0/')"
  if [ "$NODE_MAJOR" -lt 20 ] 2>/dev/null; then
    warn "Node.js $NODE_VER may be too old. opencode/openchamber require Node 20+."
    warn "Consider upgrading Alpine or running: apk add nodejs --repository=http://dl-cdn.alpinelinux.org/alpine/edge/community"
  fi
else
  printf '[skip] node disabled in aserv.yaml\n'
fi

if is_true python; then
  log "Python"
  apk add --no-cache python3 py3-pip py3-virtualenv
  printf 'Python %s\n' "$(python3 --version 2>/dev/null || echo n/a)"
else
  printf '[skip] python disabled in aserv.yaml\n'
fi

if is_true github; then
  log "GitHub CLI"
  apk add --no-cache github-cli \
    && track_ok "gh $(gh --version 2>/dev/null | head -1 || echo installed)" \
    || { warn "github-cli not available in Alpine repo. Install manually or use apk edge/community."; track_fail "github-cli: not in apk repo"; }
else
  printf '[skip] github disabled in aserv.yaml\n'
  track_skip "github-cli"
fi

if is_true docker; then
  log "Docker"
  apk add --no-cache docker docker-cli docker-compose || warn "Docker not installed. If Podroid already includes it, ignore this."
  rc-update add docker default >/dev/null 2>&1 || true
  rc-service docker start >/dev/null 2>&1 || true
  printf 'Docker: %s\n' "$(docker --version 2>/dev/null || echo n/a)"
  track_ok "docker $(docker --version 2>/dev/null | head -1 || echo installed)"
else
  printf '[skip] docker disabled in aserv.yaml\n'
  track_skip "docker"
fi

if is_true podman; then
  log "Podman"
  apk add --no-cache podman fuse-overlayfs slirp4netns || warn "Podman not available in repo."
  track_ok "podman"
else
  printf '[skip] podman disabled in aserv.yaml\n'
  track_skip "podman"
fi

if is_true lxc; then
  log "LXC"
  apk add --no-cache lxc lxc-templates || warn "LXC not available in repo."
  track_ok "lxc"
else
  printf '[skip] lxc disabled in aserv.yaml\n'
  track_skip "lxc"
fi

if is_true cloudflare; then
  log "Cloudflared"
  if ! apk add --no-cache cloudflared 2>/dev/null; then
    warn "cloudflared not in apk — downloading binary from GitHub releases."
    _cf_arch="$(uname -m)"
    case "$_cf_arch" in
      aarch64|arm64) _cf_arch="arm64" ;;
      armv7*)        _cf_arch="arm"   ;;
      *)             _cf_arch="amd64" ;;
    esac
    printf 'Architecture: %s -> cloudflared-linux-%s\n' "$(uname -m)" "$_cf_arch"
    curl -fsSL \
      "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${_cf_arch}" \
      -o /usr/local/bin/cloudflared \
      && chmod +x /usr/local/bin/cloudflared \
      && printf 'cloudflared downloaded: %s\n' "$(cloudflared --version 2>/dev/null || echo ok)" \
      || warn "cloudflared download failed. Try manually: https://github.com/cloudflare/cloudflared/releases"
  else
    printf 'cloudflared installed via apk: %s\n' "$(cloudflared --version 2>/dev/null || echo ok)"
  fi
  if [ -n "$CLOUDFLARE_TUNNEL_TOKEN" ]; then
    mkdir -p /etc/aserv
    printf '%s\n' "$CLOUDFLARE_TUNNEL_TOKEN" > /etc/aserv/cloudflare-token
    chmod 600 /etc/aserv/cloudflare-token
    printf 'Cloudflare tunnel token saved to /etc/aserv/cloudflare-token\n'
  else
    printf 'No tunnel token set — run aserv-setup-cloudflare after install.\n'
  fi
else
  printf '[skip] cloudflare disabled in aserv.yaml\n'
fi

if is_true tailscale; then
  log "Tailscale"
  apk add --no-cache tailscale || warn "tailscale not available via apk."
  rc-update add tailscale default >/dev/null 2>&1 || true
  if [ -n "$TAILSCALE_AUTH_KEY" ]; then
    tailscale up --authkey="$TAILSCALE_AUTH_KEY" || warn "Tailscale headless join failed. Run 'tailscale up' manually."
  fi
else
  printf '[skip] tailscale disabled in aserv.yaml\n'
fi

if is_true rclone; then
  log "Rclone"
  apk add --no-cache rclone || warn "rclone not available via apk."
else
  printf '[skip] rclone disabled in aserv.yaml\n'
fi

if is_true opencode; then
  log "OpenCode"
  _ocode_ok=0

  # Detect libc: Alpine/musl needs a specific musl binary
  _oc_arch="$(uname -m)"
  case "$_oc_arch" in
    aarch64|arm64) _oc_arch="arm64" ;;
    x86_64)        _oc_arch="x64"   ;;
    *)             _oc_arch="x64"   ;;
  esac

  if [ -f /etc/alpine-release ] || (ldd --version 2>&1 | grep -q musl 2>/dev/null); then
    # Alpine/musl: download musl-specific binary
    printf '[opencode] Alpine/musl detected — downloading musl binary (%s)...\n' "$_oc_arch"
    apk add --no-cache tar curl ca-certificates >/dev/null 2>&1 || true
    _oc_url="https://github.com/anomalyco/opencode/releases/latest/download/opencode-linux-${_oc_arch}-musl.tar.gz"
    printf '[opencode] URL: %s\n' "$_oc_url"
    if curl -fL "$_oc_url" -o /tmp/opencode.tar.gz 2>/dev/null \
        && tar -xzf /tmp/opencode.tar.gz -C /tmp 2>/dev/null \
        && install -m 755 /tmp/opencode /usr/local/bin/opencode; then
      rm -f /tmp/opencode.tar.gz /tmp/opencode
      printf 'opencode musl binary installed OK\n'
      _ocode_ok=1
    else
      warn "musl binary download/extract failed. URL: $_oc_url"
      rm -f /tmp/opencode.tar.gz /tmp/opencode
    fi
  fi

  # Fallback: npm (works on glibc systems, often fails on musl)
  if [ $_ocode_ok -eq 0 ] && command -v npm >/dev/null 2>&1; then
    printf '[opencode] Trying npm...\n'
    npm install -g opencode 2>/dev/null && _ocode_ok=1 || \
    npm install -g opencode-ai 2>/dev/null && _ocode_ok=1 || true
  fi

  # Fallback: official install script (handles its own detection)
  if [ $_ocode_ok -eq 0 ]; then
    printf '[opencode] Trying official install script...\n'
    curl -fsSL https://opencode.ai/install | sh 2>/dev/null && _ocode_ok=1 || true
  fi

  if [ $_ocode_ok -eq 1 ] && command -v opencode >/dev/null 2>&1; then
    printf 'opencode: %s\n' "$(opencode --version 2>/dev/null | head -1 || echo installed)"
    track_ok "opencode $(opencode --version 2>/dev/null | head -1 || echo installed)"
    if is_true services && [ -f "$BASE_DIR/openrc/opencode" ]; then
      install_service "$BASE_DIR/openrc/opencode"
      printf '  opencode service registered\n'
      track_ok "service: opencode (autostart)"
    fi
  else
    warn "opencode installation failed. Install manually with:"
    warn "  curl -fL https://github.com/anomalyco/opencode/releases/latest/download/opencode-linux-${_oc_arch}-musl.tar.gz -o /tmp/oc.tar.gz && tar -xzf /tmp/oc.tar.gz -C /tmp && install -m755 /tmp/opencode /usr/local/bin/opencode"
    track_fail "opencode: all install methods failed (arch: ${_oc_arch}, musl: yes)"
  fi

  ask_if_empty OPENCODE_UI_PASSWORD "OpenCode UI password (Enter to disable auth)"
  mkdir -p /etc/conf.d
  cat > /etc/conf.d/opencode <<CFG
OPENCODE_UI_PASSWORD="$OPENCODE_UI_PASSWORD"
OPENCODE_PORT="${OPENCODE_PORT:-3000}"
OPENCODE_HOSTNAME="${OPENCODE_HOSTNAME:-0.0.0.0}"
CFG
  printf 'OpenCode conf.d written (port %s)\n' "${OPENCODE_PORT:-3000}"
else
  printf '[skip] opencode disabled in aserv.yaml\n'
  track_skip "opencode"
fi

if is_true openchamber; then
  log "OpenChamber"
  # OpenChamber requires Node.js 22+
  _ocm_node="$(node -v 2>/dev/null | sed 's/v//;s/\..*//' || echo 0)"
  if [ "${_ocm_node:-0}" -lt 22 ] 2>/dev/null; then
    warn "OpenChamber requires Node.js 22+. Current: $(node -v 2>/dev/null || echo not installed)"
    track_fail "openchamber: Node.js 22+ required (current: v${_ocm_node})"
  else
    _ocm_ok=0
    if command -v npm >/dev/null 2>&1; then
      npm install -g @openchamber/web 2>/dev/null \
        && printf '@openchamber/web installed OK\n' && _ocm_ok=1 \
        || warn "@openchamber/web npm install failed — trying official install script..."
    fi
    if [ $_ocm_ok -eq 0 ]; then
      curl -fsSL https://raw.githubusercontent.com/openchamber/openchamber/main/scripts/install.sh \
        | bash 2>/dev/null \
        && printf 'openchamber installed via script OK\n' && _ocm_ok=1 \
        || warn "OpenChamber curl installer also failed."
    fi
    if [ $_ocm_ok -eq 1 ]; then
      track_ok "openchamber $(openchamber --version 2>/dev/null | head -1 || echo installed)"
    else
      track_fail "openchamber: all install methods failed"
    fi
  fi
  ask_if_empty OPENCHAMBER_PASSWORD "OpenChamber UI password (Enter to disable auth)"
  mkdir -p /etc/conf.d
  cat > /etc/conf.d/openchamber <<CFG
OPENCHAMBER_PASSWORD="$OPENCHAMBER_PASSWORD"
OPENCHAMBER_PORT="${OPENCHAMBER_PORT:-3210}"
CFG
  printf 'OpenChamber conf.d written (port %s)\n' "${OPENCHAMBER_PORT:-3210}"
else
  printf '[skip] openchamber disabled in aserv.yaml\n'
  track_skip "openchamber"
fi

if is_true azure; then
  log "Azure CLI"
  sh "$BASE_DIR/modules/azure.sh" \
    && track_ok "azure-cli $(az version 2>/dev/null | grep '"azure-cli"' | sed 's/.*: "//;s/".*//' || echo installed)" \
    || { warn "Native Azure CLI install failed. The az wrapper will fall back to Docker."; track_fail "azure-cli: native install failed (Docker fallback active)"; }
else
  printf '[skip] azure disabled in aserv.yaml\n'
  track_skip "azure-cli"
fi

if is_true dotnet; then
  log ".NET SDK"
  sh "$BASE_DIR/modules/dotnet.sh" \
    && track_ok "dotnet $(dotnet --version 2>/dev/null || echo installed)" \
    || { warn ".NET SDK not installed: check the log above."; track_fail "dotnet: install failed"; }
else
  printf '[skip] dotnet disabled in aserv.yaml\n'
  track_skip "dotnet"
fi

if is_true llm; then
  log "LLM tools: llama.cpp prerequisites"
  apk add --no-cache git cmake make clang openblas-dev || true
  printf 'LLM prerequisites installed.\n'
  track_ok "llm prerequisites (cmake, clang, openblas)"
else
  printf '[skip] llm disabled in aserv.yaml\n'
  track_skip "llm"
fi

log "Installing aserv-* commands"
for f in "$BASE_DIR"/bin/*; do
  if [ -f "$f" ]; then
    copy_bin "$f"
    printf '  installed: %s\n' "$(basename "$f")"
  fi
done

log "Registering and starting OpenRC services"
if is_true services; then
  if [ -f "$BASE_DIR/openrc/openchamber" ]; then
    install_service "$BASE_DIR/openrc/openchamber"
    if command -v openchamber >/dev/null 2>&1; then
      rc-service openchamber restart \
        && printf '  openchamber started OK (port %s)\n' "${OPENCHAMBER_PORT:-3210}" \
        || warn "openchamber service failed to start — check: aserv-logs openchamber"
      track_ok "service: openchamber started (port ${OPENCHAMBER_PORT:-3210})"
    else
      warn "openchamber binary not found — service registered for boot but NOT started now."
      warn "Install first: npm install -g @openchamber/web"
      track_fail "service: openchamber not started (binary missing)"
    fi
  fi
  if [ -f "$BASE_DIR/openrc/cloudflared" ]; then
    install_service "$BASE_DIR/openrc/cloudflared"
    if command -v cloudflared >/dev/null 2>&1; then
      rc-service cloudflared restart \
        && printf '  cloudflared started OK\n' \
        || warn "cloudflared service failed to start — check: aserv-logs cloudflared"
      track_ok "service: cloudflared started"
    else
      warn "cloudflared binary not found — service registered for boot but NOT started now."
      track_fail "service: cloudflared not started (binary missing)"
    fi
  fi
  # opencode service is registered inside the opencode block above (only if binary installed)
else
  printf '[skip] services disabled in aserv.yaml\n'
  track_skip "OpenRC services"
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

# ────────────────────────────────────────────────────────────────
printf '\n'
printf '\033[1;37m%s\033[0m\n' '================================================'
printf '\033[1;37m%s\033[0m\n' '          INSTALLATION SUMMARY'
printf '\033[1;37m%s\033[0m\n' '================================================'

if [ -n "$_ok" ]; then
  printf '\n\033[1;32mSucceeded:\033[0m\n'
  printf '%b' "$_ok"
fi

if [ -n "$_skip" ]; then
  printf '\n\033[1;33mSkipped (disabled in aserv.yaml):\033[0m\n'
  printf '%b' "$_skip"
fi

if [ -n "$_fail" ]; then
  printf '\n\033[1;31mFailed:\033[0m\n'
  printf '%b' "$_fail"
  printf '\n\033[1;31mRun aserv-update or re-run install.sh to retry failed components.\033[0m\n'
fi

printf '\033[1;37m%s\033[0m\n' '================================================'
