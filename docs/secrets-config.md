# Secrets Configuration

Blade Server uses an **encrypted configuration profile** system to manage secrets safely across installations.

---

## Overview

Sensitive values — tokens, hostnames, passwords, API keys — live in a plaintext `.conf` file inside `configsrc/`.

That folder is **gitignored** and never reaches the remote repository.

When ready, `aserv-config-build` encrypts the file using **AES-256-CBC with PBKDF2** key derivation and saves the encrypted output to `config/`.

The encrypted `config/*.enc` file **can be committed to git**. Without the correct password it is unreadable.

At install time, `install.sh` detects available profiles in `config/`, asks which one to use, prompts for the decryption password, and loads all variables into the install session. Any variable that is still empty after loading is prompted for interactively.

---

## Workflow

```
configsrc/myprofile.conf         <- plaintext secrets, gitignored
         |
         |  aserv-config-build configsrc/myprofile.conf
         v
config/myprofile.enc             <- encrypted, safe to commit to git
         |
         |  sh install.sh
         |  (choose profile -> type password)
         v
variables loaded into install session
(empty variables prompted interactively)
```

---

## Step 1 — Create the configsrc folder

```sh
mkdir -p configsrc
```

---

## Step 2 — Create your profile

Copy the template:

```sh
cp docs/config-template.conf configsrc/myprofile.conf
```

Edit `configsrc/myprofile.conf`:

- Set `CONFIG_NAME` to your profile name (this becomes the filename in `config/`)
- Set `CONFIG_PASSWORD` to a strong passphrase — you must type it every time you run `install.sh`
- Fill in any values you want pre-loaded; leave optional ones empty if you prefer to be prompted

---

## Step 3 — Encrypt the profile

```sh
aserv-config-build configsrc/myprofile.conf
```

This reads `CONFIG_NAME` and `CONFIG_PASSWORD` from your file, then encrypts the entire file and writes:

```
config/myprofile.enc
```

---

## Step 4 — Commit the encrypted profile

```sh
git add config/myprofile.enc
git commit -m "Add encrypted config profile"
git push
```

---

## Step 5 — Use at install time

On a fresh installation, after cloning the repository:

```sh
sh install.sh
```

The installer will:
1. List all `config/*.enc` profiles found in the repository
2. Ask which one to use (or offer to skip and enter values manually)
3. Prompt for the decryption password
4. Decrypt and load all variables into the install session
5. For any variable that is still empty, prompt interactively

---

## Available Variables

| Variable | Description | Default |
|---|---|---|
| `CONFIG_NAME` | Profile name — also the output filename | *(required)* |
| `CONFIG_PASSWORD` | Encryption passphrase (build-time only, never stored) | *(required)* |
| `GIT_USER_NAME` | Global `git config user.name` | prompted if empty |
| `GIT_USER_EMAIL` | Global `git config user.email` | prompted if empty |
| `GITHUB_TOKEN` | GitHub Personal Access Token | optional |
| `CLOUDFLARE_TUNNEL_NAME` | Cloudflare tunnel name | optional |
| `CLOUDFLARE_HOSTNAME` | Public hostname through Cloudflare | optional |
| `AZURE_SUBSCRIPTION_ID` | Default Azure subscription ID | optional |
| `SSH_PORT` | SSH port | `22` |
| `OPENCHAMBER_PORT` | OpenChamber local port | `3210` |
| `TAILSCALE_AUTH_KEY` | Tailscale pre-auth key | optional |

---

## Re-encrypting After Changes

If you update `configsrc/myprofile.conf`, run `aserv-config-build` again:

```sh
aserv-config-build configsrc/myprofile.conf
```

Then commit the updated `.enc` file:

```sh
git add config/myprofile.enc
git commit -m "Update encrypted config profile"
```

---

## Security Notes

- `configsrc/` is in `.gitignore` — never commit plaintext secrets
- Encryption uses AES-256-CBC with 600 000 PBKDF2 iterations and a random salt
- `CONFIG_PASSWORD` is never stored anywhere — only you know it
- `config/*.enc` encrypted files are safe to publish on a public GitHub repository
- Use a strong, unique passphrase for each profile

---

## Without a Config Profile

If you skip the profile selection at install time, `install.sh` will prompt for each required value interactively. A config profile is optional, not mandatory.
