# Android Server

Transform any Android smartphone into a persistent Linux development server using **Podroid**, **Alpine Linux**, **Cloudflare Tunnel**, **OpenChamber**, **OpenCode**, and a full developer toolchain.

Repository:

```sh
git clone https://github.com/KeyserDSoze/android_server.git
```

---

## Purpose

This project turns an Android phone into a micro Linux server that runs continuously.

The server can be used for:

- Software development
- Git repositories and GitHub workflows
- AI-assisted coding with OpenCode
- AI service hosting with OpenChamber
- Remote access via Cloudflare Tunnel
- SSH administration
- GitHub CLI, Azure CLI, .NET SDK, Node.js, Python
- Optional local LLM inference
- Optional Docker, Podman, LXC container workloads

---

## Architecture

```text
Android
└── Podroid
    └── Alpine Linux VM
        ├── OpenChamber
        ├── OpenCode
        ├── Cloudflare Tunnel
        ├── SSH
        ├── Git
        ├── GitHub CLI
        ├── Azure CLI
        ├── .NET SDK
        ├── Node.js
        ├── Python
        ├── Docker / Podman / LXC (optional)
        └── OpenRC services (autostart on boot)
```

---

## Android Requirements

Any Android smartphone with:

- ARM64 architecture
- Android 8.0 or higher
- 6 GB RAM or more (recommended)
- 20 GB free storage (recommended)
- Stable Wi-Fi connection

No root is required.
No bootloader unlock is required.
The existing Android installation is untouched.

---

## Required App: Podroid

Install Podroid from the official repository:

```
https://github.com/ExTV/Podroid
```

Download the APK from the **Releases** section and install it on the phone.

Podroid creates a real Alpine Linux VM on Android with a dedicated Linux kernel, which allows container runtimes, OpenRC services, and native SSH to work correctly.

---

## Recommended Podroid Configuration

Open Podroid and configure the VM with these settings:

```
RAM:      3 GB – 4 GB
CPU:      4 cores (if available)
Storage:  32 GB or more
SSH:      enabled
Downloads folder sharing: enabled
Backend:  QEMU TCG (AVF on supported Pixel devices)
```

---

## Android Power Management

To prevent Android from killing Podroid in the background:

1. Open Android **Settings** → **Battery**
2. Find **Podroid** and disable battery optimization
3. Allow background activity
4. Pin Podroid in recent apps (if supported by your device)

Recommended operating conditions:

```
Screen off
Phone connected to power
Stable Wi-Fi
No aggressive power-saving mode
```

---

## First VM Boot

Open Podroid, start the VM, and open the built-in terminal.

Update Alpine:

```sh
apk update && apk upgrade
apk add git
```

---

## Clone This Repository

Inside the Podroid VM terminal:

```sh
git clone https://github.com/KeyserDSoze/android_server.git
cd android_server
chmod +x install.sh
```

---

## Feature Configuration

Edit `aserv.yaml` to enable or disable components before installing:

```yaml
github: true
azure: true
cloudflare: true
opencode: true
openchamber: true
ssh: true
docker: false
podman: false
lxc: false
llm: false
tailscale: false
rclone: false
node: true
python: true
dotnet: true
devtools: true
aliases: true
services: true
```

---

## Secrets Configuration

Some components require credentials, tokens, or hostnames (Cloudflare, GitHub, Azure, Tailscale).

The project provides an **encrypted configuration profile** system:

1. Create a plaintext profile in `configsrc/` (gitignored, never committed)
2. Run `aserv-config-build` to encrypt it — output goes to `config/`
3. The encrypted file is safe to commit and push to GitHub
4. At install time, enter your password to decrypt and load all variables
5. Any variable still empty after loading is prompted interactively

```sh
# Create your profile from the template
mkdir -p configsrc
cp docs/config-template.conf configsrc/myprofile.conf

# Edit the file, fill in values, set CONFIG_PASSWORD
nano configsrc/myprofile.conf

# Encrypt it
aserv-config-build configsrc/myprofile.conf

# Commit the encrypted version
git add config/myprofile.enc && git commit -m "Add config profile"
```

See [docs/secrets-config.md](docs/secrets-config.md) for the full guide and variable reference.

If you skip this step, the installer will prompt for each value interactively.

---

## Installation

Run as root inside the Podroid Alpine VM:

```sh
sh install.sh
```

The installer will:

1. List available encrypted config profiles and offer to load one
2. Update Alpine packages
3. Install all enabled components from `aserv.yaml`
4. Configure git user (from profile or interactively)
5. Register OpenRC services for autostart
6. Create the workspace directory structure
7. Install `aserv-*` helper commands system-wide

---

## Post-Install: Cloudflare Tunnel

```sh
aserv-setup-cloudflare
```

You will be asked for (or values are loaded from your config profile):

- **Tunnel name** — a logical name for the tunnel
- **Public hostname** — e.g. `chamber.yourdomain.com`

The script configures the tunnel, DNS routing, `~/.cloudflared/config.yml`, and enables the `cloudflared` service at boot.

---

## Post-Install: Authentication

```sh
aserv-auth
```

Or manually:

```sh
gh auth login    # GitHub CLI
az login         # Azure CLI
```

Verify:

```sh
gh auth status
az account show
dotnet --info
```

---

## Automatic Services at Boot

OpenRC manages all persistent services. On VM boot these start automatically:

```
sshd
openchamber
cloudflared
tailscale   (if enabled)
docker      (if enabled)
```

Check status:

```sh
aserv-status
```

Restart all services:

```sh
aserv-restart
```

View logs:

```sh
aserv-logs openchamber
aserv-logs cloudflared
```

---

## Directory Structure

The installer creates:

```
~/projects    ← Git projects and source code
~/models      ← local LLM models (.gguf files)
~/logs        ← service log files
~/scripts     ← custom automation scripts
~/backup      ← backups
```

---

## Helper Commands

```sh
aserv-status              # system and service overview
aserv-update              # update all components
aserv-restart             # restart all services
aserv-logs <service>      # tail service logs
aserv-auth                # authenticate GitHub and Azure
aserv-setup-cloudflare    # configure Cloudflare Tunnel
aserv-config-build        # encrypt a config profile
aserv-llm-install         # install local LLM tools
```

---

## Update

Update all installed components:

```sh
aserv-update
```

Updates: Alpine packages, npm globals, Azure CLI, GitHub CLI extensions.

---

## Remote Access

### SSH

```sh
ssh root@<phone-ip> -p 22
```

### Cloudflare Tunnel

After setup, access OpenChamber at:

```
https://chamber.yourdomain.com
```

---

## Using OpenCode

```sh
cd ~/projects
git clone https://github.com/user/project.git
cd project
opencode
```

---

## Using OpenChamber

OpenChamber runs as a background service.

Check locally:

```sh
curl http://127.0.0.1:3210
```

Or access through the Cloudflare Tunnel at your configured hostname.

---

## Container Workloads (Docker / Podman / LXC)

Because Podroid provides a dedicated Linux kernel, container runtimes work correctly inside the VM. Enable them in `aserv.yaml` before installing:

```yaml
docker: true
podman: true
lxc: true
```

---

## Azure CLI Notes

Azure CLI is installed via Python/pip in a virtualenv at `/opt/azcli`. If native installation fails, the `az` wrapper automatically falls back to a Docker-based image.

```sh
az version
az login
```

---

## .NET SDK Notes

The installer tries the latest available `dotnet*-sdk` package from Alpine repos and falls back to the official `dotnet-install.sh` script.

```sh
dotnet --info
dotnet new console -o ~/projects/test && cd ~/projects/test && dotnet run
```

---

## Security Recommendations

- Use a strong passphrase for your config profile
- Do not expose SSH directly to the Internet — use Cloudflare Tunnel or Tailscale
- Enable Cloudflare Access on your public domain for additional auth
- Keep packages updated with `aserv-update`
- Never commit secrets to a repository — use the encrypted profile system

---

## Troubleshooting

### Tunnel does not start

```sh
cloudflared tunnel list
rc-service cloudflared status
aserv-logs cloudflared
```

### OpenChamber not responding

```sh
rc-service openchamber status
curl http://127.0.0.1:3210
aserv-logs openchamber
```

### Azure CLI not working

```sh
az version
python3 --version
aserv-update
```

### GitHub CLI not authenticated

```sh
gh auth login
gh auth status
```

---

## Quick Start (TL;DR)

```sh
apk update && apk add git
git clone https://github.com/KeyserDSoze/android_server.git
cd android_server
chmod +x install.sh
sh install.sh
aserv-setup-cloudflare
aserv-auth
aserv-status
```
