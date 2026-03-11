#!/usr/bin/env bash
# Deploys the Mansfield demo metadata bundle in manifest/package.xml
# Usage:
#   ./scripts/deploy-mansfield-assets.sh <target-org-alias>

set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <target-org-alias>"
  exit 1
fi

TARGET_ORG="$1"

echo "==> Deploying Mansfield assets to org: ${TARGET_ORG}"
sf project deploy start \
  --target-org "${TARGET_ORG}" \
  --manifest manifest/package.xml \
  --wait 20

echo "==> Deploy complete"
