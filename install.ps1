# KwaaiNet Windows installer
# Usage: irm https://raw.githubusercontent.com/Kwaai-AI-Lab/KwaaiNet/main/install.ps1 | iex

$ErrorActionPreference = "Stop"

$repo    = "Kwaai-AI-Lab/KwaaiNet"
$asset   = "kwaainet-x86_64-pc-windows-msvc.zip"
$url     = "https://github.com/$repo/releases/latest/download/$asset"
$zip     = "$env:TEMP\kwaainet-install.zip"
$dst     = "$env:LOCALAPPDATA\kwaainet"

Write-Host "Downloading KwaaiNet..." -ForegroundColor Cyan
Invoke-WebRequest -Uri $url -OutFile $zip

Write-Host "Installing to $dst ..." -ForegroundColor Cyan
if (Test-Path $dst) { Remove-Item $dst -Recurse -Force }
Expand-Archive $zip $dst -Force
Remove-Item $zip

# Add to PATH for this session
if ($env:Path -notlike "*$dst*") {
    $env:Path += ";$dst"
}

# Persist to user PATH
$userPath = [Environment]::GetEnvironmentVariable("Path", "User")
if ($userPath -notlike "*$dst*") {
    [Environment]::SetEnvironmentVariable("Path", "$userPath;$dst", "User")
    Write-Host "Added $dst to your PATH (restart terminal to take effect in new windows)" -ForegroundColor Yellow
}

Write-Host "Running kwaainet setup..." -ForegroundColor Cyan
kwaainet setup

Write-Host ""
Write-Host "KwaaiNet installed successfully." -ForegroundColor Green
Write-Host "Run 'kwaainet start --daemon' to join the network." -ForegroundColor Green
