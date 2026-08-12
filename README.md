# Android Server

Transform any Android smartphone, Raspberry Pi, or Linux server into a persistent Linux development server using **Cloudflare Tunnel**, **OpenChamber**, **OpenCode**, and a full developer toolchain.

Repository:

```sh
git clone https://github.com/KeyserDSoze/android_server.git
```

---

## Supported Platforms

| Platform | Init system | Package manager | Status |
|---|---|---|---|
| Android + Podroid (Alpine Linux) | OpenRC | apk | Fully supported |
| Raspberry Pi OS (Debian) | systemd | apt | Supported |
| Ubuntu Server 22.04 / 24.04 | systemd | apt | Fully supported |
| Debian 12+ | systemd | apt | Supported |
| Other Debian-based Linux distributions | systemd | apt | Best effort |

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

### Android + Podroid (Alpine)

```text
Android
└── Podroid
    └── Alpine Linux VM
        ├── OpenChamber
        ├── OpenCode
        ├── Cloudflare Tunnel
        ├── SSH
        ├── Git, GitHub CLI, Azure CLI, .NET SDK, Node.js, Python
        ├── Docker / Podman / LXC (optional)
        └── OpenRC services (autostart on boot)
```

### Ubuntu Server / Debian

```text
Ubuntu Server
├── OpenChamber
├── OpenCode
├── Cloudflare Tunnel (cloudflared → systemd)
├── SSH
├── Git, GitHub CLI, Azure CLI, .NET SDK, Node.js, Python
├── Docker / Podman / LXC (optional)
└── systemd services (autostart on boot)
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

## Raspberry Pi OS Requirements

Raspberry Pi OS **64-bit or 32-bit** can run the Debian branch of the installer. For a Raspberry Pi 2, use a lightweight Raspberry Pi OS installation and expect slower package and npm builds.

- Raspberry Pi OS Lite recommended
- Raspberry Pi 2 or newer
- At least 1 GB free RAM and 8 GB free disk space; more is recommended
- Internet connection
- A user with `sudo` access, or a root shell

Cloudflared provides an ARM binary fallback for ARMv7 systems. OpenChamber can run through Node.js on ARMv7, subject to its package dependencies. The official OpenCode releases currently publish Linux binaries for x64 and ARM64, not ARMv7; on a Raspberry Pi 2 the installer reports OpenCode as unsupported instead of attempting an invalid npm package.

## Ubuntu Server / Debian Requirements

Any machine (physical, VM, VPS, mini PC) with:

- Ubuntu 22.04 LTS / 24.04 LTS (or Debian 12+)
- x86_64 or ARM64 architecture
- 2 GB RAM minimum (4 GB recommended)
- 20 GB free disk
- Internet connection

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

## First VM Boot (Android/Alpine)

Open Podroid, start the VM, and open the built-in terminal.

Update Alpine:

```sh
apk update && apk upgrade
apk add git
```

---

## Clone This Repository

Run the commands for the Linux distribution installed on the machine. Git must be installed before cloning the repository.

### Raspberry Pi OS, Ubuntu, Debian, and other Debian-based distributions

```sh
sudo apt-get update
sudo apt-get install -y git ca-certificates curl openssl
git clone https://github.com/KeyserDSoze/android_server.git
cd android_server
```

If `sudo` is not installed, become root first and omit `sudo`:

```sh
su -
apt-get update
apt-get install -y git ca-certificates curl openssl
git clone https://github.com/KeyserDSoze/android_server.git
cd android_server
```

### Alpine Linux

```sh
apk update
apk add git ca-certificates curl openssl
git clone https://github.com/KeyserDSoze/android_server.git
cd android_server
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
codex: true
codex_proxy: true
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

### Using an existing encrypted profile

If a profile such as `config/raspi.enc`, `config/nipogi.enc`, or `config/blade20play.enc` is already present in the repository, do not copy the plaintext file to the server. Start the installer and select the profile when it displays the list:

```sh
# Debian-based systems, including Raspberry Pi OS
sudo bash install.sh

# Alpine Linux, as root
sh install.sh
```

The installer then:

1. Shows the available files in `config/*.enc`
2. Asks which profile to load
3. Requests the `CONFIG_PASSWORD` used to create that profile
4. Decrypts the profile only in a temporary file
5. Loads its values and prompts only for variables that are still empty

The password requested here is the encryption password, not the Cloudflare token or the OpenCode/OpenChamber UI password. If the password is wrong, the installer stops with a decryption error. Choose `0` when you want to skip the profile and enter values manually.

The Codex proxy hostname is intentionally not given a default. Set `CLOUDFLARE_CODEX_HOSTNAME` in the profile when `codex_proxy` is enabled. The proxy API key is configured separately with `CODEX_PROXY_API_KEY`; it protects incoming API requests and is not the same as the Codex OAuth session in `~/.codex/auth.json`.

---

## Installation by Linux Distribution

`install.sh` detects the OS automatically and uses the correct package manager and init system.

### Raspberry Pi OS

Raspberry Pi OS uses the Debian/systemd branch. From the cloned repository:

```sh
sudo bash install.sh
```

When prompted, select `raspi` and enter the password used to create `config/raspi.enc`. The profile supplies the configured Cloudflare hostnames, tunnel token, ports, and service passwords. The installer continues with package installation and service setup.

### Ubuntu Server and Debian

These distributions use the same Debian/systemd branch:

```sh
sudo bash install.sh
```

Select the matching `.enc` profile when prompted, or choose `0` to configure values interactively.

### Alpine Linux (including Android/Alpine inside Podroid)

```sh
sh install.sh
```

Run it from a root shell. Alpine uses `apk` and OpenRC instead of `apt` and systemd.

Select the matching encrypted profile and enter its encryption password when prompted.

### Other Linux distributions

The installer has explicit support for Alpine and Debian/Ubuntu. Other distributions are not automatically guaranteed because package names, init systems, and OS detection can differ. Check the system before installing:

```sh
cat /etc/os-release
uname -m
```

If the distribution is not Debian-based or Alpine, use a supported base distribution or adapt the package and service commands before running the installer.

### What happens after starting the installer

At the start of the installer you can choose:

- `A` / `All`: use every component enabled with `true` in `aserv.yaml`
- `C` / `Choose`: answer `Y` or `N` for each component for this run only

The interactive choice does not edit `aserv.yaml`. It is useful when the same repository profile is shared by machines with different hardware, such as a Raspberry Pi and a larger server.

The installer will:

1. Detect the OS and select the package manager (`apk` or `apt-get`)
2. List available encrypted config profiles and offer to load one
3. Request the profile password and decrypt the selected `.enc` file temporarily
4. Update packages (`apk` or `apt-get`)
5. Install all enabled components from `aserv.yaml`
6. Configure git user (from profile or interactively)
7. Register services for autostart (OpenRC on Alpine, systemd on Debian-based systems)
8. Create the workspace directory structure
9. Install `aserv-*` helper commands system-wide
10. Restart all managed services at the end, including Cloudflare and the Codex proxy when configured

**Debian-based behaviour, including Raspberry Pi OS:**
- Node.js 22 LTS installed via NodeSource
- GitHub CLI installed via official apt repository
- cloudflared installed via Cloudflare apt repository
- `cloudflared service install <token>` configures systemd automatically
- Services managed via `systemctl` (openchamber, opencode)
- Config written to `/etc/default/` instead of `/etc/conf.d/`

**Alpine behaviour:**
- Packages installed with `apk`
- Services managed with OpenRC
- Config written to `/etc/conf.d/`
- A token-based Cloudflare profile is saved to `/etc/aserv/cloudflare-token`

---

## Codex CLI and OpenAI-Compatible Proxy

Codex and the proxy are separate components:

```text
Client / SDK
    |
    v
openai-api-server-via-codex :22000
    |
    v
Codex CLI + ~/.codex/auth.json
    |
    v
OpenAI Codex backend
```

Enable both features in `aserv.yaml`:

```yaml
codex: true
codex_proxy: true
```

Configure these values in the encrypted profile:

```sh
CLOUDFLARE_CODEX_HOSTNAME="codex.example.com"
CODEX_PROXY_PORT="22000"
CODEX_PROXY_API_KEY="replace-with-a-long-random-api-key"
```

`CLOUDFLARE_CODEX_HOSTNAME` has no default and must be set explicitly. For a dashboard-managed Cloudflare Tunnel, add a Public Hostname manually:

```text
Hostname: codex.example.com
Service:  HTTP
URL:      http://127.0.0.1:22000
```

For a locally managed tunnel, `aserv-setup-cloudflare` adds the configured Codex hostname automatically.

The installer installs Codex CLI and `openai-api-server-via-codex` independently. A Codex CLI download failure does not skip the proxy installation; the proxy is installed whenever `uv` and Python package installation succeed. The installer never performs an OAuth login automatically. After installation, authenticate Codex as root, because the system service reads `/root/.codex/auth.json`:

```sh
sudo -i
export PATH="/usr/local/bin:/root/.local/bin:$PATH"
codex --version
codex login
# On a headless server:
codex login --device-auth
```

The installer places the canonical CLI at `/usr/local/bin/codex` and configures that path for the account running the installer. On a system service installation this is normally `root`, regardless of whether the distribution uses systemd or OpenRC. If a new shell still reports `codex: command not found`, check the installation directly:

```sh
sudo ls -l /usr/local/bin/codex /root/.local/bin/codex
sudo /usr/local/bin/codex --version
```

### Slow or unstable network during Codex installation

The official Codex installer downloads an architecture-specific archive. Its asset download timeout is 300 seconds, so a congested connection can fail even when the machine has internet access. The Android/Linux Server wrapper retries the installation up to three times, using the OpenAI release endpoint first and GitHub Releases as a fallback.

If the complete installer has already finished but Codex failed, retry only the Codex module as root:

```sh
cd ~/android_server
sudo sh modules/codex.sh
```

You can also test the connection and check the detected architecture before retrying:

```sh
uname -m
curl -I https://releases.openai.com/codex/install.sh
curl -I https://github.com/anomalyco/opencode
```

At 5 Mb/s, a roughly 12 MB archive should normally download well within five minutes. If the transfer repeatedly stalls, retry during a less congested period or temporarily use another connection. A timeout while downloading Codex does not indicate an OAuth or proxy configuration error; those steps happen only after the CLI is installed.

The Codex CLI installer is distribution-independent and supports Linux x64 and ARM64. It does not currently provide an official ARMv7/ARM32 binary, so a Raspberry Pi 2 may run the proxy component but cannot run the official Codex CLI. Ubuntu Server, Debian, Alpine, and other Linux distributions can use the same Codex module when their architecture is x64 or ARM64.

Verify the session and proxy:

```sh
ls -la ~/.codex/auth.json
codex --version
codex exec "scrivi solo OK"
curl -H "Authorization: Bearer $CODEX_PROXY_API_KEY" \
  "http://127.0.0.1:22000/healthz"
aserv-status
```

The proxy service is enabled for automatic startup and is restarted at the end of installation/update. It starts successfully only when `CODEX_PROXY_API_KEY`, `~/.codex/auth.json`, and a working Codex CLI are present. If the Codex token is missing, expired, or cannot be refreshed, the proxy refuses to bind or exits; re-run `codex login` manually and restart it:

```sh
# Debian/Raspberry Pi OS
sudo systemctl restart codex-proxy

# Alpine Linux
rc-service codex-proxy restart
```

The API key used by clients is the value configured in `CODEX_PROXY_API_KEY`:

```sh
export OPENAI_BASE_URL="https://codex.example.com/v1"
export OPENAI_API_KEY="replace-with-a-long-random-api-key"
```

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

### Alpine (OpenRC)

On VM boot these start automatically:

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
# or
rc-service openchamber status
rc-service cloudflared status
```

### Ubuntu (systemd)

On boot these start automatically:

```
sshd
openchamber
cloudflared   (managed by cloudflared itself via systemctl)
opencode
```

Check status:

```sh
aserv-status
# or
systemctl status openchamber
systemctl status cloudflared
systemctl status opencode
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

At the start of `aserv-update` you can choose:

- `A` / `All`: update every supported component
- `C` / `Choose`: answer `Y` or `N` for system packages, Node/npm, OpenChamber, OpenCode, Codex, the Codex proxy, Azure CLI, GitHub CLI, Cloudflare, .NET, Tailscale, and Rclone

The update selection also applies only to the current run. After the selected updates finish, the command performs a final best-effort restart of all enabled services, including `cloudflared` and `codex-proxy`.

Updates can include Alpine/Debian packages, npm globals, Azure CLI, GitHub CLI extensions, Cloudflare, .NET, Codex CLI, and the Codex proxy.

---

## Remote Access

### SSH — Direct (local network only)

```sh
ssh root@<server-ip> -p 22
```

---

### SSH — Via Cloudflare Tunnel (recommended, works from anywhere)

SSH through Cloudflare requires **cloudflared installed on your client PC** and a one-time SSH config entry.

#### 1. Install cloudflared on your PC

- **Windows**: download from https://github.com/cloudflare/cloudflared/releases (`.exe`)
- **macOS**: `brew install cloudflared`
- **Linux**: `apt-get install cloudflared` (via Cloudflare apt repo)

#### 2. Edit your SSH config file

| OS | File location |
|---|---|
| Windows | `C:\Users\<yourname>\.ssh\config` |
| macOS / Linux | `~/.ssh/config` |

Create the file if it doesn't exist, then add:

```
Host ssh.yourdomain.com
    HostName ssh.yourdomain.com
    ProxyCommand cloudflared access ssh --hostname %h
    User root
```

Replace `ssh.yourdomain.com` with your actual SSH hostname (e.g. `ssh3.opencode.zone`) and `root` with the actual username on the server.

**On Windows**, create or edit the file in PowerShell:

```powershell
notepad "$env:USERPROFILE\.ssh\config"
```

If the `.ssh` folder doesn't exist:

```powershell
New-Item -ItemType Directory -Force "$env:USERPROFILE\.ssh"
notepad "$env:USERPROFILE\.ssh\config"
```

#### 3. Connect

```sh
ssh ssh.yourdomain.com
```

Cloudflare will authenticate you (browser popup on first access if Cloudflare Access is enabled) and proxy the connection to the server.

---

### Cloudflare Tunnel — OpenChamber

After setup, access OpenChamber at:

```
https://chamber.yourdomain.com
```


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

The installer performs a discovery pass for the distribution, CPU architecture, existing SDKs, and the .NET 10 package/download source. If any .NET 10 SDK is already installed, it keeps that version and does not download a newer patch automatically. If a .NET 10 download fails, an existing .NET 9 SDK is kept unchanged; the installer never downgrades or updates .NET 9 as a fallback.

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
# Alpine
rc-service cloudflared status
aserv-logs cloudflared

# Ubuntu
systemctl status cloudflared
journalctl -u cloudflared -n 50
```

### OpenChamber not responding

```sh
# Alpine
rc-service openchamber status
curl http://127.0.0.1:3210
aserv-logs openchamber

# Ubuntu
systemctl status openchamber
journalctl -u openchamber -n 50
curl http://127.0.0.1:3210
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

## Quick Start — Android / Alpine (TL;DR)

```sh
apk update && apk add git
git clone https://github.com/KeyserDSoze/android_server.git
cd android_server
sh install.sh
# Select the matching .enc profile and enter its encryption password
aserv-setup-cloudflare
aserv-auth
aserv-status
```

## Quick Start — Raspberry Pi OS (TL;DR)

```sh
sudo apt-get update
sudo apt-get install -y git ca-certificates curl openssl
git clone https://github.com/KeyserDSoze/android_server.git
cd android_server
sudo bash install.sh
# Select raspi and enter the password for config/raspi.enc
aserv-auth
aserv-status
```

## Quick Start — Ubuntu Server / Debian (TL;DR)

```sh
apt-get update && apt-get install -y git ca-certificates curl openssl
git clone https://github.com/KeyserDSoze/android_server.git
cd android_server
sudo bash install.sh
# Select the matching .enc profile and enter its encryption password
aserv-auth
aserv-status
```
