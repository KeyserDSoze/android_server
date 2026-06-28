#Requires -Version 5.1
# aserv-config-build.ps1 — Windows wrapper for aserv-config-build
#
# Usage (from the repository root):
#   .\bin\aserv-config-build.ps1 configsrc\blade20play.conf
#
# Produces: config\<CONFIG_NAME>.enc  (safe to commit to git)
# Decryption on Alpine: sh install.sh -> select profile -> enter password

param(
    [Parameter(Mandatory=$true)]
    [string]$SrcFile
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path $SrcFile)) { Write-Error "File not found: $SrcFile"; exit 1 }

# Read a KEY="value" line from the conf file
function Get-ConfValue([string]$file, [string]$key) {
    $line = Get-Content $file -Encoding UTF8 |
            Where-Object { $_ -match "^$key=" } |
            Select-Object -First 1
    if (-not $line) { return $null }
    ($line -replace "^$key=", '').Trim('"', "'", ' ')
}

$configName = Get-ConfValue $SrcFile 'CONFIG_NAME'
$configPass = Get-ConfValue $SrcFile 'CONFIG_PASSWORD'

if (-not $configName) { Write-Error "CONFIG_NAME not set in $SrcFile"; exit 1 }
if (-not $configPass) { Write-Error "CONFIG_PASSWORD not set in $SrcFile"; exit 1 }
if ($configPass -eq 'change_me_before_encrypting') {
    Write-Error "Set a real CONFIG_PASSWORD in $SrcFile before encrypting."
    exit 1
}

# Locate openssl — present in Git for Windows, WSL, or a standalone install
$candidates = @(
    'openssl',                                              # already in PATH
    'C:\Program Files\Git\usr\bin\openssl.exe',            # Git for Windows (64-bit)
    'C:\Program Files (x86)\Git\usr\bin\openssl.exe',      # Git for Windows (32-bit)
    'C:\OpenSSL-Win64\bin\openssl.exe',
    'C:\Program Files\OpenSSL-Win64\bin\openssl.exe'
)

$openssl = $null
foreach ($c in $candidates) {
    try {
        if ($c -eq 'openssl') {
            $null = & openssl version 2>&1
            if ($LASTEXITCODE -eq 0) { $openssl = 'openssl'; break }
        } elseif (Test-Path $c) {
            $openssl = $c; break
        }
    } catch { }
}

if (-not $openssl) {
    Write-Error @"
openssl not found. Options:
  1. Install Git for Windows (includes openssl): https://git-scm.com/
  2. Install OpenSSL for Windows: https://slproweb.com/products/Win32OpenSSL.html
  3. Run from Git Bash or WSL:  bash bin/aserv-config-build configsrc/blade20play.conf
"@
    exit 1
}

$root    = Split-Path -Parent $PSScriptRoot
$outDir  = Join-Path $root 'config'
$outFile = Join-Path $outDir "$configName.enc"
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

Write-Host ""
Write-Host ">> Source  : $SrcFile"          -ForegroundColor Green
Write-Host ">> Profile : $configName"        -ForegroundColor Green
Write-Host ">> Output  : config\$configName.enc" -ForegroundColor Green
Write-Host "   Encrypting with AES-256-CBC + PBKDF2 (600 000 iterations) ..."

& $openssl enc -aes-256-cbc -pbkdf2 -iter 600000 -salt `
    -in  $SrcFile `
    -out $outFile `
    -pass "pass:$configPass"

if ($LASTEXITCODE -ne 0) { Write-Error "Encryption failed (openssl exited $LASTEXITCODE)."; exit 1 }

Write-Host ""
Write-Host ">> Done." -ForegroundColor Green
Write-Host "   config\$configName.enc is encrypted and ready."
Write-Host ""
Write-Host "   Commit it to git:"
Write-Host "     git add config\$configName.enc"
Write-Host "     git commit -m 'Add encrypted config profile'"
Write-Host ""
Write-Host "   IMPORTANT: configsrc\ is gitignored — never commit it."
