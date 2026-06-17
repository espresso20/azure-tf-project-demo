#!/usr/bin/env bash
# =============================================================================
#  bootstrap-state.sh — one-time creation of the Azure Storage backend that
#  holds Terraform state for a given environment, before the first
#  `make init <env>`.
#
#  Chicken-and-egg: the storage account storing Terraform state can't be managed
#  by that same state. So we create it here, out-of-band. Idempotent — safe to
#  re-run.
#
#  Reads resource_group_name / storage_account_name / container_name /
#  subscription_id from terraform/env/<env>/<env>.backend.tfvars, and `location`
#  from terraform/env/<env>/<env>.terraform.tfvars (location isn't a valid
#  azurerm backend key, so it lives with the stack vars).
#
#  If `storage_account_name` is still a placeholder, a globally-unique name is
#  derived from your subscription id + location and written back into the
#  backend tfvars.
#
#  The storage account gets blob versioning, TLS 1.2 minimum, and public blob
#  access disabled. State locking uses blob leases natively — no extra lock
#  table to provision (unlike DynamoDB on AWS).
#
#  Usage:  ./scripts/bootstrap-state.sh <env>     # env: dev | staging | prod
#  Or via: make bootstrap <env>
# =============================================================================
set -euo pipefail

ENV="${1:-}"
if [ -z "${ENV}" ]; then
  echo "✗ usage: $0 <env>   (dev | staging | prod)" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKEND_TFVARS="${SCRIPT_DIR}/../terraform/env/${ENV}/${ENV}.backend.tfvars"
STACK_TFVARS="${SCRIPT_DIR}/../terraform/env/${ENV}/${ENV}.terraform.tfvars"

if [ ! -f "${BACKEND_TFVARS}" ]; then
  echo "✗ backend config not found: ${BACKEND_TFVARS}" >&2
  exit 1
fi

# Pull a (possibly quoted) value out of an HCL tfvars file:
#   storage_account_name = "foo"   ->  foo
tfvar() {
  grep -E "^[[:space:]]*$1[[:space:]]*=" "$2" 2>/dev/null | head -1 \
    | sed -E 's/^[^=]*=[[:space:]]*"?([^"]*)"?[[:space:]]*$/\1/'
}

RG="$(tfvar resource_group_name "${BACKEND_TFVARS}")"
SA="$(tfvar storage_account_name "${BACKEND_TFVARS}")"
CONTAINER="$(tfvar container_name "${BACKEND_TFVARS}")"
SUBSCRIPTION="$(tfvar subscription_id "${BACKEND_TFVARS}")"
LOCATION="$(tfvar location "${STACK_TFVARS}")"

RG="${RG:-tfstate-rg}"
CONTAINER="${CONTAINER:-tfstate}"
LOCATION="${LOCATION:-eastus}"

if [ -z "${SUBSCRIPTION}" ] || [ "${SUBSCRIPTION}" = "00000000-0000-0000-0000-000000000000" ]; then
  echo "✗ set a real 'subscription_id' in ${BACKEND_TFVARS}" >&2
  exit 1
fi

echo "» Verifying Azure CLI session..."
if ! az account show >/dev/null 2>&1; then
  echo "✗ No valid session. Run: az login" >&2
  exit 1
fi
az account set --subscription "${SUBSCRIPTION}"
echo "  subscription: ${SUBSCRIPTION}  location: ${LOCATION}"

# Derive a globally-unique storage account name if the tfvars still holds a
# placeholder. Storage account names: 3-24 chars, lowercase alphanumeric only.
case "${SA}" in
  "" | your-tfstate-storage | CHANGE_ME*)
    HASH="$(printf '%s' "${SUBSCRIPTION}${LOCATION}" | shasum | cut -c1-15)"
    SA="tfstate${HASH}"
    echo "» No real storage account set — deriving: ${SA}"
    ;;
  *)
    echo "» Using storage account from backend config: ${SA}"
    ;;
esac

echo "» Ensuring resource group '${RG}'..."
az group create --name "${RG}" --location "${LOCATION}" --output none

if az storage account show --name "${SA}" --resource-group "${RG}" >/dev/null 2>&1; then
  echo "» Storage account '${SA}' already exists — skipping create."
else
  echo "» Creating storage account '${SA}'..."
  az storage account create \
    --name "${SA}" \
    --resource-group "${RG}" \
    --location "${LOCATION}" \
    --sku Standard_LRS \
    --kind StorageV2 \
    --min-tls-version TLS1_2 \
    --allow-blob-public-access false \
    --output none
fi

echo "» Enabling blob versioning (lets us recover a clobbered state file)..."
az storage account blob-service-properties update \
  --account-name "${SA}" \
  --resource-group "${RG}" \
  --enable-versioning true \
  --output none

echo "» Ensuring container '${CONTAINER}'..."
az storage container create \
  --name "${CONTAINER}" \
  --account-name "${SA}" \
  --auth-mode login \
  --output none

# Persist the resolved storage account name back into the backend config.
# Portable in-place edit (no GNU/BSD `sed -i` divergence).
if [ "$(tfvar storage_account_name "${BACKEND_TFVARS}")" != "${SA}" ]; then
  echo "» Writing storage account name into ${ENV}.backend.tfvars..."
  tmp="$(mktemp)"
  sed -E "s|^([[:space:]]*storage_account_name[[:space:]]*=).*|\\1 \"${SA}\"|" "${BACKEND_TFVARS}" >"${tmp}"
  mv "${tmp}" "${BACKEND_TFVARS}"
fi

echo ""
echo "✓ State backend ready for '${ENV}'. Next:"
echo "    make init ${ENV}"
