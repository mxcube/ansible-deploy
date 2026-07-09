#!/bin/bash

# Script to run the Ansible playbook that deploys MXCubeWeb
#
# Usage:
#   ./deploy.sh              Full deploy (installs envs, builds UI, etc.)
#   ./deploy.sh --quick      Quick update: skips apt packages and Docker images.
#                            Conda envs and UI build are auto-skipped when already
#                            up-to-date (idempotency guards in the playbook).
#   ./deploy.sh --tags update  Ansible pass-through: only run tasks tagged 'update'

set -e

SCRIPT_ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$(realpath "${SCRIPT_ROOT}/../")"

echo "=== Running MXCubeWeb deploy playbook ==="

if ! command -v ansible-playbook >/dev/null 2>&1; then
    echo "ansible-playbook not found. Please install Ansible (./scripts/install_ansible.sh)"
    exit 2
fi

PLAYBOOK="${PROJECT_ROOT}/playbooks/deploy_vm.yml"
INVENTORY="${PROJECT_ROOT}/inventory.yaml"

if [ ! -f "${PLAYBOOK}" ]; then
    echo "Playbook not found: ${PLAYBOOK}"
    exit 1
fi

# Check that required secret environment variables are set
MISSING_VARS=()
for var in MXCUBE_SECRET_KEY MXCUBE_SECURITY_PASSWORD_SALT MXCUBE_SSO_CLIENT_SECRET; do
    if [ -z "${!var}" ]; then
        MISSING_VARS+=("$var")
    fi
done
if [ ${#MISSING_VARS[@]} -gt 0 ]; then
    echo ""
    echo "ERROR: The following required environment variables are not set:"
    for var in "${MISSING_VARS[@]}"; do
        echo "  $var"
    done
    echo ""
    echo "Set them before running this script, e.g. in ~/.mxcube_secrets (never commit that file):"
    echo "  export MXCUBE_SECRET_KEY=\$(python -c 'import secrets; print(secrets.token_hex())')"
    echo "  export MXCUBE_SECURITY_PASSWORD_SALT=\$(python -c 'import secrets; print(secrets.token_hex())')"
    echo "  export MXCUBE_SSO_CLIENT_SECRET=<value>"
    echo "  source ~/.mxcube_secrets"
    echo ""
    exit 1
fi

# Parse --quick flag; pass everything else through to ansible-playbook
QUICK=false
EXTRA_ARGS=()
for arg in "$@"; do
    case "$arg" in
        --quick|-q)
            QUICK=true
            ;;
        *)
            EXTRA_ARGS+=("$arg")
            ;;
    esac
done

# Detect whether passwordless sudo works on the target (used for both quick and full deploys)
BECOME_ARGS=()
if ! ansible -i "${INVENTORY}" all -m command -a "true" --become --timeout 10 >/dev/null 2>&1; then
    echo "Sudo requires a password on the target — you will be prompted once."
    BECOME_ARGS=(--ask-become-pass)
fi

if [ "$QUICK" = true ]; then
    echo "(quick mode: skipping system packages, Docker image downloads and conda env update)"
    ansible-playbook -i "${INVENTORY}" "${PLAYBOOK}" \
        --skip-tags "system,docker" \
        --extra-vars "skip_env_update=true" \
        "${BECOME_ARGS[@]}" "${EXTRA_ARGS[@]}"
else
    ansible-playbook -i "${INVENTORY}" "${PLAYBOOK}" "${BECOME_ARGS[@]}" "${EXTRA_ARGS[@]}"
fi

echo "=== Deploy finished ==="