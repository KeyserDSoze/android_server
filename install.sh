#!/bin/sh
set -eu

BASE_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
CONFIG_FILE="$BASE_DIR/blade.yaml"

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
    fail "Esegui questo script dentro Podroid/Alpine come root."
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

need_root

log "Blade Server Edition bootstrap"
mkdir -p /root/projects /root/models /root/logs /root/scripts /root/backup /etc/blade-server
cp "$CONFIG_FILE" /etc/blade-server/blade.yaml

log "Aggiornamento Alpine"
apk update
apk upgrade

log "Pacchetti base"
apk add --no-cache ca-certificates curl wget git openssh-client openssh-server tmux nano vim htop btop tree jq zip unzip rsync bash shadow sudo openrc util-linux coreutils grep sed gawk procps

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
  apk add --no-cache github-cli || warn "github-cli non disponibile nel repo Alpine: installalo manualmente o usa apk edge/community."
fi

if is_true docker; then
  log "Docker"
  apk add --no-cache docker docker-cli docker-compose || warn "Docker non installato. Se Podroid lo include già, puoi ignorare."
  rc-update add docker default >/dev/null 2>&1 || true
  rc-service docker start >/dev/null 2>&1 || true
fi

if is_true podman; then
  log "Podman"
  apk add --no-cache podman fuse-overlayfs slirp4netns || warn "Podman non installato dai repo."
fi

if is_true lxc; then
  log "LXC"
  apk add --no-cache lxc lxc-templates || warn "LXC non installato dai repo."
fi

if is_true cloudflare; then
  log "Cloudflared"
  apk add --no-cache cloudflared || warn "cloudflared non disponibile via apk. Proverò installer alternativo in blade-setup-cloudflare."
fi

if is_true tailscale; then
  log "Tailscale"
  apk add --no-cache tailscale || warn "tailscale non disponibile via apk."
  rc-update add tailscale default >/dev/null 2>&1 || true
fi

if is_true rclone; then
  log "Rclone"
  apk add --no-cache rclone || warn "rclone non disponibile via apk."
fi

if is_true opencode; then
  log "OpenCode"
  if command -v npm >/dev/null 2>&1; then
    npm install -g opencode-ai || warn "Installazione npm di opencode-ai fallita."
  fi
fi

if is_true openchamber; then
  log "OpenChamber"
  if command -v npm >/dev/null 2>&1; then
    npm install -g openchamber || warn "Installazione npm di openchamber fallita."
  fi
fi

if is_true azure; then
  log "Azure CLI"
  sh "$BASE_DIR/modules/azure.sh" || warn "Azure CLI nativo non riuscito. Il wrapper az proverà fallback Docker."
fi

if is_true dotnet; then
  log ".NET SDK"
  sh "$BASE_DIR/modules/dotnet.sh" || warn ".NET SDK non installato: controlla i log sopra."
fi

if is_true llm; then
  log "LLM tools: llama.cpp prerequisites + helper"
  apk add --no-cache git cmake make clang openblas-dev || true
fi

log "Installazione comandi blade-*"
for f in "$BASE_DIR"/bin/*; do [ -f "$f" ] && copy_bin "$f"; done

log "Installazione servizi OpenRC"
if is_true services; then
  [ -f "$BASE_DIR/openrc/openchamber" ] && install_service "$BASE_DIR/openrc/openchamber"
  [ -f "$BASE_DIR/openrc/cloudflared" ] && install_service "$BASE_DIR/openrc/cloudflared"
fi

if is_true ssh; then
  log "SSH"
  rc-update add sshd default >/dev/null 2>&1 || true
  ssh-keygen -A >/dev/null 2>&1 || true
  rc-service sshd restart >/dev/null 2>&1 || true
fi

if is_true aliases; then
  log "Alias shell"
  grep -q 'blade-server aliases' /root/.profile 2>/dev/null || cat >> /root/.profile <<'PROFILE'

# blade-server aliases
alias blade-status='blade-status'
alias blade-update='blade-update'
alias blade-logs='blade-logs'
alias blade-restart='blade-restart'
alias projects='cd /root/projects'
PROFILE
fi

log "Fine installazione"
printf '%s\n' "Prossimi passi:" \
  "  1) blade-setup-cloudflare" \
  "  2) blade-auth" \
  "  3) blade-status" \
  "  4) Apri OpenChamber dal dominio configurato o via porta locale 3210"
