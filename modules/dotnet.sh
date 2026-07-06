#!/bin/sh
set -eu

# Install latest stable .NET SDK.
# Alpine: try apk packages (dotnet10-sdk / dotnet9-sdk / dotnet8-sdk), fallback to dotnet-install.sh
# Ubuntu/Debian: use dotnet-install.sh directly (packages via Microsoft feed optional)

log() { printf '\n\033[1;32m== %s ==\033[0m\n' "$*"; }
warn() { printf '\n\033[1;33m!! %s\033[0m\n' "$*"; }

if [ -f /etc/alpine-release ]; then
  apk add --no-cache icu-libs krb5-libs libgcc libintl libssl3 libstdc++ zlib curl bash ca-certificates || true
else
  DEBIAN_FRONTEND=noninteractive apt-get install -y -q \
    libicu-dev libkrb5-dev libgcc-s1 libssl3 libstdc++6 zlib1g curl bash ca-certificates 2>/dev/null || true
fi

install_apk_sdk() {
  for pkg in dotnet10-sdk dotnet9-sdk dotnet8-sdk; do
    if apk add --no-cache "$pkg"; then
      return 0
    fi
  done
  return 1
}

if [ -f /etc/alpine-release ] && install_apk_sdk; then
  log "dotnet installed via apk"
else
  warn "dotnet*-sdk package not available via apk; falling back to dotnet-install.sh"
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

dotnet --info || warn "dotnet installed but 'dotnet --info' failed in this shell. Reopen the shell and try again."
