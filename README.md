# MXCubeWeb — Deployment Tools

This repository contains everything needed to run and deploy MXCubeWeb:

| Directory | Purpose |
|-----------|---------|
| [`docker/`](docker/) | Development container (Debian 10, VNC desktop, conda) |
| [`ansible/`](ansible/) | Ansible playbooks for deploying to a VM |
| [`demo.bliss.yaml/`](demo.bliss.yaml/) | Hardware object YAML configs for the mock beamline (real BLISS backend) |
| [`demo.mockup.yaml/`](demo.mockup.yaml/) | Same, with every hardware object swapped for its `*Mockup` equivalent (no BLISS) |

---

## Quick overview

### Production — Ansible deployment to a VM, or to your own machine

Deploys MXCubeWeb as a systemd service, either on a remote target VM/server
over SSH, or directly on the machine you run the playbook from. Manages the
conda environment, Python/JS dependencies, systemd units, and the Docker
hardware simulators — the steps below are identical either way, except
where noted.

#### Prerequisites

- Ansible installed locally (e.g. `python3 -m pip install --user ansible`;
  open a new terminal afterwards so the updated `PATH` takes effect)
- Required Ansible collections installed:
  `ansible-galaxy collection install -r ansible/requirements.yml`
- `jq` installed locally (`sudo apt install jq`) — required by the deploy
  scripts to parse inventory data
- SSH access to the target VM(s) — not needed when deploying on your own machine
- Docker and the Compose plugin already installed on the target
  (the playbook manages containers via `docker-compose` but does not install Docker itself)
- Docker images loaded on the target (see [Loading Docker images](#6-load-docker-images-on-the-vm))

#### 1. Configure the inventory

Edit [`ansible/inventory.yaml`](ansible/inventory.yaml) and keep exactly
**one** of the two host entries active:

```yaml
mxcube_vms:
  hosts:
    # Option A: deploy on THIS machine — no SSH involved
    # localhost:
    #   ansible_connection: local
    #   vm_context: "mxcube_local"
    #   use_bliss: true    # real BLISS-backed hardware config (demo.bliss.yaml)

    # Option B: deploy on a remote VM/server over SSH
    mxcube_vm1:
      ansible_host: YOUR_VM_HOSTNAME_OR_IP
      vm_context: "mxcube_vm1"
      use_bliss: false    # no BLISS on this VM — mockup hardware config (demo.mockup.yaml)
```

With Option A, all scripts below (`start.sh`, `deploy.sh`, `stop.sh`,
`restart.sh`) run every command directly on your machine instead of over
SSH, and MXCubeWeb is reached straight at `https://localhost:8081`. SSH
access to the target — if you use Option B — is assumed to already be set
up independently of this playbook (key-based auth, VPN, whatever your
environment needs); nothing here manages that for you.

> `use_bliss` is set **per host** here, not just in `vars.yml` — different
> targets can run different hardware configs at the same time (e.g. one
> real-BLISS host, one standalone mockup host). See
> [Hardware configuration](#hardware-configuration--demobliss-yaml--demomockup-yaml)
> below for what that actually switches.

#### 2. Configure variables

Edit [`ansible/playbooks/group_vars/all/vars.yml`](ansible/playbooks/group_vars/all/vars.yml)
for site-specific settings (install path, port, SSO, video stream, etc.).

Key variables:

| Variable | Default | Description |
|----------|---------|-------------|
| `install_base_path` | `/opt/mxcube` | Install root on the target |
| `service_user` | current user | User that runs the service — see [Dedicated service user](#optional-dedicated-service-user) to create one instead of using your own account |
| `mxcube_config_dir` | derived from `use_bliss` | Which hardware config directory gets deployed — see [Hardware configuration](#hardware-configuration--demobliss-yaml--demomockup-yaml) |
| `mxcubeweb_config.port` | `8081` | Port exposed by MXCubeWeb |
| `use_bliss` | `true` | Fallback if a host doesn't set its own `use_bliss` in `inventory.yaml` (see step 1) |
| `mxcubeweb_config.external_url` | `https://your-mxcube-host.example.com` | Public URL of the deployment |
| `mxcubeweb_config.allowed_cors_origins` | `[]` | Origins allowed to open a SocketIO connection |
| `mxcubeweb_config.user_db_path` | `{{ install_base_path }}/data/mxcube-user.db` | Local user-account database — kept off `/tmp` so it survives reboots and is reliably writable by `service_user` |
| `mxcubeweb_video.stream_url` | `ws://<target host>:8000/ws` | Video stream URL handed to the frontend; must be `ws://`/`wss://`, not `http(s)://` — the UI opens it as a raw WebSocket |
| `mxcubeweb_video.mxcube_starts_stream` | `true` | Whether MXCubeWeb spawns its own `video-streamer`/`ffmpeg` process. Leave `true` unless you're running a separate/external streamer — with it `false` and nothing else providing a stream, nothing will be listening on `stream_port` at all |

> The playbook always clones `mxcubecore`/`mxcubeweb` fresh from their
> `develop` branch on GitHub into `install_base_path` (even when deploying
> on your own machine with `ansible_connection: local`). This repository's
> `server.yaml.j2` and `demo.bliss.yaml`/`demo.mockup.yaml` configs are only
> tested against the versions checked out alongside it — the latest `develop` may have moved on
> and be incompatible (different config fields, renamed hardware objects,
> etc.). Pin `mxcubecore_version`/`mxcubeweb_version` to a known-good ref if
> that matters to you.

> `use_bliss` clones BLISS from `bliss_repo` (`gitlab.esrf.fr`) when true.
> Normally set per-host in `inventory.yaml` (step 1) rather than here — the
> `true` above is only the fallback for a host that doesn't set its own.

> `allowed_cors_origins` entries must be full origins with scheme, e.g.
> `"https://your-mxcube-host.example.com"` or `"http://localhost:8081"` —
> a bare `host:port` (no scheme) will never match the browser's `Origin`
> header and is silently ignored. Same-origin requests (front-end and
> back-end served from the same host) don't need to be listed at all.

> `allowed_cors_origins` and `stream_url` use
> `{{ ansible_host | default(inventory_hostname) }}` to pick up the target's
> actual address from `inventory.yaml` automatically — you shouldn't need to
> hardcode a hostname here. Falls back to `inventory_hostname` (e.g.
> `localhost`) for a host that doesn't set `ansible_host` explicitly.

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

#### 6. Load Docker images on the VM

The playbook downloads and loads the hardware simulator images automatically
from `arinax_docker_image_url`/`flex_docker_image_url` — no manual step
needed if those URLs are reachable from your VM.

If they aren't reachable, get the `.tar` images another way and load them
manually instead:

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

#### 7. Deploy

```bash
cd ansible
./scripts/start.sh
```

The script asks whether to do a full deploy or a quick code-only update,
then waits for the BLISS REST API and MXCubeWeb to be ready, and prints the
URL to reach it. It assumes access to the target (SSH tunnel, VPN, direct
network, etc.) is already set up independently, if needed — on a local
target, MXCubeWeb is reachable directly at `https://localhost:8081`.

#### Available scripts

| Script | Description |
|--------|-------------|
| `scripts/start.sh` | Interactive: deploy + start, prints the URL to reach it |
| `scripts/deploy.sh` | Deploy only (accepts `--quick` for code-only update) |
| `scripts/restart.sh` | Restart the service(s) without redeploying |
| `scripts/stop.sh` | Stop the service |

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

#### Optional: dedicated service user

By default the deployment runs as whichever account you SSH in as
(`service_user` defaults to your own login user). To run it as a separate,
dedicated account instead, create it first with the standalone
[`create_service_user.yml`](ansible/playbooks/create_service_user.yml)
playbook:

```bash
cd ansible
ansible-playbook -i inventory.yaml playbooks/create_service_user.yml
```

This creates a `mxop` user (home dir + `/bin/bash` shell) on every host in
the `mxcube_vms` inventory group. It's deliberately separate from
`deploy_vm.yml` and doesn't touch SSH access or sudo rights — just the
account itself.

Creating the account alone doesn't switch anything over: `deploy_vm.yml`
still installs/runs everything as whatever `service_user` is currently set
to. Set `service_user: mxop` in `vars.yml` and redeploy to actually move
the deployment onto that account. If a host already has a prior deployment
under a different `service_user`, expect a full redeploy so directories,
the conda environment, and systemd units get owned by the new one.

#### Service management on the VM

```bash
systemctl status mxcubeweb-mxcube_vm1
journalctl -u mxcubeweb-mxcube_vm1 -f
sudo systemctl restart mxcubeweb-mxcube_vm1
```

---

### Hardware configuration — demo.bliss.yaml / demo.mockup.yaml

There are two parallel hardware-object config directories for the mock
beamline (minidiff, sample changer, detectors, etc.), kept in sync with each
other except for which backend each hardware object talks to:

- [`demo.bliss.yaml/`](demo.bliss.yaml/) — real BLISS-backed hardware objects
  (`BlissMotor`, `BlissShutter`, `BlissNState`, `BlissEnergy`, ...). Requires
  `use_bliss: true` and access to BLISS.
- [`demo.mockup.yaml/`](demo.mockup.yaml/) — every one of those swapped for
  its `*Mockup` equivalent, so the beamline runs standalone with no BLISS
  dependency at all.

`mxcube_config_dir` in `vars.yml` picks between them automatically based on
`use_bliss` — you don't need to set it yourself. To switch to a real
beamline configuration instead of either of these, point `mxcube_config_dir`
at your own site-specific config directory.

> `drac.yaml` (ICAT/DRAC LIMS) and `session.yaml` (synchrotron name, email
> domain, in-house proposal codes), present in both directories, are kept as
> working ESRF examples and contain ESRF-specific hostnames and values.
> Adapt or replace them before deploying.

---

## Repository structure

```
ansible-deploy/
├── ansible/                    # Ansible deployment
│   ├── inventory.yaml          # VM list, use_bliss set per-host here
│   ├── ansible.cfg
│   ├── requirements.yml        # Required Ansible collections (community.docker)
│   ├── docker-compose.yml      # Hardware simulator services
│   ├── playbooks/
│   │   ├── deploy_vm.yml       # Main deploy playbook
│   │   ├── create_service_user.yml  # Standalone: create the mxop service account
│   │   ├── restart.yml
│   │   ├── stop.yml
│   │   ├── group_vars/all/
│   │   │   ├── vars.yml        # Site configuration
│   │   │   └── vault.yml       # Encrypted secrets (not committed)
│   │   └── templates/          # Jinja2 systemd/config templates
│   └── scripts/                # Helper shell scripts (start/deploy/restart/stop)
├── demo.bliss.yaml/             # Mock beamline hardware objects (real BLISS backend)
├── demo.mockup.yaml/            # Mock beamline hardware objects (no BLISS, *Mockup classes)
└── docker/                     # Development container
    ├── Dockerfile
    ├── docker-compose.yml      # Hardware simulators for local dev
    ├── docker-entrypoint.sh
    ├── conda-install.sh
    └── README.md
```
