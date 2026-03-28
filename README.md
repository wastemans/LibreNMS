# LibreNMS

LibreNMS on a dedicated VM: SNMP monitoring, syslog, auto-discovery, graphs.

---

## Prerequisites

- Proxmox firewall ports: `443/tcp` (web UI), `514/tcp` (syslog), `161/udp` (SNMP outbound)
- Port `8000` is internal only

## LXC Setup

```bash
pveam download local debian-12-standard_12.12-1_amd64.tar.zst
pct create 115 local:vztmpl/debian-12-standard_12.12-1_amd64.tar.zst \
  --hostname monitor --cores 2 --memory 4096 --rootfs local-lvm:10 \
  --net0 name=eth0,bridge=vmbr0,ip=dhcp --unprivileged 0 \
  --features nesting=1,keyctl=1 --start 1
```

Install Docker Engine (not Debian's `docker.io`):

```bash
pct enter 115
apt update && apt install -y ca-certificates curl
curl -fsSL https://get.docker.com | sh
```

---

## Quick start

```bash
cp .env.example .env        # edit all values
cp scripts/post/librenms/devices.json.example scripts/post/librenms/devices.json   # optional
cp scripts/post/librenms/services.json.example scripts/post/librenms/services.json # optional
./scripts/utility/utility_build-stack.sh
```

First boot takes a few minutes (DB init, migrations, scan). Watch progress:

```bash
docker logs -f librenms-scan
```

---

## Architecture

All services use host networking (`127.0.0.1`). Data lives at `DATA_DIR` (bind mounts, not Docker volumes).

| Service      | Container             | Role                                              |
| ------------ | --------------------- | ------------------------------------------------- |
| `db`         | `librenms-db`         | MariaDB                                           |
| `redis`      | `librenms-redis`      | Cache + sessions                                  |
| `librenms`   | `librenms`            | Web app + CLI on `:8000`                          |
| `dispatcher` | `librenms-dispatcher` | Poll/discovery worker                             |
| `syslogng`   | `librenms-syslogng`   | Syslog on `:514`                                  |
| `nginx`      | `librenms-nginx`      | TLS on `:443`, redirect `:80`, proxy to `:8000`   |
| `scan`       | `librenms-scan`       | One-shot bootstrap: user, imports, `lnms scan`    |

---

## Configuration

### `.env`

Copy `.env.example` to `.env` and edit. Key fields: `DATA_DIR`, `APP_URL`, DB creds, `SNMP_COMMUNITY`, `DISCOVERY_SUBNET`, `LNMS_ADMIN_USER`, `LNMS_ADMIN_PASS`.

Set `LNMS_API_TOKEN` (from `openssl rand -hex 16`) to enable auto-imports on bootstrap.

### Bootstrap imports

When `LNMS_API_TOKEN` is set, the `scan` container automatically imports:

| What               | Source                         | Toggle                         |
| ------------------ | ------------------------------ | ------------------------------ |
| Alert rules        | Built into image               | `IMPORT_ALERT_COLLECTION=0`    |
| Ping-only devices  | `scripts/post/librenms/devices.json`  | File missing = skipped  |
| Service checks     | `scripts/post/librenms/services.json` | File missing = skipped  |

Re-runs skip existing entries. Copy the `.example` files and edit with your hostnames/IPs.

### `config.php`

Mounted into the `librenms` container. Uses `getenv()` for URL, SNMP, subnets, syslog purge. These must be in `.env` and listed under `librenms`'s `environment:` in `docker-compose.yaml`.

---

## Lifecycle scripts

In `scripts/utility/` (run from anywhere):

| Script                              | Effect                             |
| ----------------------------------- | ---------------------------------- |
| `utility_build-stack.sh`            | Build + `up -d` + status check     |
| `utility_restart-stack.sh`          | `down` + `up -d` (data kept)       |
| `utility_upgrade-stack.sh`          | Pull/rebuild/restart (data kept)   |
| `utility_destructive-recreate.sh`   | **Wipes `DATA_DIR`**, rebuild      |
| `utility_destroy-stack.sh`          | **Wipes data**, stop, no rebuild   |
| `utility_stack_status.sh`           | Poll API until 200                 |
| `utility_librenms_import_alerts.sh` | Manual re-run: alert import        |
| `utility_librenms_import_devices.sh`| Manual re-run: device import       |
| `utility_librenms_import_services.sh`| Manual re-run: service import     |

---

## Common commands

```bash
# Discovery
docker exec -u librenms librenms lnms scan
docker exec -u librenms librenms lnms device:add --ping-fallback IP

# Config
docker exec -u librenms librenms lnms config:get nets
docker exec -u librenms librenms lnms config:get snmp.community

# Users
docker exec -u librenms librenms lnms user:add --password='PASS' --role=admin USER

# Logs
docker logs -f librenms-scan
docker logs -f librenms-nginx
docker compose ps
```

---

## Data on disk

All state under `DATA_DIR` (`DATA_DIR/db` for MariaDB, `DATA_DIR/librenms` for RRD/data).

Survives `docker compose down`. Only `utility_destructive-recreate.sh` or `utility_destroy-stack.sh` deletes it.

---

## SNMP on Debian hosts

```bash
apt install snmpd
```

Minimal `/etc/snmp/snmpd.conf`:

```
rocommunity public
disk /
disk /var
```

`systemctl restart snmpd` — LibreNMS auto-discovers and graphs CPU, memory, disk, swap, I/O, interfaces.

### Process monitoring

```
proc nginx 1
```

Alerts if process count drops to zero.

### TCP port checks (services)

Use `devices.json` + `services.json` for automated import, or add manually: **Device > Services > Add Service** (type `tcp`, param `-H IP -p PORT`).
