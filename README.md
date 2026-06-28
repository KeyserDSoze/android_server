# Blade Server Edition

Bootstrap completo per usare un telefono Android con Podroid come micro server Linux Alpine.

## Feature abilitate in `blade.yaml`

Tutto è impostato a `true`: GitHub CLI, Azure CLI, Cloudflare Tunnel, OpenCode, OpenChamber, SSH, Docker, Podman, LXC, llama.cpp helper, Tailscale, rclone, Node, Python, devtools, alias e servizi OpenRC.

## Installazione dentro Podroid

```sh
apk add git
# oppure carica questa cartella via ZIP
cd blade-server
sh install.sh
```

## Dopo l'installazione

```sh
blade-setup-cloudflare
blade-auth
blade-status
```

## Azure CLI

Lo script prova a installare Azure CLI nativa in `/opt/azcli` e crea il comando `az`.
Se l'installazione nativa fallisce, il wrapper `az` usa Docker con l'immagine ufficiale `mcr.microsoft.com/azure-cli`, se Docker è disponibile.

## OpenChamber

Il servizio ascolta su `127.0.0.1:3210` ed è esposto tramite Cloudflare Tunnel.
Cambia la password prima di esporlo: modifica `/etc/init.d/openchamber` oppure esporta `OPENCHAMBER_PASSWORD` nel servizio.

## Comandi utili

```sh
blade-status
blade-update
blade-restart
blade-logs openchamber
blade-logs cloudflared
blade-llm-install
```

## Progetti

Usa `/root/projects`:

```sh
cd /root/projects
gh repo clone TUO_UTENTE/TUO_REPO
cd TUO_REPO
opencode
```


## .NET SDK

Il bootstrap installa anche il .NET SDK quando `dotnet: true` è presente in `blade.yaml`.
Su Alpine prova prima i pacchetti ufficiali `dotnet10-sdk`, `dotnet9-sdk`, `dotnet8-sdk`; se non sono disponibili usa `dotnet-install.sh`.

Verifica con:

```sh
dotnet --info
dotnet new webapi -n TestApi
cd TestApi
dotnet run --urls http://0.0.0.0:5000
```
