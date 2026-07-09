#!/bin/bash
#
# Shared helpers to resolve the deploy target (local machine or remote
# VM/server) from inventory.yaml and run commands against it transparently.
#
# Usage:
#   source "${SCRIPT_ROOT}/lib.sh"
#   resolve_target "${PROJECT_ROOT}/inventory.yaml"
#   run_on_target "some command" [--sudo] [--tty]
#
# After resolve_target, these globals are set:
#   TARGET_HOST       inventory hostname (e.g. "localhost" or "mxcube_vm1")
#   TARGET_CONNECTION "local" or "ssh"
#   TARGET_SSH_HOST   ansible_host (remote targets only)
#   TARGET_USER       ansible_user, if set
#   TARGET_PORT       ansible_port, if set
#   TARGET_VM_CONTEXT vm_context (falls back to TARGET_HOST)
#   TARGET_DISPLAY    human-readable label for messages ("localhost" or the SSH host)

resolve_target() {
    local inventory="$1"

    if ! command -v jq >/dev/null 2>&1; then
        echo "jq is required by these scripts but was not found. Install it (e.g. 'sudo apt install jq') and retry." >&2
        return 1
    fi

    if ! command -v ansible >/dev/null 2>&1; then
        echo "ansible is required by these scripts but was not found on PATH. Run './scripts/install_ansible.sh' and retry." >&2
        return 1
    fi

    TARGET_HOST=$(ansible -i "${inventory}" mxcube_vms --list-hosts 2>/dev/null | tail -n +2 | head -1 | tr -d ' ')
    if [ -z "${TARGET_HOST}" ]; then
        echo "No host found in the 'mxcube_vms' group of ${inventory}" >&2
        return 1
    fi

    local json
    json=$(ansible-inventory -i "${inventory}" --host "${TARGET_HOST}")

    TARGET_CONNECTION=$(echo "${json}" | jq -r '.ansible_connection // "ssh"')
    TARGET_SSH_HOST=$(echo "${json}" | jq -r '.ansible_host // empty')
    TARGET_USER=$(echo "${json}" | jq -r '.ansible_user // empty')
    TARGET_PORT=$(echo "${json}" | jq -r '.ansible_port // empty')
    TARGET_VM_CONTEXT=$(echo "${json}" | jq -r --arg h "${TARGET_HOST}" '.vm_context // $h')

    if [ -z "${TARGET_SSH_HOST}" ]; then
        TARGET_SSH_HOST="${TARGET_HOST}"
    fi

    if [ "${TARGET_CONNECTION}" = "local" ]; then
        TARGET_DISPLAY="localhost"
    else
        TARGET_DISPLAY="${TARGET_SSH_HOST}"
    fi
}

is_local_target() {
    [ "${TARGET_CONNECTION}" = "local" ]
}

# Run a command on the resolved target, transparently using a local shell or
# SSH depending on ansible_connection. Returns the command's exit code.
#   run_on_target "<command>" [--sudo] [--tty]
run_on_target() {
    local cmd="$1"
    shift
    local use_sudo=false
    local use_tty=false
    for arg in "$@"; do
        case "$arg" in
            --sudo) use_sudo=true ;;
            --tty) use_tty=true ;;
        esac
    done

    if is_local_target; then
        if [ "${use_sudo}" = true ]; then
            sudo bash -c "${cmd}"
        else
            bash -c "${cmd}"
        fi
        return $?
    fi

    local ssh_opts=()
    [ -n "${TARGET_PORT}" ] && ssh_opts+=(-p "${TARGET_PORT}")
    [ "${use_tty}" = true ] && ssh_opts+=(-t)

    local ssh_dest="${TARGET_USER:+${TARGET_USER}@}${TARGET_SSH_HOST}"
    local remote_cmd="${cmd}"
    [ "${use_sudo}" = true ] && remote_cmd="sudo ${cmd}"

    ssh "${ssh_opts[@]}" "${ssh_dest}" "${remote_cmd}"
}
