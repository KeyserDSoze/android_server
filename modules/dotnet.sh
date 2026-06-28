#!/bin/sh
set -eu

# Install latest stable .NET SDK for Alpine/ARM64 when available.
# Preferred path: Alpine packages (Microsoft docs list dotnet10-sdk / dotnet9-sdk / dotnet8-sdk).
# Fallback path: Microsoft dotnet-install.sh non-admin install.

log() { printf '\n\033[1;32m== %s ==\033[0m\n' "$*"; }
warn() { printf '\n\033[1;33m!! %s\033[0m\n' "$*"; }

apk add --no-cache icu-libs krb5-libs libgcc libintl libssl3 libstdc++ zlib curl bash ca-certificates || true

install_apk_sdk() {
  for pkg in dotnet10-sdk dotnet9-sdk dotnet8-sdk; do
    if apk add --no-cache "$pkg"; then
      return 0
    fi
  done
  return 1
}

if install_apk_sdk; then
  log "dotnet installato via apk"
else
  warn "Pacchetto dotnet*-sdk non disponibile via apk; uso dotnet-install.sh"
  mkdir -p /opt/dotnet
  curl -fsSL https://dot.net/v1/dotnet-install.sh -o /tmp/dotnet-install.sh
  chmod +x /tmp/dotnet-install.sh
  /tmp/dotnet-install.sh --channel STS --install-dir /opt/dotnet || \
    /tmp/dotnet-install.sh --channel LTS --install-dir /opt/dotnet
  ln -sf /opt/dotnet/dotnet /usr/local/bin/dotnet
fi

if ! grep -q 'DOTNET_ROOT' /root/.profile 2>/dev/null; then
  cat >> /root/.profile <<'PROFILE'

# .NET SDK
export DOTNET_ROOT=/opt/dotnet
export PATH="$PATH:/opt/dotnet:/root/.dotnet/tools"
export DOTNET_CLI_TELEMETRY_OPTOUT=1
PROFILE
fi

export DOTNET_ROOT=/opt/dotnet
export PATH="$PATH:/opt/dotnet:/root/.dotnet/tools"
export DOTNET_CLI_TELEMETRY_OPTOUT=1

dotnet --info || warn "dotnet installato ma dotnet --info non è riuscito in questa shell. Riapri la shell e riprova."
