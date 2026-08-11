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

Cloudflared provides an ARM binary fallback for ARMv7 systems. OpenCode and OpenChamber availability depends on the Node.js/npm packages and architecture; the installer reports any component that cannot be installed.

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

Updates: Alpine packages, npm globals, Azure CLI, GitHub CLI extensions.

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

The installer performs a discovery pass for the distribution, CPU architecture, existing SDKs, and available Alpine packages. It prefers .NET 10. On Debian-based systems and ARM32, it uses the official `dotnet-install.sh` script; .NET 9 is used only as an explicit fallback when the .NET 10 SDK cannot be installed for the detected architecture.

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
