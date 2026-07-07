#!/bin/bash

set -euo pipefail

# ==============================================================================
# GovPay - Build, tag e push di una nuova immagine
# Uso: ./govpay-release.sh <versione> [--local] [--rev <N>] [image_base]
#
#   <versione>   Versione del PRODOTTO/installer GovPay (es. 3.9.3.p2).
#                Usata per -v (path interni al Dockerfile) e per l'installer locale.
#   --local      Usa l'installer locale govpay-installer-<versione>.tgz
#   --rev <N>    Revisione dell'IMMAGINE a prodotto invariato (es. 2 -> tag 3.9.3.p2-2).
#                Incrementala quando cambia solo l'immagine (Tomcat, entrypoint,
#                hook console, base image, fix CVE...) e NON il prodotto GovPay.
#   image_base   Repository (default: linkitaly/govpay)
#
# Esempi:
#   ./govpay-release.sh 3.6.3
#   ./govpay-release.sh 3.9.3.p2 --local
#   ./govpay-release.sh 3.9.3.p2 --local --rev 2
#   ./govpay-release.sh 3.9.3.p2 --local --rev 2 myregistry.example.com/govpay
# ==============================================================================

VERSION="${1:-}"

if [[ -z "$VERSION" || "${VERSION:0:1}" == "-" ]]; then
  echo "❌ Errore: versione non specificata."
  echo "   Uso: $0 <versione> [--local] [--rev <N>] [image_base]"
  echo "   Esempio: $0 3.9.3.p2 --local --rev 2"
  exit 1
fi
shift

LOCAL_FLAG=""
IMAGE_REV=""
IMAGE_BASE="linkitaly/govpay"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --local)  LOCAL_FLAG="--local"; shift ;;
    --rev|-r) IMAGE_REV="${2:-}"
              [[ -z "$IMAGE_REV" ]] && { echo "❌ --rev richiede un valore (es. --rev 2)"; exit 1; }
              shift 2 ;;
    -*)       echo "❌ Opzione sconosciuta: $1"; exit 1 ;;
    *)        IMAGE_BASE="$1"; shift ;;
  esac
done

INSTALLER="govpay-installer-${VERSION}.tgz"

# Tag dell'immagine: versione prodotto + eventuale revisione immagine.
# TAG_VERSION -> tag IMMUTABILE (pinnabile/rollback).
# VERSION     -> tag MOBILE ("ultima immagine per quella versione"), solo se c'e' una revisione.
if [[ -n "$IMAGE_REV" ]]; then
  TAG_VERSION="${VERSION}-${IMAGE_REV}"
else
  TAG_VERSION="${VERSION}"
fi

# ------------------------------------------------------------------------------
# Build
# ------------------------------------------------------------------------------
echo "🔨 Build GovPay ${VERSION} (tag immagine: ${TAG_VERSION})..."

if [[ "$LOCAL_FLAG" == "--local" ]]; then
  if [[ ! -f "$INSTALLER" ]]; then
    echo "❌ Installer locale non trovato: $INSTALLER"
    exit 1
  fi
  echo "   (usando installer locale: $INSTALLER)"
  ./build_image.sh -t "${IMAGE_BASE}:${TAG_VERSION}_postgres" -v "$VERSION" -l "$INSTALLER" -d postgresql
  ./build_image.sh -t "${IMAGE_BASE}:${TAG_VERSION}_mariadb"  -v "$VERSION" -l "$INSTALLER" -d mariadb
  ./build_image.sh -t "${IMAGE_BASE}:${TAG_VERSION}"          -v "$VERSION" -l "$INSTALLER"
else
  ./build_image.sh -t "${IMAGE_BASE}:${TAG_VERSION}_postgres" -v "$VERSION" -d postgresql
  ./build_image.sh -t "${IMAGE_BASE}:${TAG_VERSION}_mariadb"  -v "$VERSION" -d mariadb
  ./build_image.sh -t "${IMAGE_BASE}:${TAG_VERSION}"          -v "$VERSION"
fi

# ------------------------------------------------------------------------------
# Tag mobili (solo con revisione): "ultima immagine per la versione <VERSION>"
# ------------------------------------------------------------------------------
if [[ -n "$IMAGE_REV" ]]; then
  echo "🏷️  Tag mobili ${VERSION}[_db] -> ${TAG_VERSION}..."
  docker tag "${IMAGE_BASE}:${TAG_VERSION}_postgres" "${IMAGE_BASE}:${VERSION}_postgres"
  docker tag "${IMAGE_BASE}:${TAG_VERSION}_mariadb"  "${IMAGE_BASE}:${VERSION}_mariadb"
  docker tag "${IMAGE_BASE}:${TAG_VERSION}"          "${IMAGE_BASE}:${VERSION}"
fi

# ------------------------------------------------------------------------------
# Tag latest
# ------------------------------------------------------------------------------
echo "🏷️  Tag latest -> ${TAG_VERSION}..."
docker tag "${IMAGE_BASE}:${TAG_VERSION}" "${IMAGE_BASE}:latest"

# ------------------------------------------------------------------------------
# Push
# ------------------------------------------------------------------------------
echo "🚀 Push immagini..."

# Tag immutabili + latest
IMAGES=(
  "${IMAGE_BASE}:${TAG_VERSION}_postgres"
  "${IMAGE_BASE}:${TAG_VERSION}_mariadb"
  "${IMAGE_BASE}:${TAG_VERSION}"
  "${IMAGE_BASE}:latest"
)
# Tag mobili (se c'e' una revisione)
if [[ -n "$IMAGE_REV" ]]; then
  IMAGES+=(
    "${IMAGE_BASE}:${VERSION}_postgres"
    "${IMAGE_BASE}:${VERSION}_mariadb"
    "${IMAGE_BASE}:${VERSION}"
  )
fi

read -rp "Docker Hub username: " DOCKER_USER
docker login -u "$DOCKER_USER"

for img in "${IMAGES[@]}"; do
  docker push "$img"
done

docker logout

echo "✅ Release ${TAG_VERSION} completata."
