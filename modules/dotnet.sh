#!/bin/sh
set -eu

# Install the latest supported .NET SDK, preferring .NET 10.
# ARM32 uses the official installer because Microsoft package feeds do not publish
# all SDK versions for that architecture.

log() { printf '\n\033[1;32m== %s ==\033[0m\n' "$*"; }
warn() { printf '\n\033[1;33m!! %s\033[0m\n' "$*"; }

if [ -f /etc/alpine-release ]; then
  DISTRO="alpine"
  apk add --no-cache icu-libs krb5-libs libgcc libintl libssl3 libstdc++ zlib curl bash ca-certificates || true
else
  DISTRO="debian"
  DEBIAN_FRONTEND=noninteractive apt-get install -y -q \
    libicu-dev libkrb5-dev libgcc-s1 libssl3 libstdc++6 zlib1g curl bash ca-certificates 2>/dev/null || true
fi

ARCH="$(uname -m)"
case "$ARCH" in
  armv7*|armhf) DOTNET_ARCH="arm" ;;
  aarch64|arm64) DOTNET_ARCH="arm64" ;;
  x86_64|amd64) DOTNET_ARCH="x64" ;;
  armv6*|armel) DOTNET_ARCH="arm" ;;
  *) DOTNET_ARCH="unsupported" ;;
esac

printf '[dotnet] Discovery: distro=%s arch=%s dotnet-arch=%s\n' "$DISTRO" "$ARCH" "$DOTNET_ARCH"
EXISTING_SDKS=""
EXISTING_DOTNET10=""
EXISTING_DOTNET9=""
if command -v dotnet >/dev/null 2>&1; then
  printf '[dotnet] Existing SDKs:\n'
  EXISTING_SDKS="$(dotnet --list-sdks 2>/dev/null || true)"
  printf '%s\n' "$EXISTING_SDKS"
  EXISTING_DOTNET10="$(printf '%s\n' "$EXISTING_SDKS" | awk '$1 ~ /^10\./ {print $1}' | sort -V | tail -n1)"
  EXISTING_DOTNET9="$(printf '%s\n' "$EXISTING_SDKS" | awk '$1 ~ /^9\./ {print $1}' | sort -V | tail -n1)"
else
  printf '[dotnet] Existing SDKs: none found\n'
fi

if [ -n "$EXISTING_DOTNET10" ]; then
  log ".NET 10 already installed"
  printf '[dotnet] Keeping installed SDK %s; no download or major-version fallback is needed.\n' "$EXISTING_DOTNET10"
  DOTNET_INSTALL_NEEDED=0
else
  DOTNET_INSTALL_NEEDED=1
fi

install_apk_sdk() {
  pkg="dotnet10-sdk"
  if apk search -x "$pkg" 2>/dev/null | grep -q "^${pkg}-"; then
    printf '[dotnet] Discovery: Alpine package %s is available\n' "$pkg"
    apk add --no-cache "$pkg" && return 0
  else
    printf '[dotnet] Discovery: Alpine package %s is not available\n' "$pkg"
  fi
  return 1
}

install_scripted_sdk() {
  channel="$1"
  printf '[dotnet] Trying official SDK channel %s for %s...\n' "$channel" "$DOTNET_ARCH"
  if [ "$DOTNET_ARCH" = "unsupported" ]; then
    warn "Unsupported .NET architecture: $ARCH"
    return 1
  fi
  /bin/bash /tmp/dotnet-install.sh --channel "$channel" --install-dir /opt/dotnet
}

if [ "${DOTNET_INSTALL_NEEDED:-1}" = "0" ]; then
  :
elif [ "$DISTRO" = "alpine" ] && install_apk_sdk; then
  log "dotnet installed via apk"
else
  if [ "$DISTRO" = "alpine" ]; then
    warn "No supported Alpine SDK package found after discovery."
  else
    printf '[dotnet] Debian package feed is not assumed; using the official installer.\n'
  fi
  mkdir -p /opt/dotnet
  curl -fsSL https://dot.net/v1/dotnet-install.sh -o /tmp/dotnet-install.sh
  chmod +x /tmp/dotnet-install.sh
  if install_scripted_sdk "10.0"; then
    log "dotnet 10 installed via official installer"
  else
    if [ -n "$EXISTING_DOTNET9" ]; then
      warn "dotnet 10 could not be downloaded; keeping existing dotnet $EXISTING_DOTNET9. No downgrade or major-version change was performed."
    else
      warn "dotnet 10 could not be installed for $ARCH. No SDK was changed."
      exit 1
    fi
  fi
fi

if [ -x /opt/dotnet/dotnet ]; then
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
