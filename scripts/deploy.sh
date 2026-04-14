#!/usr/bin/env bash
# deploy.sh — Build app.zip and deploy to Azure App Service via Blob + WEBSITE_RUN_FROM_PACKAGE.
#
# Infra must already exist (Terraform: terraform/projects/smbc-jria-healthcheck).
# Requires: az cli + logged in, npm, zip.
#
# Usage:
#   ./scripts/deploy.sh
#   SKIP_BUILD=1 ./scripts/deploy.sh    # upload existing app.zip without rebuilding
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR/.."

# Keep in sync with terraform/projects/smbc-jria-healthcheck/locals.tf
STORAGE_ACCOUNT="cubicle13backup"
CONTAINER="jria-healthcheck-stub"
BLOB_NAME="app.zip"
APP_NAME="app-smbc-jria-healthcheck-poc"
RG="rg-smbc-jria-healthcheck-poc"

echo "[deploy] Verifying az login..."
az account show --query '{name:name, id:id}' -o table

if [[ "${SKIP_BUILD:-0}" != "1" ]]; then
  echo "[deploy] Building app.zip (npm run package)..."
  npm run package
fi

[[ -f app.zip ]] || { echo "[deploy] ERROR: app.zip not found"; exit 1; }
echo "[deploy] app.zip size: $(du -h app.zip | cut -f1)"

echo "[deploy] Uploading to ${STORAGE_ACCOUNT}/${CONTAINER}/${BLOB_NAME}..."
az storage blob upload \
  --auth-mode login \
  --account-name "${STORAGE_ACCOUNT}" \
  --container-name "${CONTAINER}" \
  --name "${BLOB_NAME}" \
  --file app.zip \
  --overwrite \
  --only-show-errors

echo "[deploy] Restarting App Service ${APP_NAME}..."
az webapp restart --name "${APP_NAME}" --resource-group "${RG}" --only-show-errors

HEALTH_URL="https://${APP_NAME}.azurewebsites.net/health"
echo "[deploy] Waiting 25s for cold start..."
sleep 25

echo "[deploy] Probing ${HEALTH_URL}..."
for i in 1 2 3 4 5 6; do
  if curl -fsS --max-time 10 "${HEALTH_URL}" ; then
    echo
    echo "[deploy] SUCCESS"
    exit 0
  fi
  echo "  attempt ${i}/6 failed, retrying in 10s..."
  sleep 10
done

echo "[deploy] WARN: healthcheck did not respond OK — check App Service logs:"
echo "  az webapp log tail --name ${APP_NAME} --resource-group ${RG}"
exit 1
