#!/usr/bin/env bash
# Installs a curated set of VS Code extensions for Salesforce development
# Usage:
#   chmod +x scripts/install-salesforce-vscode-extensions.sh
#   ./scripts/install-salesforce-vscode-extensions.sh
#
# Notes:
# - Requires the 'code' CLI. In VS Code, run from Command Palette:
#   "Shell Command: Install 'code' command in PATH" (macOS)
#   or ensure VS Code is added to PATH (Windows/Linux terminals).
# - Safe to re-run; uses --force to update/repair installs.
# - Optional AI assistants can be removed if undesired.

set -euo pipefail

extensions=(
  "salesforce.salesforcedx-vscode"   # Salesforce Extension Pack (Apex/LWC/Org Browser/Debug/Test)
  "dbaeumer.vscode-eslint"           # ESLint for JS/TS (LWC)
  "esbenp.prettier-vscode"           # Prettier formatting
  "chuckjonas.apex-pmd"              # Apex PMD static analysis
  "eamodio.gitlens"                  # GitLens Git insights
  "mitchdenny.soql"                  # SOQL Viewer
  "dotjoshjohnson.xml"               # XML Tools (metadata editing)
  "firsttris.vscode-jest-runner"     # Jest Runner for LWC tests (swap with Orta.vscode-jest if preferred)
  "redhat.vscode-yaml"               # YAML support (scratch defs, pipelines)
  # Optional AI assistants (remove if not desired):
  "GitHub.copilot"
  "Codeium.codeium"
)

echo "==> Checking for VS Code 'code' CLI..."
if ! command -v code &>/dev/null; then
  echo "ERROR: VS Code 'code' CLI not found."
  echo "Open VS Code and run: Command Palette -> Shell Command: Install 'code' command in PATH"
  exit 1
fi
echo "OK: 'code' CLI is available."

echo "==> Installing/extensions updating..."
for ext in "${extensions[@]}"; do
  echo "Installing: $ext"
  if ! code --install-extension "$ext" --force; then
    echo "Warning: Failed to install $ext (continuing)."
  fi
done

echo "==> Installed Salesforce-related extensions:"
code --list-extensions | grep -E 'salesforce|apex|lwc|pmd|jest|yaml|xml|gitlens|copilot|codeium' || true

echo "==> Done."
