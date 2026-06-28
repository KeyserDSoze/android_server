#!/bin/sh
set -eu

apk add --no-cache python3 py3-pip py3-virtualenv gcc musl-dev python3-dev libffi-dev openssl-dev cargo rust || true
python3 -m venv /opt/azcli
. /opt/azcli/bin/activate
pip install --upgrade pip setuptools wheel
if pip install azure-cli; then
  ln -sf /opt/azcli/bin/az /usr/local/bin/az-native
fi

cat > /usr/local/bin/az <<'AZEOF'
#!/bin/sh
if command -v az-native >/dev/null 2>&1; then
  exec az-native "$@"
fi
if command -v docker >/dev/null 2>&1; then
  exec docker run --rm -it \
    -v "$HOME/.azure:/root/.azure" \
    -v "$PWD:/work" -w /work \
    mcr.microsoft.com/azure-cli az "$@"
fi
echo "Azure CLI non disponibile. Installa azure-cli nativo oppure abilita Docker in Podroid." >&2
exit 1
AZEOF
chmod +x /usr/local/bin/az
