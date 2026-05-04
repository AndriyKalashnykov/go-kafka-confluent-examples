#!/usr/bin/env bash
# Install kind + kubectl into ~/.local/bin so the e2e harness has the
# tools available locally and inside CI runners (the GitHub Actions
# ubuntu-latest image preinstalls kubectl, but act's catthehacker runner
# does not — install unconditionally for parity).
#
# Versions are pinned via inline `# renovate:` comments below; the same
# constants are mirrored as step-env in .github/workflows/ci.yml so that
# Renovate's customManagers regex covers BOTH locations.
set -euo pipefail

# renovate: datasource=github-releases depName=kubernetes-sigs/kind
KIND_VERSION="${KIND_VERSION:-v0.31.0}"
# renovate: datasource=github-releases depName=kubernetes/kubernetes
KUBECTL_VERSION="${KUBECTL_VERSION:-v1.35.3}"

OS="$(uname -s | tr '[:upper:]' '[:lower:]')"
ARCH="$(uname -m)"
case "$ARCH" in
  x86_64) ARCH=amd64 ;;
  aarch64|arm64) ARCH=arm64 ;;
  *) echo "Unsupported arch: $ARCH" >&2; exit 1 ;;
esac

DEST="${HOME}/.local/bin"
mkdir -p "$DEST"

if ! command -v kind >/dev/null 2>&1 || [ "$(kind version 2>/dev/null | awk '{print $2}')" != "$KIND_VERSION" ]; then
  echo "Installing kind ${KIND_VERSION}..."
  curl -fsSLo "${DEST}/kind" "https://kind.sigs.k8s.io/dl/${KIND_VERSION}/kind-${OS}-${ARCH}"
  chmod +x "${DEST}/kind"
fi

if ! command -v kubectl >/dev/null 2>&1 || [ "$(kubectl version --client -o json 2>/dev/null | grep -o '"gitVersion":"[^"]*"' | head -1 | cut -d'"' -f4)" != "$KUBECTL_VERSION" ]; then
  echo "Installing kubectl ${KUBECTL_VERSION}..."
  curl -fsSLo "${DEST}/kubectl" "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/${OS}/${ARCH}/kubectl"
  chmod +x "${DEST}/kubectl"
fi

echo "kind:    $(kind version)"
echo "kubectl: $(kubectl version --client | head -1)"
