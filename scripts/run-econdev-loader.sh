#!/usr/bin/env bash
# Runs the one-time Economic development demo loader Apex script.
# Usage:
#   ./scripts/run-econdev-loader.sh <target-org-alias> [--dry-run]

set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <target-org-alias> [--dry-run]"
  exit 1
fi

TARGET_ORG="$1"
MODE="${2:-}"

SCRIPT_PATH="scripts/apex/econdev_demo_clone_run.apex"
if [[ "${MODE}" == "--dry-run" ]]; then
  SCRIPT_PATH="scripts/apex/econdev_demo_clone_dry_run.apex"
fi

echo "==> Running loader script: ${SCRIPT_PATH} on ${TARGET_ORG}"
sf apex run \
  --target-org "${TARGET_ORG}" \
  --file "${SCRIPT_PATH}"

echo "==> Loader execution finished"
