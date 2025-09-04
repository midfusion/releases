#!/usr/bin/env bash
set -euo pipefail

# Midfusion installer that works with both public and private repositories
# Usage:
#   For private repos (requires gh CLI): curl -fsSL https://raw.githubusercontent.com/midfusion/releases/main/.github/scripts/install.sh | bash
#   For public repos: curl -fsSL https://github.com/midfusion/releases/releases/latest/download/install.sh | sudo bash
#   Specific version: curl -fsSL https://raw.githubusercontent.com/midfusion/releases/main/.github/scripts/install.sh | bash -s -- v0.1.0

REPO="midfusion/releases"
VERSION="${1:-}"
USE_SUDO="${SUDO:-auto}"

# Check if we can use GitHub CLI (for private repos)
if command -v gh >/dev/null 2>&1; then
  USE_GH_CLI=1
  echo "✓ GitHub CLI detected - using for private repository access"
else
  USE_GH_CLI=0
  echo "ℹ GitHub CLI not found - attempting public repository access"
fi

# Get version
if [[ -z "${VERSION}" ]]; then
  if [[ "${USE_GH_CLI}" == "1" ]]; then
    VERSION=$(gh release list --repo "${REPO}" --limit 1 | head -n1 | cut -f1)
  else
    if command -v jq >/dev/null 2>&1; then
      VERSION=$(curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest" | jq -r .tag_name)
    else
      VERSION=$(curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest" | sed -n 's/.*"tag_name"\s*:\s*"\([^"]*\)".*/\1/p')
    fi
  fi
fi

OS=$(uname | tr '[:upper:]' '[:lower:]')
ARCH=$(uname -m)
case "${ARCH}" in
  x86_64|amd64) ARCH=amd64 ;;
  aarch64|arm64) ARCH=arm64 ;;
  *) echo "Unsupported arch: ${ARCH}" >&2; exit 1 ;;
esac

ARCHIVE="midfusion-${OS}-${ARCH}.gz"
tmpdir=$(mktemp -d)
trap 'rm -rf "${tmpdir}"' EXIT

echo "Installing midfusion ${VERSION} for ${OS}/${ARCH}"

# Download using appropriate method
if [[ "${USE_GH_CLI}" == "1" ]]; then
  echo "Downloading via GitHub CLI..."
  cd "${tmpdir}"
  gh release download "${VERSION}" --repo "${REPO}" --pattern "${ARCHIVE}" 2>/dev/null || {
    echo "❌ Failed to download. Make sure you're authenticated with 'gh auth login'"
    exit 1
  }
else
  URL="https://github.com/${REPO}/releases/download/${VERSION}/${ARCHIVE}"
  echo "Downloading: ${URL}"
  curl -fsSL "${URL}" -o "${tmpdir}/${ARCHIVE}" || {
    echo "❌ Failed to download. Repository might be private - install GitHub CLI and run 'gh auth login'"
    exit 1
  }
fi

# Extract and prepare binary
echo "Extracting binary..."
gunzip -c "${tmpdir}/${ARCHIVE}" > "${tmpdir}/midfusion-${OS}-${ARCH}"
chmod +x "${tmpdir}/midfusion-${OS}-${ARCH}"

# Determine if we need sudo
INSTALL_DIR="/usr/local/bin"
if [[ "${USE_SUDO}" == "auto" ]]; then
  if [[ -w "${INSTALL_DIR}" ]]; then
    USE_SUDO=""
  else
    USE_SUDO="sudo"
    echo "🔐 Installing to ${INSTALL_DIR} (requires sudo)"
  fi
elif [[ "${USE_SUDO}" == "true" ]]; then
  USE_SUDO="sudo"
fi

# Install binary
echo "Installing midfusion..."
${USE_SUDO} install -m 0755 "${tmpdir}/midfusion-${OS}-${ARCH}" "${INSTALL_DIR}/midfusion"
${USE_SUDO} ln -sf "${INSTALL_DIR}/midfusion" "${INSTALL_DIR}/mf" 2>/dev/null || true

# Verify installation
if command -v midfusion >/dev/null 2>&1; then
  VERSION_OUTPUT=$(midfusion --version 2>/dev/null || echo "midfusion")
  echo "✅ Successfully installed: ${VERSION_OUTPUT}"
  echo "💡 You can now use 'midfusion' or 'mf' commands"
else
  echo "⚠️  Installation completed but 'midfusion' not found in PATH"
  echo "   Make sure ${INSTALL_DIR} is in your PATH"
fi

echo "🎉 Installation complete!"


