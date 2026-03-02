# KwaaiNet Windows installer (cargo-dist generated, PowerShell variant)
#
# Usage:
#   irm https://github.com/Kwaai-AI-Lab/KwaaiNet/releases/latest/download/kwaainet-installer.ps1 | iex
#
# This script is a convenience wrapper.  The canonical installer is the
# cargo-dist-generated kwaainet-installer.ps1 that is uploaded as a release
# asset on every release.  It handles checksum verification and PATH setup.

$ErrorActionPreference = "Stop"

$repo = "Kwaai-AI-Lab/KwaaiNet"

# ── Clean up old manual installs (pre-v0.1.5) ────────────────────────────────
# Before v0.1.5, the Windows installer placed binaries in
# $env:LOCALAPPDATA\Programs\kwaainet.  Remove them so they don't shadow the
# new cargo-dist install in ~/.cargo/bin.
$oldDir = Join-Path $env:LOCALAPPDATA "Programs\kwaainet"
if (Test-Path $oldDir) {
    Write-Host "Removing old install: $oldDir" -ForegroundColor Yellow
    try {
        Remove-Item -Recurse -Force $oldDir
        Write-Host "  removed $oldDir"
    } catch {
        Write-Host "  Warning: could not remove $oldDir — delete it manually." -ForegroundColor Yellow
    }
}

# ── Resolve the latest release tag ───────────────────────────────────────────
# (avoids stale CDN caches on /releases/latest)
$version = (Invoke-RestMethod "https://api.github.com/repos/$repo/releases/latest").tag_name
Write-Host "Installing KwaaiNet $version ..." -ForegroundColor Cyan

$installerUrl = "https://github.com/$repo/releases/download/$version/kwaainet-installer.ps1"
Invoke-Expression (Invoke-RestMethod $installerUrl)
