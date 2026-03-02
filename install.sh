#!/usr/bin/env bash
# KwaaiNet one-command installer (cargo-dist generated, shell variant)
#
# Usage:
#   curl --proto '=https' --tlsv1.2 -LsSf \
#     https://github.com/Kwaai-AI-Lab/KwaaiNet/releases/latest/download/kwaainet-installer.sh | sh
#
# This script is a convenience wrapper.  The canonical installer is the
# cargo-dist-generated kwaainet-installer.sh that is uploaded as a release
# asset on every release.  It handles all platform detection, checksum
# verification, and PATH setup automatically.

set -euo pipefail

REPO="Kwaai-AI-Lab/KwaaiNet"

# ── Clean up old manual installs (pre-v0.1.5) ────────────────────────────────
# Before v0.1.5, the install instructions used `tar | sudo mv` which placed
# binaries in /usr/local/bin.  Remove them so they don't shadow the new
# cargo-dist install in ~/.cargo/bin.
for old_bin in /usr/local/bin/kwaainet /usr/local/bin/p2pd; do
  if [ -f "${old_bin}" ]; then
    echo "Removing old install: ${old_bin}"
    if sudo rm -f "${old_bin}" 2>/dev/null; then
      echo "  removed ${old_bin}"
    else
      echo "  Warning: could not remove ${old_bin} — run: sudo rm -f ${old_bin}"
    fi
  fi
done

# Warn if a Homebrew-managed copy exists — it will shadow ~/.cargo/bin.
if command -v brew >/dev/null 2>&1 && brew list kwaainet >/dev/null 2>&1; then
  echo ""
  echo "Note: kwaainet is also installed via Homebrew."
  echo "  To avoid PATH conflicts, run: brew uninstall kwaainet"
  echo "  Or upgrade instead:          brew upgrade kwaainet"
  echo ""
fi

# ── Resolve the latest release tag ───────────────────────────────────────────
# (avoids stale CDN caches on /releases/latest)
VERSION=$(curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest" \
  | grep '"tag_name"' | head -1 | sed 's/.*"tag_name": *"\([^"]*\)".*/\1/')
if [ -z "${VERSION}" ]; then
  echo "Error: could not determine latest release version from GitHub API." >&2
  exit 1
fi

INSTALLER_URL="https://github.com/${REPO}/releases/download/${VERSION}/kwaainet-installer.sh"
echo "Installing KwaaiNet ${VERSION} ..."
curl --proto '=https' --tlsv1.2 -LsSf "${INSTALLER_URL}" | sh
