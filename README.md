# monitor_stack

Two things on a dedicated VM:

- **librenms/** — LibreNMS: SNMP monitoring, syslog receiver, auto-discovery, graphs
- **puppet/** — `syslog_forward` module: pushes syslog from every managed node to LibreNMS

LibreNMS replaces NMIS9. It polls SNMP (CPU, memory, disk, swap, I/O, interfaces), receives syslog, auto-discovers your estate by subnet sweep, and ships with decent pre-built graphs for all of it.

---

## Prerequisites

- Ports to open inbound on your Proxmox firewall:
  - `443/tcp` — LibreNMS web UI (HTTPS via nginx)
  - `514/tcp` — syslog ingest (from all managed nodes)
  - `161/udp` — SNMP polling outbound to devices (usually open by default)
  - Port `8000` is internal only — do not expose it

## LXC Container Setup (Recommended)

Run this on the Proxmox host to create and start the container:

```bash
pveam download local debian-12-standard_12.12-1_amd64.tar.zst
pct create 115 local:vztmpl/debian-12-standard_12.12-1_amd64.tar.zst --hostname monitor --cores 2 --memory 4096 --rootfs local-lvm:10 --net0 name=eth0,bridge=vmbr0,ip=dhcp --unprivileged 0 --features nesting=1,keyctl=1 --start 1
```

> **Note:** If Docker warns about "system 252 detected, you may need to enable nesting", run:
> ```bash
> pct stop 115
> pct set 115 --features nesting=1,keyctl=1
> pct start 115
> ```

Install Docker and docker-compose inside the container:

```bash
pct enter 115
apt update && apt install -y curl docker-compose && curl -fsSL https://get.docker.com | sh
```

---

## LibreNMS Stack

### Before starting

**0. Create your `.env` file** from the example:

```bash
cp librenms/.env.example librenms/.env
```

Then edit `librenms/.env` with your actual values. This file is gitignored — never commit it.

**1. Set your timezone** in `.env`:
```
TZ=Region/City
```

**2. Set the external URL** in `.env`:
```
APP_URL=http://your-host
```

**3. Set your SNMP community and discovery subnet** in `.env`:
```
SNMP_COMMUNITY=your-community
DISCOVERY_SUBNET=x.x.x.0/24
```

**4. Admin login and alert collection import** (bootstrap reads these on every `docker-compose up`):

```
LNMS_ADMIN_USER=admin
LNMS_ADMIN_PASS=your-secure-password
```

To load **all** bundled alert rules on first boot (same definitions as *Add rule from collection*), generate a hex API token and put it in `.env` (do not use shell `$(...)` inside `.env` — paste the value only):

```bash
openssl rand -hex 16
```

```
LNMS_API_TOKEN=paste_the_32_hex_chars_here
IMPORT_ALERT_COLLECTION=1
```

Leave `LNMS_API_TOKEN` empty to skip rule import. Set `IMPORT_ALERT_COLLECTION=0` to disable even when a token is set.

### Stack management

All lifecycle operations are in `librenms/scripts/utility/`. Run them from anywhere — they navigate to the right directory automatically.

| Script | What it does |
|---|---|
| `build-stack.sh` | Build images and start all containers |
| `restart-stack.sh` | Stop and restart — data preserved |
| `upgrade-stack.sh` | Pull latest images, rebuild, restart — data preserved |
| `destructive-recreate.sh` | **Wipes all data**, then rebuilds and starts |
| `destroy-stack.sh` | **Wipes all data** and stops — does not rebuild |

### Start

```bash
cd ~/projects/LibreNMS/librenms
./scripts/utility/build-stack.sh
```

LibreNMS takes ~2 minutes to fully initialise on first boot (DB migrations run). Watch it:

```bash
docker logs -f librenms
```

### Verify subnet config after startup

Confirm `DISCOVERY_SUBNET` was parsed into separate entries (one line per subnet):

```bash
docker exec -u librenms librenms lnms config:get nets
```

Expected output (example for two subnets):

```
["10.1.1.0\/24","10.2.0.0\/16"]
```

### Manual scan

The `scan` bootstrap container fires automatically ~60 seconds after `docker-compose up -d` and exits. To trigger a scan manually at any time:

```bash
docker exec -u librenms librenms lnms scan
```

To see what the scan is hitting and why devices are accepted or skipped:

```bash
docker exec -u librenms librenms lnms scan -v
```

### Adding ping-only devices (no SNMP)

Devices that don't run SNMP (e.g. unmanaged or consumer switches) won't be auto-discovered by the subnet scan. Add them manually:

```bash
docker exec -u librenms librenms lnms device:add --ping-fallback 10.0.1.10
docker exec -u librenms librenms lnms device:add --ping-fallback 10.20.0.1
```

LibreNMS will ping them on every 5-minute poll cycle and graph availability and round-trip latency. To set a friendly display name, go to **Device > Edit > Display Name** in the web UI.

If SNMP is later enabled on any of these devices, edit the device in the UI to add SNMP credentials — full interface and traffic graphs will start building automatically from that point.

### Web UI

`https://your-host` — the admin account is created automatically by the bootstrap container (60 seconds after `docker-compose up`). Use the credentials from `LNMS_ADMIN_USER` / `LNMS_ADMIN_PASS` in `.env`.

### Reset or change password

The bootstrap re-runs `user:add` on every `docker-compose up`, so updating `LNMS_ADMIN_PASS` in `.env` and restarting the stack resets the password automatically.

To reset manually without restarting:

```bash
docker exec -u librenms librenms lnms user:add --password=NEWPASSWORD --role=admin USERNAME
```

### First-time setup in the UI

1. **Validate**: Admin > Validate Install — fix any warnings shown
   - The stack uses **`CACHE_DRIVER=redis`** and **`SESSION_DRIVER=redis`** (names from the [official LibreNMS Docker image](https://github.com/librenms/docker) — not `CACHE_STORE`). **`APP_URL`** must be the exact HTTPS URL you use (e.g. `https://lnms.i`). After changing compose or `.env`, recreate the `librenms` container so `/opt/librenms/.env` is regenerated.
2. **Devices**: Once discovery subnets are set in `config.php`, run discovery manually first time: Admin > Discovery > Run Now (or wait up to 6h for the cron)
3. **Syslog**: Devices > Syslog — syslog entries appear here once nodes start forwarding

### Alert rules (full collection)

On bootstrap, if `LNMS_API_TOKEN` is set and `IMPORT_ALERT_COLLECTION=1`, the scan container registers that token in `api_tokens` and runs `librenms/scripts/import-alert-collection.php` against `http://127.0.0.1:8000` (same JSON as **Alerts > Alert Rules > Add rule from collection**). Existing rule names **SKIP** (HTTP non-2xx); new names are added enabled. Irrelevant rules never fire on devices that lack matching sensors/OIDs.

Manual re-run (e.g. after upgrading the LibreNMS image with a newer `alert_rules.json`):

```bash
cd ~/projects/LibreNMS/librenms
export LNMS_API_TOKEN='same value as in .env'
./scripts/post/librenms/post_librenms_import_alerts.sh
```

### HTTPS via nginx reverse proxy

An nginx container is included in the stack. It listens on `443` and proxies to LibreNMS on `127.0.0.1:8000`. Port `80` redirects to HTTPS.

A throwaway self-signed cert is generated automatically inside the container at startup — no cert management needed.

Set `APP_URL` in `.env` to use https:
```
APP_URL=https://your-host
```

Port `8000` remains accessible for direct internal access if needed.

### Dashboards

LibreNMS ships with no default dashboards. Build one in the UI (Dashboard > New Dashboard) and add widgets:

| Widget | What it shows |
|---|---|
| Availability Map | All devices as green/red tiles |
| Device Summary | Up/down/ignored counts |
| Alerts | Active alert list |
| Syslog | Live syslog feed |
| Top Interfaces | Busiest ports by traffic |

Set it as the default for all users: **Settings > WebUI Settings > Dashboard Settings**.

Dashboards live in the DB volume and survive restarts. They are lost on `docker-compose down -v`.

### Persistence

All data is stored at `DATA_DIR` (set in `.env`, default `/opt/monitor_stack`). This is a plain host directory — Docker has no control over it. It survives container restarts, image rebuilds, and `docker compose down`. Only `destructive-recreate.sh` and `destroy-stack.sh` will remove it.

```
/opt/monitor_stack/
  db/        ← MariaDB files
  librenms/  ← RRD graphs, discovered device data, logs
```

Back it up with rsync or any standard file backup. To start from scratch use `destructive-recreate.sh`.

---

## Puppet Module — syslog_forward

Replaces `x_rsyslog`. Self-contained module that handles the full local-log-suppression + central-forwarding stack in one place:

| What | How |
|---|---|
| journald | Drop-in sets `Storage=none` + `ForwardToSyslog=yes` — no disk or RAM journal, everything goes to rsyslog |
| rsyslog | `49-syslog-forward.conf` forwards `*.*` to LibreNMS over TCP then `& stop` — nothing written to `/var/log/` |
| Logrotate | Not managed — nothing to rotate |
| Legacy cleanup | Removes `99-syslog-forward.conf` if present from older versions |

### Install

```bash
cp -r puppet/modules/syslog_forward /etc/puppetlabs/code/environments/production/modules/
```

### Replace x_rsyslog

In `Compatible.yaml` (or wherever `x_rsyslog` is declared), swap it out:

```yaml
classes:
  - 'syslog_forward'
  # remove 'x_rsyslog' — syslog_forward replaces it entirely
```

### Hiera

Add to `all.yaml` (or your equivalent "all nodes" layer):

```yaml
syslog_forward::host: '10.1.1.60'
syslog_forward::port: 514
```

### Apply to nodes

```puppet
include syslog_forward
```

Queues 10,000 messages in memory if LibreNMS is unreachable, flushes when it comes back.

### Verify

```bash
logger "test from $(hostname)"
```

Check LibreNMS > Devices > (your device) > Syslog.

---

## SNMP on Debian hosts

LibreNMS polls via SNMP. Each Debian VM needs `snmpd` installed and configured:

```bash
apt install snmpd
```

Minimal `/etc/snmp/snmpd.conf`:
```
rocommunity public
# Expose CPU, memory, disk, swap, I/O via UCD-SNMP-MIB
disk /
disk /var
```

Restart: `systemctl restart snmpd`

LibreNMS will discover and start graphing CPU, memory, swap, disk, load, I/O, and interfaces automatically once the device is found.

### Monitoring specific processes (e.g. Puppet server)

Add `proc` lines to `/etc/snmp/snmpd.conf` to expose process counts via SNMP:

```
# Alert if puppetserver process count drops below 1
proc puppetserver 1
```

LibreNMS picks these up automatically under **Device > Processes** and can alert if the count goes to zero.

### Monitoring specific TCP ports (services)

Use LibreNMS's **Services** feature for Nagios-style TCP port checks — useful for checking that Puppet (8140), a web app, or any other service is actually accepting connections:

1. **Device > Services > Add Service**
2. Type: `tcp`
3. Parameters: `-H 127.0.0.1 -p 8140`
4. Set alert thresholds

This alerts if the port stops accepting connections, independently of SNMP.

---

## Replacing NMIS9

| NMIS9 function              | LibreNMS equivalent                          |
|-----------------------------|----------------------------------------------|
| SNMP polling (all metrics)  | Built-in poller — same MIBs, same data       |
| Auto-discovery              | Subnet sweep via `$config['nets']`           |
| Interface graphs            | Auto-generated per device                   |
| Host resource graphs        | CPU, mem, disk, swap, load — all built-in    |
| Syslog                      | syslog-ng sidecar on port 514               |
| Availability / alerting     | LibreNMS alerting (configure after setup)   |

NMIS9 can be switched off once LibreNMS has completed its first discovery sweep and you've verified devices are appearing.
