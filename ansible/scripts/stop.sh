#!/bin/bash

# Script to stop MXCubeWeb service

set -e

SCRIPT_ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$(realpath "${SCRIPT_ROOT}/../")"
# shellcheck source=lib.sh
source "${SCRIPT_ROOT}/lib.sh"

resolve_target "${PROJECT_ROOT}/inventory.yaml"
SERVICE_NAME="mxcubeweb-${TARGET_VM_CONTEXT}"

echo "=== Stopping MXCubeWeb ==="
echo ""

# Stop the currently configured target's service
echo "Stopping service ${SERVICE_NAME} on ${TARGET_DISPLAY}..."
if run_on_target "systemctl is-active --quiet ${SERVICE_NAME}"; then
    run_on_target "systemctl stop ${SERVICE_NAME}" --sudo --tty
    echo "Service stopped"
else
    echo "Service is already stopped"
fi

echo ""
echo "=== MXCubeWeb stopped ==="
