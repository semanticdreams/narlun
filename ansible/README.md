# Ansible Deployment

This directory provisions and deploys Narlun onto an Ubuntu 24.04 VPS.

## What It Sets Up

- `redis-server` for app state
- `nginx` for static web serving and reverse proxying `/api/` and `/api/ws`
- a `narlun` system user
- a `narlun-backend` systemd service running the aiohttp app
- a local production Flutter web build synced from your machine during deploy

There is no PostgreSQL, no remote frontend build, and no Node.js dependency on the VPS.

## Secrets

`group_vars/all/vault.yml` is intentionally cleartext right now so you can review it and later encrypt it with Ansible Vault. It is ignored by Git.

It currently contains:

- `secret_key`
- `push_vapid_public_key`
- `push_vapid_private_key`
- `push_vapid_subject`

## Variables To Review

Defaults live in `group_vars/all/main.yml`.

The most important values are:

- `nginx_server_name`
- `public_host`
- `nginx_enable_https`
- `nginx_use_letsencrypt`
- `letsencrypt_email`
- `domain`

Current defaults are safe for initial HTTP-only bring-up, but push notifications and installable PWA behavior require real HTTPS on a real hostname.

The nginx config also raises request-size and proxy timeout limits enough for profile-picture uploads and long-lived websocket connections.

Redis persistence is configured explicitly during provisioning with append-only
logging plus periodic snapshots, so app state survives Redis restarts and VPS
reboots.

## Requirements

- Ansible installed locally
- `ansible.posix` collection installed locally
- `rsync` available locally and on the VPS
- SSH access to the target host with `become` privileges
- Flutter available locally for `ui/tool/build_web.sh`

Install the required collection with:

```bash
ansible-galaxy collection install ansible.posix
```

## Usage

From the repository root:

```bash
make provision
make deploy
```

`make deploy` automatically builds the web bundle locally before syncing files to the server.

If you run the deploy playbook directly, point it at the repository root with:

```bash
NARLUN_REPO_ROOT=/path/to/narlun ansible-playbook deploy.yml
```

## After First Provision

Before a production rollout, update at least:

- `nginx_server_name` to your real hostname
- `domain` if you want it to differ from the default derived URL
- `nginx_enable_https: true`
- `nginx_use_letsencrypt: true`
- `letsencrypt_email` to a real address

Then re-run `make provision`.

## Logs

The backend writes structured JSON logs to stdout, so on the VPS they live in
the `systemd` journal for `narlun-backend`. Frontend client errors are written
to `/home/narlun/log/frontend-errors.jsonl` and nginx writes to:

- `/var/log/nginx/narlun.access.log`
- `/var/log/nginx/narlun.error.log`

To download a local bundle of current logs from the VPS into `data/logs/`:

```bash
make logs
```

That exports the backend journal from the last 24 hours into a file and also
downloads the frontend error log plus the active nginx access/error logs.

To change the journal window:

```bash
make logs SINCE="3 days ago"
make logs SINCE=all
```

If you want a different local destination, set `NARLUN_LOG_DOWNLOAD_DIR` before
running the playbook.

To inspect logs directly on the server:

```bash
ssh ovh
sudo journalctl -u narlun-backend -f
```
