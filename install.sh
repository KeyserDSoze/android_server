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
  if [ "${_selection_ready:-0}" = "1" ]; then
    case " $_selected_features " in
      *" $key "*) return 0 ;;
      *) return 1 ;;
    esac
  fi
  [ "$val" = "true" ] || [ "$val" = "yes" ] || [ "$val" = "1" ]
}

feature_enabled_in_yaml() {
  key="$1"
  [ -f "$CONFIG_FILE" ] || return 1
  val="$(awk -F: -v k="$key" '$1==k {gsub(/[ \t]/,"",$2); print tolower($2)}' "$CONFIG_FILE" | tail -n1)"
  [ "$val" = "true" ] || [ "$val" = "yes" ] || [ "$val" = "1" ]
}

choose_install_mode() {
  _selection_ready=0
  _selected_features=""
  printf '\nInstall mode: [A]ll components or [C]hoose components? [A]: '
  read _mode
  _mode="$(printf '%s' "${_mode:-A}" | tr -d '\r' | tr '[:lower:]' '[:upper:]')"
  [ "$_mode" = "C" ] || { printf 'Install mode: all components enabled in aserv.yaml.\n'; return 0; }

  printf '\nChoose components for this run (Y/N). The aserv.yaml file will not be changed.\n'
  for _feature in github azure dotnet cloudflare opencode openchamber codex codex_proxy ssh docker podman lxc llm tailscale rclone node python devtools aliases services; do
    _default="N"
    feature_enabled_in_yaml "$_feature" && _default="Y"
    printf '  %-12s [%s]: ' "$_feature" "$_default"
    read _answer
    _answer="$(printf '%s' "${_answer:-$_default}" | tr -d '\r' | tr '[:lower:]' '[:upper:]')"
    if [ "$_answer" = "Y" ] || [ "$_answer" = "YES" ]; then
      _selected_features="$_selected_features $_feature"
    fi
  done
  _selection_ready=1
  printf 'Component selection saved for this run.\n'
}

need_root() {
  if [ "$(id -u)" != "0" ]; then
    fail "Run this script as root."
  fi
}

copy_bin() {
  src="$1"; dst="/usr/local/bin/$(basename "$src")"
  install -m 0755 "$src" "$dst"
}

# OS-aware service install
install_service() {
  src="$1"
  name="$(basename "$src")"
  if [ "$OS_ID" = "debian" ]; then
    # Strip .service suffix if present
    svc_name="$(printf '%s' "$name" | sed 's/\.service$//')"
    svc_src="$BASE_DIR/systemd/${svc_name}.service"
    if [ -f "$svc_src" ]; then
      cp "$svc_src" "/etc/systemd/system/${svc_name}.service"
      # Strip Windows CRLF from service file
      sed -i 's/\r$//' "/etc/systemd/system/${svc_name}.service"
      systemctl daemon-reload >/dev/null 2>&1 || true
      systemctl enable "$svc_name" >/dev/null 2>&1 || true
      # Restart if already running so the new config takes effect immediately
      if systemctl is-active "$svc_name" >/dev/null 2>&1; then
        systemctl restart "$svc_name" >/dev/null 2>&1 || true
        printf '  %s: service file updated and restarted\n' "$svc_name"
      else
        printf '  %s: service file installed (will start below)\n' "$svc_name"
      fi
    else
      warn "No systemd service file for $svc_name (expected: systemd/${svc_name}.service)"
    fi
  else
    dst="/etc/init.d/$name"
    install -m 0755 "$src" "$dst"
    rc-update add "$name" default >/dev/null 2>&1 || true
  fi
}

# OS-aware service start/stop
svc_start() {
  if [ "$OS_ID" = "debian" ]; then systemctl restart "$1"; else rc-service "$1" restart; fi
}
svc_stop() {
  if [ "$OS_ID" = "debian" ]; then systemctl stop "$1" 2>/dev/null || true; else rc-service "$1" stop 2>/dev/null || true; fi
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
CLOUDFLARE_CODEX_HOSTNAME=""
AZURE_SUBSCRIPTION_ID=""
SSH_PORT="22"
OPENCHAMBER_PORT="3210"
OPENCHAMBER_PASSWORD=""
OPENCODE_UI_PASSWORD=""
OPENCODE_PORT="3000"
OPENCODE_HOSTNAME="0.0.0.0"
CODEX_PROXY_PORT="22000"
CODEX_PROXY_API_KEY=""
TAILSCALE_AUTH_KEY=""
REINSTALL_CLOUDFLARE=0  # set by prompt below

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

  # Strip Windows CRLF line endings — config files edited on Windows have \r\n
  _clean="$(mktemp /tmp/aserv-clean-XXXXXX)"
  tr -d '\r' < "$_tmp" > "$_clean"
  rm -f "$_tmp"; _tmp="$_clean"

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

# ── OS Detection ─────────────────────────────────────────────────────────────────────
if [ -f /etc/alpine-release ]; then
  OS_ID="alpine"
  CONF_DIR="/etc/conf.d"
elif [ -f /etc/os-release ] && grep -qi 'ubuntu\|debian' /etc/os-release 2>/dev/null; then
  OS_ID="debian"
  CONF_DIR="/etc/default"
else
  OS_ID="unknown"
  CONF_DIR="/etc/conf.d"
  warn "Unknown OS — some commands may fail."
fi

need_root
# Ensure openssl is available for config profile decryption
if [ "$OS_ID" = "debian" ]; then
  apt-get install -y -q openssl >/dev/null 2>&1 || true
else
  apk add --no-cache openssl >/dev/null 2>&1 || true
fi
load_config_profile
choose_install_mode

# ── Interactive setup questions ────────────────────────────────────────────────────────
if is_true cloudflare && [ -n "$CLOUDFLARE_TUNNEL_TOKEN" ]; then
  printf '\n'
  printf '\033[1;33m  WARNING: Reinstalling Cloudflare will KILL the running tunnel.\033[0m\n'
  printf '  If you are connected via SSH through Cloudflare you will be DISCONNECTED.\n'
  printf '\n  Reinstall Cloudflare tunnel? [y/N]: '
  read _cf_ans
  _cf_ans="$(printf '%s' "${_cf_ans:-N}" | tr -d '\r' | tr '[:upper:]' '[:lower:]')"
  if [ "$_cf_ans" = "y" ] || [ "$_cf_ans" = "yes" ]; then
    REINSTALL_CLOUDFLARE=1
    printf '  Cloudflare tunnel will be reinstalled.\n'
  else
    REINSTALL_CLOUDFLARE=0
    printf '  Cloudflare tunnel will be kept as-is.\n'
  fi
fi
printf 'Base dir : %s\n' "$BASE_DIR"
printf 'Config   : %s\n' "$CONFIG_FILE"
mkdir -p /root/projects /root/models /root/logs /root/scripts /root/backup /etc/aserv
cp "$CONFIG_FILE" /etc/aserv/aserv.yaml
printf 'Workspace directories created.\n'

log "Updating packages"
if [ "$OS_ID" = "debian" ]; then
  # Prevent needrestart from auto-restarting services (e.g. cloudflared) during upgrade
  export NEEDRESTART_MODE=l
  export NEEDRESTART_SUSPEND=1
  DEBIAN_FRONTEND=noninteractive apt-get update -q && printf 'Index updated.\n'
  DEBIAN_FRONTEND=noninteractive apt-get upgrade -y -q && printf 'Packages upgraded.\n'
  unset NEEDRESTART_MODE NEEDRESTART_SUSPEND
else
  apk update && printf 'Index updated.\n'
  apk upgrade && printf 'Packages upgraded.\n'
fi

log "Base packages"
if [ "$OS_ID" = "debian" ]; then
  DEBIAN_FRONTEND=noninteractive apt-get install -y -q \
    ca-certificates curl wget git openssh-client openssh-server tmux nano vim htop tree \
    jq zip unzip rsync bash sudo coreutils grep sed gawk procps openssl || true
  # btop not in all Ubuntu versions — optional
  DEBIAN_FRONTEND=noninteractive apt-get install -y -q btop 2>/dev/null || true
else
  apk add --no-cache ca-certificates curl wget git openssh-client openssh-server tmux nano vim htop btop tree jq zip unzip rsync bash shadow sudo openrc util-linux coreutils grep sed gawk procps openssl
fi
printf 'Base packages installed.\n'

log "Git configuration"
ask_if_empty GIT_USER_NAME  "Git user name  (Enter to skip)"
ask_if_empty GIT_USER_EMAIL "Git user email (Enter to skip)"
if [ -n "$GIT_USER_NAME" ];  then git config --global user.name  "$GIT_USER_NAME";  fi
if [ -n "$GIT_USER_EMAIL" ]; then git config --global user.email "$GIT_USER_EMAIL"; fi

if is_true devtools; then
  log "Dev tools"
  if [ "$OS_ID" = "debian" ]; then
    DEBIAN_FRONTEND=noninteractive apt-get install -y -q \
      build-essential clang cmake make pkg-config libssl-dev zlib1g-dev libffi-dev libsqlite3-dev || true
  else
    apk add --no-cache build-base clang cmake make pkgconf linux-headers openssl-dev zlib-dev libffi-dev sqlite-dev
  fi
  printf 'Dev tools installed.\n'
  track_ok "devtools"
else
  printf '[skip] devtools disabled in aserv.yaml\n'
fi

if is_true node; then
  log "Node.js + npm"
  _node_required=20
  is_true openchamber && _node_required=22
  if [ "$OS_ID" = "debian" ]; then
    curl -fsSL https://deb.nodesource.com/setup_22.x | bash - >/dev/null 2>&1 || true
    DEBIAN_FRONTEND=noninteractive apt-get install -y -q nodejs xz-utils || true
  else
    apk add --no-cache nodejs npm || \
    apk add --no-cache nodejs22 npm || \
    apk add --no-cache nodejs20 npm || \
    warn "Node.js installation failed."
  fi
  NODE_VER="$(node -v 2>/dev/null || echo unknown)"
  NPM_VER="$(npm -v 2>/dev/null || echo unknown)"
  printf 'Node.js %s / npm %s\n' "$NODE_VER" "$NPM_VER"
  NODE_MAJOR="$(printf '%s' "$NODE_VER" | sed 's/v//;s/\..*//;s/unknown/0/')"
  if [ "$NODE_MAJOR" -lt "$_node_required" ] 2>/dev/null && [ "$OS_ID" = "debian" ]; then
    _node_arch="$(uname -m)"
    case "$_node_arch" in
      aarch64|arm64) _node_arch="arm64" ;;
      armv7*|armhf)  _node_arch="armv7l" ;;
      x86_64|amd64)  _node_arch="x64" ;;
      *)             _node_arch="" ;;
    esac
    if [ -n "$_node_arch" ]; then
      _node_version="$(curl -fsSL https://nodejs.org/dist/index.json 2>/dev/null | awk -F'"' '/"version":"v22\./ { print $4; exit }')"
      if [ -n "$_node_version" ]; then
        _node_url="https://nodejs.org/dist/${_node_version}/node-${_node_version}-linux-${_node_arch}.tar.xz"
        printf '[node] Current Node.js %s is below required major %s; downloading %s...\n' "$NODE_VER" "$_node_required" "$_node_version"
        if curl -fsSL "$_node_url" -o /tmp/node.tar.xz 2>/dev/null; then
          rm -rf /tmp/node22
          mkdir -p /tmp/node22
          if tar -xJf /tmp/node.tar.xz -C /tmp/node22 --strip-components=1 2>/dev/null; then
            cp -a /tmp/node22/. /usr/local/
            hash -r 2>/dev/null || true
            NODE_VER="$(node -v 2>/dev/null || echo unknown)"
            NPM_VER="$(npm -v 2>/dev/null || echo unknown)"
            NODE_MAJOR="$(printf '%s' "$NODE_VER" | sed 's/v//;s/\..*//;s/unknown/0/')"
          fi
          rm -rf /tmp/node22 /tmp/node.tar.xz
        fi
      fi
    fi
  fi
  if [ "$NODE_MAJOR" -lt "$_node_required" ] 2>/dev/null; then
    warn "Node.js $NODE_VER is too old. Required: Node.js $_node_required+."
    track_fail "node $NODE_VER (too old, need ${_node_required}+)"
  else
    track_ok "node $NODE_VER / npm $NPM_VER"
  fi
else
  printf '[skip] node disabled in aserv.yaml\n'
  track_skip "node"
fi

if is_true python; then
  log "Python"
  if [ "$OS_ID" = "debian" ]; then
    DEBIAN_FRONTEND=noninteractive apt-get install -y -q python3 python3-pip python3-venv || true
  else
    apk add --no-cache python3 py3-pip py3-virtualenv
  fi
  printf 'Python %s\n' "$(python3 --version 2>/dev/null || echo n/a)"
  track_ok "python $(python3 --version 2>/dev/null || echo installed)"
else
  printf '[skip] python disabled in aserv.yaml\n'
  track_skip "python"
fi

if is_true github; then
  log "GitHub CLI"
  if [ "$OS_ID" = "debian" ]; then
    mkdir -p /usr/share/keyrings
    curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
      | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg 2>/dev/null
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
      | tee /etc/apt/sources.list.d/github-cli.list >/dev/null
    apt-get update -q && DEBIAN_FRONTEND=noninteractive apt-get install -y -q gh \
      && track_ok "gh $(gh --version 2>/dev/null | head -1 || echo installed)" \
      || { warn "GitHub CLI apt install failed."; track_fail "github-cli: install failed"; }
  else
    apk add --no-cache github-cli \
      && track_ok "gh $(gh --version 2>/dev/null | head -1 || echo installed)" \
      || { warn "github-cli not available in Alpine repo."; track_fail "github-cli: not in apk repo"; }
  fi
else
  printf '[skip] github disabled in aserv.yaml\n'
  track_skip "github-cli"
fi

if is_true docker; then
  log "Docker"
  if [ "$OS_ID" = "debian" ]; then
    DEBIAN_FRONTEND=noninteractive apt-get install -y -q docker.io docker-compose || true
    systemctl enable docker >/dev/null 2>&1 || true
    systemctl start docker >/dev/null 2>&1 || true
  else
    apk add --no-cache docker docker-cli docker-compose || warn "Docker not installed. If Podroid already includes it, ignore this."
    rc-update add docker default >/dev/null 2>&1 || true
    rc-service docker start >/dev/null 2>&1 || true
  fi
  printf 'Docker: %s\n' "$(docker --version 2>/dev/null || echo n/a)"
  track_ok "docker $(docker --version 2>/dev/null | head -1 || echo installed)"
else
  printf '[skip] docker disabled in aserv.yaml\n'
  track_skip "docker"
fi

if is_true podman; then
  log "Podman"
  if [ "$OS_ID" = "debian" ]; then
    DEBIAN_FRONTEND=noninteractive apt-get install -y -q podman || warn "Podman not available on this Ubuntu version."
  else
    apk add --no-cache podman fuse-overlayfs slirp4netns || warn "Podman not available in repo."
  fi
  track_ok "podman"
else
  printf '[skip] podman disabled in aserv.yaml\n'
  track_skip "podman"
fi

if is_true lxc; then
  log "LXC"
  if [ "$OS_ID" = "debian" ]; then
    DEBIAN_FRONTEND=noninteractive apt-get install -y -q lxc || warn "LXC not available."
  else
    apk add --no-cache lxc lxc-templates || warn "LXC not available in repo."
  fi
  track_ok "lxc"
else
  printf '[skip] lxc disabled in aserv.yaml\n'
  track_skip "lxc"
fi

if is_true cloudflare; then
  log "Cloudflared"
  if [ "$OS_ID" = "debian" ]; then
    mkdir -p --mode=0755 /usr/share/keyrings
    curl -fsSL https://pkg.cloudflare.com/cloudflare-public-v2.gpg | tee /usr/share/keyrings/cloudflare-public-v2.gpg >/dev/null
    echo 'deb [signed-by=/usr/share/keyrings/cloudflare-public-v2.gpg] https://pkg.cloudflare.com/cloudflared any main' \
      | tee /etc/apt/sources.list.d/cloudflared.list >/dev/null
    apt-get update -q && DEBIAN_FRONTEND=noninteractive apt-get install -y -q cloudflared \
      && printf 'cloudflared installed via apt\n' \
      || warn "cloudflared apt install failed."
    if [ -n "$CLOUDFLARE_TUNNEL_TOKEN" ]; then
      if [ "$REINSTALL_CLOUDFLARE" = "1" ]; then
        # Stop any running cloudflared processes before reinstalling
        pkill -f cloudflared 2>/dev/null || true
        sleep 1
        cloudflared service uninstall 2>/dev/null || true
        cloudflared service install "$CLOUDFLARE_TUNNEL_TOKEN" \
          && printf 'cloudflared systemd service installed\n' \
          && track_ok "service: cloudflared started (systemd)" \
          || warn "cloudflared service install failed."
      else
        printf 'Cloudflare tunnel reinstall skipped (keeping existing service).\n'
        track_ok "service: cloudflared (kept, not reinstalled)"
      fi
    fi
  else
    if ! apk add --no-cache cloudflared 2>/dev/null; then
      warn "cloudflared not in apk — downloading binary from GitHub releases."
      _cf_arch="$(uname -m)"
      case "$_cf_arch" in
        aarch64|arm64) _cf_arch="arm64" ;;
        armv7*)        _cf_arch="arm"   ;;
        *)             _cf_arch="amd64" ;;
      esac
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
  fi
else
  printf '[skip] cloudflare disabled in aserv.yaml\n'
  track_skip "cloudflare"
fi

if is_true tailscale; then
  log "Tailscale"
  if [ "$OS_ID" = "debian" ]; then
    curl -fsSL https://tailscale.com/install.sh | sh 2>/dev/null \
      && printf 'Tailscale installed\n' || warn "Tailscale install failed."
    systemctl enable tailscaled >/dev/null 2>&1 || true
    systemctl start tailscaled >/dev/null 2>&1 || true
  else
    apk add --no-cache tailscale || warn "tailscale not available via apk."
    rc-update add tailscale default >/dev/null 2>&1 || true
  fi
  if [ -n "$TAILSCALE_AUTH_KEY" ]; then
    tailscale up --authkey="$TAILSCALE_AUTH_KEY" || warn "Tailscale headless join failed. Run 'tailscale up' manually."
  fi
else
  printf '[skip] tailscale disabled in aserv.yaml\n'
fi

if is_true rclone; then
  log "Rclone"
  if [ "$OS_ID" = "debian" ]; then
    DEBIAN_FRONTEND=noninteractive apt-get install -y -q rclone 2>/dev/null \
      || curl -fsSL https://rclone.org/install.sh | bash 2>/dev/null \
      || warn "rclone install failed."
  else
    apk add --no-cache rclone || warn "rclone not available via apk."
  fi
else
  printf '[skip] rclone disabled in aserv.yaml\n'
fi

if is_true opencode; then
  log "OpenCode"
  _ocode_ok=0

  _install_opencode_npm() {
    printf '[opencode] npm ignore-scripts=%s\n' "$(npm config get ignore-scripts 2>/dev/null || echo unknown)"
    npm_config_ignore_scripts=false npm install -g --foreground-scripts --ignore-scripts=false --allow-scripts=opencode-ai opencode-ai@latest 2>/dev/null || return 1
    command -v opencode >/dev/null 2>&1 && opencode --version >/dev/null 2>&1
  }

  # Detect libc: Alpine/musl needs a specific musl binary
  _oc_arch="$(uname -m)"
  case "$_oc_arch" in
    aarch64|arm64) _oc_arch="arm64" ;;
    x86_64)        _oc_arch="x64"   ;;
    armv7*|armhf)  _oc_arch="armv7l" ;;
    *)             _oc_arch=""      ;;
  esac

  _oc_musl=0
  if [ -f /etc/alpine-release ] || ldd --version 2>&1 | grep -q musl; then
    _oc_musl=1
  fi

  if [ "$_oc_musl" = "1" ] && [ -n "$_oc_arch" ] && [ "$_oc_arch" != "armv7l" ]; then
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

  # Fallback: official npm package (the package is opencode-ai, not opencode).
  if [ $_ocode_ok -eq 0 ] && [ "$_oc_arch" != "armv7l" ] && command -v npm >/dev/null 2>&1; then
    printf '[opencode] Trying npm...\n'
    _install_opencode_npm && _ocode_ok=1 || true
  fi

  # Fallback: official install script (handles its own detection)
  if [ $_ocode_ok -eq 0 ] && [ "$_oc_arch" != "armv7l" ]; then
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
    if [ "$_oc_arch" = "armv7l" ]; then
      warn "  OpenCode does not publish an ARMv7 binary. Raspberry Pi 2 is not supported by the official OpenCode releases."
      warn "  Use a Raspberry Pi 4/5 64-bit OS, or disable opencode in aserv.yaml."
    elif [ "$_oc_musl" = "1" ] && [ -n "$_oc_arch" ]; then
      warn "  curl -fL https://github.com/anomalyco/opencode/releases/latest/download/opencode-linux-${_oc_arch}-musl.tar.gz -o /tmp/oc.tar.gz && tar -xzf /tmp/oc.tar.gz -C /tmp && install -m755 /tmp/opencode /usr/local/bin/opencode"
    else
      warn "  npm install -g opencode-ai@latest"
    fi
    track_fail "opencode: all install methods failed (arch: ${_oc_arch:-unsupported}, musl: ${_oc_musl})"
  fi

  ask_if_empty OPENCODE_UI_PASSWORD "OpenCode UI password (Enter to disable auth)"
  mkdir -p "$CONF_DIR"
  cat > "$CONF_DIR/opencode" <<CFG
OPENCODE_UI_PASSWORD="$OPENCODE_UI_PASSWORD"
OPENCODE_PORT="${OPENCODE_PORT:-3000}"
OPENCODE_HOSTNAME="${OPENCODE_HOSTNAME:-0.0.0.0}"
CFG
  printf 'OpenCode conf written (%s, port %s)\n' "$CONF_DIR/opencode" "${OPENCODE_PORT:-3000}"
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
  mkdir -p "$CONF_DIR"
  cat > "$CONF_DIR/openchamber" <<CFG
OPENCHAMBER_PASSWORD="$OPENCHAMBER_PASSWORD"
OPENCHAMBER_PORT="${OPENCHAMBER_PORT:-3210}"
CFG
  printf 'OpenChamber conf written (%s, port %s)\n' "$CONF_DIR/openchamber" "${OPENCHAMBER_PORT:-3210}"
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

if is_true codex; then
  log "Codex CLI + API proxy"
  sh "$BASE_DIR/modules/codex.sh" \
    && track_ok "codex and openai-api-server-via-codex installed" \
    || { warn "Codex components require manual setup; check the log above."; track_fail "codex: install failed"; }

  if is_true codex_proxy; then
    mkdir -p "$CONF_DIR"
    cat > "$CONF_DIR/codex-proxy" <<CFG
CODEX_PROXY_PORT="${CODEX_PROXY_PORT:-22000}"
CODEX_PROXY_API_KEY="$CODEX_PROXY_API_KEY"
CFG
    printf 'Codex proxy config written (%s, port %s)\n' "$CONF_DIR/codex-proxy" "${CODEX_PROXY_PORT:-22000}"
    if [ -z "$CLOUDFLARE_CODEX_HOSTNAME" ]; then
      warn "CLOUDFLARE_CODEX_HOSTNAME is empty; configure the Cloudflare hostname manually before exposing port ${CODEX_PROXY_PORT:-22000}."
      track_fail "codex proxy: Cloudflare hostname not configured"
    fi
  else
    printf '[skip] codex_proxy disabled in aserv.yaml\n'
    track_skip "codex API proxy"
  fi
else
  printf '[skip] codex disabled in aserv.yaml\n'
  track_skip "codex"
fi

if is_true llm; then
  log "LLM tools: llama.cpp prerequisites"
  if [ "$OS_ID" = "debian" ]; then
    DEBIAN_FRONTEND=noninteractive apt-get install -y -q git cmake make clang libopenblas-dev || true
  else
    apk add --no-cache git cmake make clang openblas-dev || true
  fi
  printf 'LLM prerequisites installed.\n'
  track_ok "llm prerequisites (cmake, clang, openblas)"
else
  printf '[skip] llm disabled in aserv.yaml\n'
  track_skip "llm"
fi

log "Installing aserv-* commands"
mkdir -p /usr/local/lib/aserv
if [ -f "$BASE_DIR/modules/codex.sh" ]; then
  install -m 0755 "$BASE_DIR/modules/codex.sh" /usr/local/lib/aserv/codex.sh
fi
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
      svc_start openchamber \
        && printf '  openchamber started OK (port %s)\n' "${OPENCHAMBER_PORT:-3210}" \
        || warn "openchamber service failed to start — check: aserv-logs openchamber"
      track_ok "service: openchamber started (port ${OPENCHAMBER_PORT:-3210})"
    else
      warn "openchamber binary not found — service registered for boot but NOT started now."
      warn "Install first: npm install -g @openchamber/web"
      track_fail "service: openchamber not started (binary missing)"
    fi
  fi
  if [ "$OS_ID" != "debian" ] && [ -f "$BASE_DIR/openrc/cloudflared" ]; then
    # Ubuntu: cloudflared service already set up by 'cloudflared service install' above
    install_service "$BASE_DIR/openrc/cloudflared"
    if command -v cloudflared >/dev/null 2>&1; then
      svc_start cloudflared \
        && printf '  cloudflared started OK\n' \
        || warn "cloudflared service failed to start — check: aserv-logs cloudflared"
      track_ok "service: cloudflared started"
    else
      warn "cloudflared binary not found — service registered for boot but NOT started now."
      track_fail "service: cloudflared not started (binary missing)"
    fi
  fi
  # opencode service is registered inside the opencode block above (only if binary installed)
  if is_true codex && is_true codex_proxy && command -v openai-api-server-via-codex >/dev/null 2>&1; then
    install_service "$BASE_DIR/openrc/codex-proxy"
    if [ -n "$CODEX_PROXY_API_KEY" ] && [ -f /root/.codex/auth.json ]; then
      svc_start codex-proxy \
        && printf '  codex-proxy started OK (port %s)\n' "${CODEX_PROXY_PORT:-22000}" \
        || warn "codex-proxy service failed to start — configure Codex login and check logs"
      track_ok "service: codex-proxy started (port ${CODEX_PROXY_PORT:-22000})"
    else
      warn "codex-proxy installed but not started: configure API key and run 'codex login --device-auth'."
      track_fail "service: codex-proxy not started (manual authentication/configuration required)"
    fi
  fi
else
  printf '[skip] services disabled in aserv.yaml\n'
  track_skip "OpenRC services"
fi

if is_true ssh; then
  log "SSH"
  if [ -n "$SSH_PORT" ] && [ "$SSH_PORT" != "22" ]; then
    sed -i "s/^#*Port .*/Port $SSH_PORT/" /etc/ssh/sshd_config 2>/dev/null || true
  fi
  if [ "$OS_ID" = "debian" ]; then
    systemctl enable ssh >/dev/null 2>&1 || true
    systemctl restart ssh >/dev/null 2>&1 || true
  else
    rc-update add sshd default >/dev/null 2>&1 || true
    ssh-keygen -A >/dev/null 2>&1 || true
    rc-service sshd restart >/dev/null 2>&1 || true
  fi
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

restart_managed_services() {
  log "Final service restart"
  if [ "$OS_ID" = "debian" ]; then
    for _service in ssh openchamber opencode codex-proxy cloudflared tailscaled docker; do
      if systemctl is-enabled "$_service" >/dev/null 2>&1; then
        systemctl restart "$_service" >/dev/null 2>&1 \
          && printf '  restarted: %s\n' "$_service" \
          || warn "  restart failed: $_service"
      fi
    done
  else
    for _service in sshd openchamber opencode codex-proxy cloudflared tailscale docker; do
      if [ -x "/etc/init.d/$_service" ]; then
        rc-service "$_service" restart >/dev/null 2>&1 \
          && printf '  restarted: %s\n' "$_service" \
          || warn "  restart failed: $_service"
      fi
    done
  fi
}

restart_managed_services

log "Installation complete"
printf '%s\n' "Next steps:" \
  "  1) aserv-setup-cloudflare" \
  "  2) aserv-auth" \
  "  3) codex login --device-auth (if Codex is enabled)" \
  "  4) aserv-status" \
  "  5) Access OpenChamber at your configured domain or locally at port ${OPENCHAMBER_PORT}"

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
