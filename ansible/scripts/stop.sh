#!/bin/bash

# Script to stop MXCubeWeb service and close SSH tunnels (if any)

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

# Also stop the local direct-deployment instance if it's running and isn't
# what we just stopped above. Handy if you've been switching inventory.yaml
# back and forth between local and remote testing and forgot a local run is
# still holding ports 8081/8000 — it would otherwise silently block a fresh
# SSH tunnel from binding on those same local ports.
if [ "${TARGET_VM_CONTEXT}" != "mxcube_local" ] && systemctl is-active --quiet mxcubeweb-mxcube_local 2>/dev/null; then
    echo ""
    echo "Also stopping local instance (mxcubeweb-mxcube_local) still running on this machine..."
    sudo systemctl stop mxcubeweb-mxcube_local
    echo "Local instance stopped"
fi

# Close any lingering SSH tunnels holding the well-known local ports,
# regardless of which remote host they were opened against — a tunnel to a
# host you're no longer targeting can be just as blocking as one to the
# current target.
echo ""
echo "Closing SSH tunnels (if any)..."
pkill -f "ssh.*-L.*8081:localhost:8081" 2>/dev/null && echo " Closed tunnel on port 8081" || echo "No tunnel found on port 8081"
pkill -f "ssh.*-L.*8000:localhost:8000" 2>/dev/null && echo " Closed tunnel on port 8000" || echo "No tunnel found on port 8000"
pkill -f "ssh.*-L.*5000:localhost:5000" 2>/dev/null && echo " Closed tunnel on port 5000 (BLISS)" || echo "No tunnel found on port 5000"

echo ""
echo "=== MXCubeWeb stopped ==="
