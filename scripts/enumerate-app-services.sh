#!/usr/bin/env bash
# enumerate-app-services.sh
#
# Scans one or more Azure subscriptions for App Services running Node.js
# and emits a GitHub Actions output variable `targets` containing a JSON
# array suitable for use as a strategy matrix, plus a `count` integer.
#
# Environment variables (all optional — defaults shown):
#   SUBSCRIPTION_IDS_INPUT   Comma-separated sub IDs from workflow_dispatch input
#   SUBSCRIPTION_IDS_SECRET  Comma-separated sub IDs from Actions secret (fallback)
#   NODE_STACK_FILTER        Stack prefix to match (default: "NODE")
#                            Empty string → match all App Services (any stack)
#
# Output (written to $GITHUB_OUTPUT when set; printed to stdout otherwise):
#   targets  JSON array of objects: {app_name, resource_group, subscription_id, os_type, node_stack}
#   count    Integer count of discovered targets
#
# Requires:
#   az  (Azure CLI, already logged in before this script is called)
#   jq  (available on GitHub-hosted runners)
#
set -euo pipefail

# ── Resolve subscription list ────────────────────────────────────────────────

RAW_IDS="${SUBSCRIPTION_IDS_INPUT:-}"
if [[ -z "${RAW_IDS}" ]]; then
  RAW_IDS="${SUBSCRIPTION_IDS_SECRET:-}"
fi

if [[ -z "${RAW_IDS}" ]]; then
  echo "[enumerate] No subscription IDs provided via input or secret. Falling back to az account list." >&2
  # Use all subscriptions the service principal can see
  RAW_IDS=$(az account list --query "[].id" -o tsv | tr '\n' ',' | sed 's/,$//')
fi

if [[ -z "${RAW_IDS}" ]]; then
  echo "[enumerate] ERROR: No Azure subscriptions found. Ensure the service principal has access." >&2
  exit 1
fi

# Normalise: split on commas, strip whitespace, remove empty entries
IFS=',' read -ra RAW_ARRAY <<< "${RAW_IDS}"
SUBSCRIPTIONS=()
for sub in "${RAW_ARRAY[@]}"; do
  sub="$(echo "${sub}" | tr -d '[:space:]')"
  [[ -n "${sub}" ]] && SUBSCRIPTIONS+=("${sub}")
done

echo "[enumerate] Scanning ${#SUBSCRIPTIONS[@]} subscription(s): ${SUBSCRIPTIONS[*]}" >&2

STACK_FILTER="${NODE_STACK_FILTER:-NODE}"

# ── Enumerate across subscriptions ──────────────────────────────────────────

TARGETS="[]"

for SUB in "${SUBSCRIPTIONS[@]}"; do
  echo "[enumerate] → subscription: ${SUB}" >&2

  # Set active subscription for this iteration
  az account set --subscription "${SUB}" 2>/dev/null || {
    echo "[enumerate]   WARN: Cannot access subscription ${SUB}, skipping." >&2
    continue
  }

  # Query all web apps (kind = "app" or "app,linux").
  # We retrieve siteConfig to inspect linuxFxVersion (Linux) and
  # windowsFxVersion / nodeVersion (Windows).
  #
  # az webapp list + show-config is slower but more reliable than querying
  # site properties directly for stack info. We do a two-step approach:
  #   1. List all webapps quickly (no site config)
  #   2. For each, fetch siteConfig and filter
  #
  # This is intentionally verbose so operators can see what was inspected.

  WEBAPPS_JSON=$(az webapp list \
    --subscription "${SUB}" \
    --query "[].{name:name, rg:resourceGroup, kind:kind, location:location}" \
    -o json 2>/dev/null) || {
    echo "[enumerate]   WARN: az webapp list failed for subscription ${SUB}." >&2
    continue
  }

  WEBAPP_COUNT=$(echo "${WEBAPPS_JSON}" | jq 'length')
  echo "[enumerate]   Found ${WEBAPP_COUNT} total App Service(s) in subscription ${SUB}" >&2

  if [[ "${WEBAPP_COUNT}" -eq 0 ]]; then
    continue
  fi

  # Iterate and check each app's stack
  while IFS= read -r APP_JSON; do
    APP_NAME=$(echo "${APP_JSON}" | jq -r '.name')
    RESOURCE_GROUP=$(echo "${APP_JSON}" | jq -r '.rg')
    KIND=$(echo "${APP_JSON}" | jq -r '.kind // ""')

    # Skip slots, function apps, and container-only apps
    # kind values: "app", "app,linux", "functionapp", "app,container,linux", etc.
    if echo "${KIND}" | grep -qiE "functionapp|container|workflow"; then
      echo "[enumerate]     Skipping ${APP_NAME} (kind=${KIND})" >&2
      continue
    fi

    # Fetch site config to get stack info
    SITE_CONFIG=$(az webapp config show \
      --name "${APP_NAME}" \
      --resource-group "${RESOURCE_GROUP}" \
      --subscription "${SUB}" \
      -o json 2>/dev/null) || {
      echo "[enumerate]     WARN: Could not fetch config for ${APP_NAME}, skipping." >&2
      continue
    }

    LINUX_FX=$(echo "${SITE_CONFIG}" | jq -r '.linuxFxVersion // ""')
    WIN_NODE=$(echo "${SITE_CONFIG}" | jq -r '.nodeVersion // ""')

    # Determine OS type and stack string
    if echo "${KIND}" | grep -qi "linux"; then
      OS_TYPE="Linux"
      NODE_STACK="${LINUX_FX}"
    else
      OS_TYPE="Windows"
      NODE_STACK="${WIN_NODE}"
    fi

    # Apply stack filter
    if [[ -n "${STACK_FILTER}" ]]; then
      if ! echo "${NODE_STACK}" | grep -qi "${STACK_FILTER}"; then
        echo "[enumerate]     Skipping ${APP_NAME} (stack='${NODE_STACK}', filter='${STACK_FILTER}')" >&2
        continue
      fi
    fi

    echo "[enumerate]     MATCH: ${APP_NAME} | rg=${RESOURCE_GROUP} | os=${OS_TYPE} | stack=${NODE_STACK}" >&2

    # Append to targets array
    NEW_ENTRY=$(jq -n \
      --arg app_name "${APP_NAME}" \
      --arg resource_group "${RESOURCE_GROUP}" \
      --arg subscription_id "${SUB}" \
      --arg os_type "${OS_TYPE}" \
      --arg node_stack "${NODE_STACK}" \
      '{app_name: $app_name, resource_group: $resource_group, subscription_id: $subscription_id, os_type: $os_type, node_stack: $node_stack}')

    TARGETS=$(echo "${TARGETS}" | jq --argjson entry "${NEW_ENTRY}" '. + [$entry]')

  done < <(echo "${WEBAPPS_JSON}" | jq -c '.[]')

done

# ── Emit outputs ─────────────────────────────────────────────────────────────

TARGET_COUNT=$(echo "${TARGETS}" | jq 'length')
echo "[enumerate] Total Node.js App Service targets: ${TARGET_COUNT}" >&2

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  # Compact JSON — no newlines (required for GitHub Actions matrix)
  COMPACT=$(echo "${TARGETS}" | jq -c '.')
  echo "targets=${COMPACT}" >> "${GITHUB_OUTPUT}"
  echo "count=${TARGET_COUNT}" >> "${GITHUB_OUTPUT}"
else
  # Running locally — pretty print for readability
  echo ""
  echo "=== TARGETS ==="
  echo "${TARGETS}" | jq '.'
  echo "=== COUNT: ${TARGET_COUNT} ==="
fi
