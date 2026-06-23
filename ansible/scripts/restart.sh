#!/bin/bash

# Restart MXCubeWeb (and BLISS if use_bliss=true) without redeploying.
#
# Usage:
#   ./restart.sh              Restart all services
#   ./restart.sh --tags bliss  Restart BLISS services only (requires use_bliss: true)

set -e

SCRIPT_ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$(realpath "${SCRIPT_ROOT}/../")"

PLAYBOOK="${PROJECT_ROOT}/playbooks/restart.yml"
INVENTORY="${PROJECT_ROOT}/inventory.yaml"

if ! command -v ansible-playbook >/dev/null 2>&1; then
    echo "ansible-playbook not found. Please install Ansible (./scripts/install_ansible.sh)"
    exit 2
fi

BECOME_ARGS=()
if ! ansible -i "${INVENTORY}" all -m command -a "true" --become --timeout 10 -q 2>/dev/null; then
    echo "Sudo requires a password on the target — you will be prompted once."
    BECOME_ARGS=(--ask-become-pass)
fi

echo "=== Restarting MXCubeWeb services ==="
ansible-playbook -i "${INVENTORY}" "${PLAYBOOK}" "${BECOME_ARGS[@]}" "$@"
echo "=== Restart complete ==="
