# MXCubeWeb — Deployment Tools

This repository contains everything needed to run and deploy MXCubeWeb:

| Directory | Purpose |
|-----------|---------|
| [`docker/`](docker/) | Development container (Debian 10, VNC desktop, conda) |
| [`ansible/`](ansible/) | Ansible playbooks for deploying to a VM |
| [`demo.yaml/`](demo.yaml/) | Hardware object YAML configs for the mock beamline |

---

## Quick overview

### Production — Ansible deployment to a VM, or to your own machine

Deploys MXCubeWeb as a systemd service, either on a remote target VM/server
over SSH, or directly on the machine you run the playbook from. Manages the
conda environment, Python/JS dependencies, systemd units, and the Docker
hardware simulators — the steps below are identical either way, except
where noted.

#### Prerequisites

- Ansible installed locally (`./ansible/scripts/install_ansible.sh`; open a
  new terminal afterwards so the updated `PATH` takes effect)
- `jq` installed locally (`sudo apt install jq`) — required by the deploy
  scripts to parse inventory data
- SSH access to the target VM(s) — not needed when deploying on your own machine
- Docker and the Compose plugin already installed on the target
  (the playbook manages containers via `docker-compose` but does not install Docker itself)
- Docker images loaded on the target (see [Loading Docker images](#7-load-docker-images-on-the-vm-first-time))

#### 1. Configure the inventory

Edit [`ansible/inventory.yaml`](ansible/inventory.yaml) and keep exactly
**one** of the two host entries active:

```yaml
mxcube_vms:
  hosts:
    # Option A: deploy on THIS machine — no SSH involved
    localhost:
      ansible_connection: local
      vm_context: "mxcube_local"

    # Option B: deploy on a remote VM/server over SSH
    # mxcube_vm1:
    #   ansible_host: YOUR_VM_HOSTNAME_OR_IP
    #   vm_context: "mxcube_vm1"
```

With Option A, all scripts below (`start.sh`, `deploy.sh`, `stop.sh`,
`restart.sh`, `setup_ssh.sh`) run every command directly on your machine
instead of over SSH, and MXCubeWeb is reached straight at
`https://localhost:8081` — no SSH tunnel step.

#### 2. Configure variables

Edit [`ansible/playbooks/group_vars/all/vars.yml`](ansible/playbooks/group_vars/all/vars.yml)
for site-specific settings (install path, port, SSO, video stream, etc.).

Key variables:

| Variable | Default | Description |
|----------|---------|-------------|
| `install_base_path` | `/opt/mxcube` | Install root on the target |
| `service_user` | current user | User that runs the service |
| `use_local_repos` | `true` | Sync from local paths vs. clone from GitHub |
| `mxcubeweb_config.port` | `8081` | Port exposed by MXCubeWeb |
| `use_bliss` | `false` | Enable BLISS backend |
| `mxcubeweb_config.external_url` | `https://your-mxcube-host.example.com` | Public URL of the deployment |
| `mxcubeweb_config.allowed_cors_origins` | `[]` | Origins allowed to open a SocketIO connection |

> When deploying on your own machine (`ansible_connection: local`), by default
> the playbook rsyncs `local_mxcubeweb_path`/`local_mxcubecore_path` into
> `install_base_path`, so keep that different from your checkouts.
>
> To skip the copy and run directly against your working checkouts instead
> (no rsync, editable installs point straight at your source tree), set
> `use_local_repos_in_place: true` and point `install_base_path` at the
> parent directory containing both checkouts as siblings named `mxcubecore`
> and `mxcubeweb` (e.g. `install_base_path: "~/mxcube"`). Note that
> `server.yaml` then gets templated straight into your mxcubeweb working
> tree, so it will show up as a modified file after each deploy.

> Leave `use_bliss: false` unless you have access to it,
> or set `use_local_repos: true` with your own `local_bliss_path`.
> if you use something else than BLISS

> `use_local_repos: false` clones `mxcubecore`/`mxcubeweb` from their `develop`
> branch on GitHub instead of syncing your local checkout. This repository's
> `server.yaml.j2` and `demo.yaml/` configs are only tested against the
> versions checked out alongside it — the latest `develop` may have moved on
> and be incompatible (different config fields, renamed hardware objects,
> etc.). Pin `mxcubecore_version`/`mxcubeweb_version` to a known-good ref if
> you go this route.

> `allowed_cors_origins` entries must be full origins with scheme, e.g.
> `"https://your-mxcube-host.example.com"` or `"http://localhost:8081"` —
> a bare `host:port` (no scheme) will never match the browser's `Origin`
> header and is silently ignored. Same-origin requests (front-end and
> back-end served from the same host) don't need to be listed at all.

#### 3. Configure SSO (optional)

Set `mxcubeweb_sso.use_sso: true` in `vars.yml` and fill in the OIDC/Keycloak
endpoints for your identity provider:

| Variable | Description |
|----------|-------------|
| `issuer` | OIDC issuer URL (e.g. Keycloak realm URL) |
| `logout_uri` / `token_info_uri` / `meta_data_uri` | Keycloak endpoints for logout, token introspection, and OIDC discovery |
| `client_id` | OIDC client ID registered in the identity provider |
| `client_secret` | Set via `MXCUBE_SSO_CLIENT_SECRET` (see [Set up secrets](#5-set-up-secrets)) |
| `scope` | Requested OIDC scopes (default `openid email profile`) |
| `code_challenge_method` | PKCE method (default `S256`) |

Leave `use_sso: false` to use mockup account instead.

#### 4. SSL/TLS (optional)

`mxcubeweb_config.cert` controls how MXCubeWeb serves HTTPS:

| Value | Behavior |
|-------|----------|
| `NONE` | Plain HTTP (default, fine behind a reverse proxy that terminates TLS) |
| `ADHOC` | Flask generates a self-signed certificate on startup |
| `SIGNED` | Uses `cert_pem`/`cert_key` (paths on the VM); set `local_cert_pem`/`local_cert_key` to copy a certificate/key from the Ansible controller to those paths during deploy |

#### 5. Set up secrets

Copy the template and fill in values:

```bash
cp ansible/scripts/mxcube_secrets.example ~/.mxcube_secrets
# edit ~/.mxcube_secrets with your values
source ~/.mxcube_secrets
```

Required variables:

```bash
export MXCUBE_SECRET_KEY=$(python -c 'import secrets; print(secrets.token_hex())')
export MXCUBE_SECURITY_PASSWORD_SALT=$(python -c 'import secrets; print(secrets.token_hex())')
export MXCUBE_SSO_CLIENT_SECRET=<value>   # leave empty if SSO is disabled
```

These are also stored in an Ansible Vault file. Copy the example and encrypt it:

```bash
cp ansible/playbooks/group_vars/all/vault.yml.example \
   ansible/playbooks/group_vars/all/vault.yml
# fill in values, then:
ansible-vault encrypt ansible/playbooks/group_vars/all/vault.yml
```

#### 6. Set up SSH (first time)

```bash
cd ansible
./scripts/setup_ssh.sh
```

Run this either way: for a remote target it copies your SSH key and
configures passwordless sudo over SSH; for a local target (`ansible_connection:
local`) it skips SSH entirely and just configures passwordless sudo on your
own machine so `deploy.sh`/`start.sh` don't prompt for your password on every
run.

#### 7. Load Docker images on the VM

The playbook downloads and loads the hardware simulator images automatically
from `arinax_docker_image_url`/`flex_docker_image_url`  —
no manual step needed if you have access to them.

If those URLs aren't reachable from your VM
Use something else or
get the `.tar` images another way and load them manually instead:

```bash
scp arinax.tar flex.tar your-vm:/tmp/

# on the VM
ssh your-vm
docker load -i /tmp/arinax.tar
docker load -i /tmp/flex.tar
```

Then leave `arinax_docker_image_url`/`flex_docker_image_url` empty in
`vars.yml` so the playbook skips the download and reuses the images already
loaded on the VM.

#### 8. Deploy

```bash
cd ansible
./scripts/start.sh
```

The script asks whether to do a full deploy or a quick code-only update,
then waits for the BLISS REST API and MXCubeWeb to be ready. On a remote
target, it then optionally opens an SSH tunnel so you can reach the
interface at `http://localhost:8081`. On a local target, MXCubeWeb is
already reachable at `https://localhost:8081` — no tunnel step.

#### Available scripts

| Script | Description |
|--------|-------------|
| `scripts/start.sh` | Interactive: deploy + start + optional SSH tunnel |
| `scripts/deploy.sh` | Deploy only (accepts `--quick` for code-only update) |
| `scripts/restart.sh` | Restart the service(s) without redeploying |
| `scripts/stop.sh` | Stop the service and close SSH tunnels |
| `scripts/setup_ssh.sh` | Configure SSH to the VM |
| `scripts/install_ansible.sh` | Install Ansible and Python dependencies |

#### Manual playbook run

```bash
cd ansible
ansible-playbook -i inventory.yaml playbooks/deploy_vm.yml
```

Useful tags for partial runs:

| Tag | Effect |
|-----|--------|
| `update` | Code sync + pip/pnpm install + frontend build only |
| `system` | Install system packages |
| `conda` | Create/update the conda environment |
| `repositories` | Copy or clone mxcubecore / mxcubeweb |
| `ui` | Frontend install and build (pnpm) |
| `docker` | Manage Docker hardware simulator containers |
| `service` | Start/restart the systemd service |
| `systemd` | Write/reload systemd unit files |

#### Service management on the VM

```bash
systemctl status mxcubeweb-mxcube_vm1
journalctl -u mxcubeweb-mxcube_vm1 -f
sudo systemctl restart mxcubeweb-mxcube_vm1
```

---

### Hardware configuration — demo.yaml

The [`demo.yaml/`](demo.yaml/) directory contains YAML hardware object configuration
files for the mock beamline (minidiff, sample changer, detectors, etc.).
This directory is used as the `mxcube_config_dir` by the Ansible deployment
and is also referenced by the Docker entrypoint.

To switch to a real beamline configuration, point `mxcube_config_dir` in
`vars.yml` to your site-specific config directory.

> `demo.yaml/drac.yaml` (ICAT/DRAC LIMS) and `demo.yaml/session.yaml`
> (synchrotron name, email domain, in-house proposal codes) are kept as
> working ESRF examples and contain ESRF-specific hostnames and values.
> Adapt or replace them before deploying.

---

## Repository structure

```
ansible-deploy/
├── ansible/                    # Ansible deployment
│   ├── inventory.yaml          # VM list
│   ├── ansible.cfg
│   ├── docker-compose.yml      # Hardware simulator services
│   ├── playbooks/
│   │   ├── deploy_vm.yml       # Main deploy playbook
│   │   ├── restart.yml
│   │   ├── stop.yml
│   │   ├── group_vars/all/
│   │   │   ├── vars.yml        # Site configuration
│   │   │   └── vault.yml       # Encrypted secrets (not committed)
│   │   └── templates/          # Jinja2 systemd/config templates
│   └── scripts/                # Helper shell scripts
├── demo.yaml/                  # Mock beamline hardware objects
└── docker/                     # Development container
    ├── Dockerfile
    ├── docker-compose.yml      # Hardware simulators for local dev
    ├── docker-entrypoint.sh
    ├── conda-install.sh
    └── README.md
```
