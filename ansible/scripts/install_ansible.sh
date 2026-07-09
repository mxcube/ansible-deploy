#!/bin/bash

# Script to install Ansible and required dependencies

set -e

SCRIPT_ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

echo "=== Installing Ansible and dependencies ==="

# On Debian/Ubuntu (PEP 668), the system python3 refuses plain `pip install`
# with "externally-managed-environment". --user --break-system-packages
# installs into ~/.local instead of touching system packages, which is safe
# here since we're not installing over anything apt manages.
PIP_ARGS=(--user)
if python3 -m pip install --help 2>/dev/null | grep -q -- '--break-system-packages'; then
    PIP_ARGS+=(--break-system-packages)
fi

if [ -f "${SCRIPT_ROOT}/requirements.txt" ]; then
    echo "Installing Python packages..."
    python3 -m pip install "${PIP_ARGS[@]}" -r "${SCRIPT_ROOT}/requirements.txt"
else
    echo "Installing Ansible..."
    python3 -m pip install "${PIP_ARGS[@]}" ansible
fi

echo "=== Installation completed ==="
echo ""
if ! command -v ansible >/dev/null 2>&1; then
    echo "NOTE: ~/.local/bin isn't on your PATH yet in this shell."
    echo "Open a new terminal (or run 'hash -r' after adding it to PATH) before continuing."
fi
echo "Deploy: ./scripts/deploy.sh"
echo "Start: ./scripts/start.sh"
