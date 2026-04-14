#!/usr/bin/env bash
# deploy.sh — Build the container image in ACR and roll the Container App.
#
# Infra must already exist (Terraform: terraform/projects/smbc-jria-healthcheck).
# Requires: az cli + logged in.
#
# Usage:
#   ./scripts/deploy.sh           # tag = git short-sha (or "manual" if not a repo)
#   TAG=v1 ./scripts/deploy.sh    # explicit tag
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR/.."

# Keep in sync with terraform/projects/smbc-jria-healthcheck/locals.tf
RG="rg-smbc-jria-healthcheck-poc"
ACR="acrsmbcjriahcpoc"
APP="ca-smbc-jria-healthcheck-poc"
REPO="jria-healthcheck-stub"

TAG="${TAG:-$(git rev-parse --short HEAD 2>/dev/null || echo manual)}"
IMAGE="${ACR}.azurecr.io/${REPO}:${TAG}"

echo "[deploy] Verifying az login..."
az account show --query '{name:name, id:id}' -o tsv

echo "[deploy] Building image in ACR (server-side)..."
echo "         image: ${IMAGE}"
az acr build \
  --registry "${ACR}" \
  --image "${REPO}:${TAG}" \
  --image "${REPO}:latest" \
  --file Dockerfile \
  --only-show-errors \
  .

echo "[deploy] Updating Container App ${APP} to image ${IMAGE}..."
az containerapp update \
  --name "${APP}" \
  --resource-group "${RG}" \
  --image "${IMAGE}" \
  --only-show-errors \
  --query "properties.latestRevisionFqdn" -o tsv

FQDN=$(az containerapp show --name "${APP}" --resource-group "${RG}" --query "properties.configuration.ingress.fqdn" -o tsv)
HEALTH_URL="https://${FQDN}/health"

echo "[deploy] Waiting 20s for revision to come up..."
sleep 20

echo "[deploy] Probing ${HEALTH_URL}..."
for i in 1 2 3 4 5 6; do
  if curl -fsS --max-time 10 "${HEALTH_URL}" ; then
    echo
    echo "[deploy] SUCCESS — ${HEALTH_URL}"
    exit 0
  fi
  echo "  attempt ${i}/6 failed, retrying in 10s..."
  sleep 10
done

echo "[deploy] WARN: healthcheck did not respond OK. Tail logs with:"
echo "  az containerapp logs show --name ${APP} --resource-group ${RG} --follow"
exit 1
