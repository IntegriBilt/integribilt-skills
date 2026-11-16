# IntegriBilt Infrastructure Reference

Baseline as of 2026-11-16 (2.0 baseline of 2026-10-03, corrected against the live host).
The live `docker-compose.yml`, Bitwarden, and read-only commands outrank this file.
Verify before changing anything.

## Network

- LAN: `192.168.254.0/24`. Server OS addresses are `.X`; iDRAC is `.X+200`.
- Gateway: Fortinet at `192.168.254.1`. WAN is a Verizon hotspot (CGNAT, path MTU 1428,
  bulk downloads around 130 KB/s on 2026-11-16). Slow image pulls and package installs are
  expected. Plan big pulls off-hours and keep tests on local models and cached dependencies.
- Tailnet: `tail7254e6.ts.net`. Policy is managed by GitOps in `IntegriGit/Tailnet-Sync`
  (push to main applies it). SVR02 runs Tailscale with `accept-dns=false`, `accept-routes`,
  SSH on, no exit node.
- DNS for `integribilt.local`: SVR17 `192.168.254.17` first, SVR07 `192.168.254.7` second.
  `.3` no longer exists. On 2026-11-16 only `.17` answered. Do not point anything at `.1`.
- SVR02 host network: `bond0` = `eno1` + `eno2` (`balance-alb`), netplan file
  `/etc/netplan/99-eno1-static.yaml` (renderer networkd), systemd-resolved with the stub
  listener off and `/etc/resolv.conf` a symlink to `/run/systemd/resolve/resolv.conf`.
  There is no working IPv6 default route; the dead `fd00:254:254:1::1` route was removed
  on 2026-11-16. An agent once replaced `resolv.conf` with a plain file pointing at `.1`
  and broke the chain; keep the symlink.
- Docker daemon DNS on SVR02 (`/etc/docker/daemon.json`): `192.168.254.17`, `8.8.8.8`,
  search `integribilt.local`, `live-restore: true`. Containers keep the DNS list they
  started with; after a daemon DNS change, recreate the container.

## SVR02 (primary Docker hub)

- Dell PowerEdge, Ubuntu 25.10 (verified 2026-11-16). iDRAC `192.168.254.202` is the
  break-glass console.
- Account: `lmiller@integribilt.local` (AD, passwordless sudo). Home is
  `/home/lmiller@integribilt.local`; `/home/lmiller` is a symlink to it. The old local
  `lmiller` account is not used.
- Docker Compose v5.4.0. Stack directory: `/home/lmiller@integribilt.local/integribilt-stack`.
  Docker data-root is `/srv/docker` (not `/var/lib/docker`).

Disks (verified 2026-11-16):

| Device | Size | Mount | Purpose |
|---|---|---|---|
| `sdd` | 223 GB | `/` (LVM `ubuntu-vg/ubuntu-lv`), `/boot`, `/boot/efi` | OS only. Nothing large belongs here |
| `sdb` | 1 TB | `/srv` | Container data (`core/`, `biz/`, `mon/`, `sec/`, `doc/`) and Docker data-root `/srv/docker` |
| `sda` | 1 TB | `/srv/graphdb` | Neo4j data |
| `sdc` | 1 TB | `/srv/keystore` | Odoo backup staging (`/srv/keystore/odoo-backups`); otherwise mostly free |
| NAS | 31 TB | `/mnt/nas/odoo` | SVR09 export `/mnt/Vaultcore/odoo-backup`, NFSv3, `hard` + systemd automount |

On 2026-11-16 the OS disk hit 93% because Odoo backups were staged on it. Watch
`df -h / /srv` first in any disk incident. Known leftovers on the OS disk: `/var/log`
(about 9 GB of syslog and journal) and `/propagated-mount` (14 GB Paperclip backup copy).

Service map (`svr02` profile, 77 services):

- Edge: traefik (8443; 8088 was not listening on 2026-11-16), pihole (53, 8053),
  next-site, clearcam + clearcam-proxy.
- Data: postgres pgvector (5432), mariadb (3306), mongodb (27017), redis-cache (6381),
  redis-timeseries (6380), neo4j (7474, 7687), odoo-db (LAN 5433).
- AI: litellm-proxy (4000), openwebui (3005), langfuse (3006), ollama (11434),
  agent-zero (50001), paperclip (3110, public 8443 via Tailscale Serve), omnigent (8005),
  honcho-api (8008) with honcho-deriver, honcho-database, honcho-redis (6384), lap (4001)
  with lap-opencode and lap-deepagents, gitea-skills (3002), antigravity-proxy with
  mcp-nginx-proxy (8445).
- Business: odoo (8069, idle since mid-2026), invoiceninja (8030), snipe-it (8001),
  netbox (8003), bookstack (8050), paperless-ngx (8010), actual (5006), n8n-server (5678),
  gitea (3007).
- Monitoring: prometheus (9091), grafana (3003), loki (3100), promtail, cadvisor (9080),
  netdata (19999), opennms (8980), uptime-kuma (3310), beszel (8090), dozzle (8081),
  portainer (9443).
- Security: graylog (9000) with opensearch and mongo, geoipupdate, wazuh manager,
  indexer, and dashboard.
- Backups: postgres-backup, mariadb-backup, mongodb-backup, redis-backup, backup-manager.
- Zabbix: server, web (8093), agents, snmptraps (1162). Tagged `ofc01` in the compose
  file but running on SVR02 since July 2026; `start-stack.sh svr02 zabbix-server` starts
  it because naming a service enables its profile.
- Kasm (outside compose, `/opt/kasm/1.19.0`): proxy, api, manager, agent, guac, rdp
  gateways, db.

## Odoo backups

- Chain: `odoo-backup.timer` (weekly, Sunday 02:30, because Odoo is idle) ->
  `odoo-backup.service` -> `/usr/local/sbin/odoo-backup.sh`, config in
  `/etc/default/odoo-backup`.
- Staging: `/srv/keystore/odoo-backups`, pruned before each run (`LOCAL_RETAIN_DAYS=1`).
  Archive: `/mnt/nas/odoo` on SVR09, 14-day retention. The service has
  `RequiresMountsFor=/mnt/nas/odoo`.
- The NAS stalls in short cycles under sustained writes but not on reads; the mount is
  `hard` so a stall waits instead of returning EIO. Originals of every changed file are
  kept beside it as `*.bak-<timestamp>`.

## OFC01 (workstation)

- Windows 11, AD user `INTEGRIBILT\lmiller`, profile `C:\Users\lmiller.INTEGRIBILT`.
- Drives: `C:` OS, `E:` projects, clones, repos.
- Docker Desktop on WSL2. Its extensions occupy 172.18 through 172.31, which is why the
  compose networks take their subnets from `NET_*_SUBNET` in OFC01's `.env`.
- GPUs: RTX 3090 24 GB and RTX 2080 Super 8 GB.
- Thin-client Google Drive folders on OFC01 are placeholders; copy files over the tailnet
  or SMB, not from the Drive mirror.

What runs here outside compose:

- Hermes Agent, native, home `%LOCALAPPDATA%\hermes\`. One gateway serves profiles
  default, cletus, jackson, rocky. API `:8642`.
- LM Studio (also branded Bionic), models in `%USERPROFILE%\.lmstudio\models`,
  server `:1234`.
- Buzz Desktop and its agents. Registry at
  `%APPDATA%\xyz.block.buzz.app\agents\managed-agents.json`.
- Coding harnesses: Claude Code, Codex, Cursor, Gemini CLI, Antigravity, OpenCode, Goose,
  Grok.

`ofc01` profile services (36 tagged in the compose file on 2026-11-16): the Buzz relay
stack, Superset, OpenRemote, beastmode, voicebox, metasploit with its MCP,
model-runner-proxy, openwebui-mcp-gateway, n8n-desktop, archivebox,
mcp-filesystem-desktop, and the Zabbix definitions.

## Memory stores and who owns what

Decisions from MEMORY-BLUEPRINT v1.0 (2026-07-07) and its review (2026-07-15):

| Kind of memory | Store | Status |
|---|---|---|
| Hermes conversations and user model | Honcho on SVR02 `:8008` | Live. On probation; verdict overdue since 2026-08-07 |
| Agent task state | Paperclip database | Live |
| Agent mailbox and scratch | redis-cache `:6381`, DB 7, keys `agent:{host}:{task-id}` | Convention only. Durability unverified |
| Relationships | Neo4j, named database | Live. Keep |
| Semantic search | Postgres with pgvector | Planned |
| Raw lake | MinIO on SVR02 | Planned. Needs a second copy before use |
| Per-harness memory | Claude `~/.claude/projects/*/memory`, Codex `~/.codex/memories`, Hermes `memories/MEMORY.md` | Live, not shared |
| Team conversation log | Buzz relay (Block-hosted) | Live. Not private, kept indefinitely |

Retired: Antigravity Storage Manager (it only syncs Antigravity chats to Google Drive),
the SVR02 MCP memory containers (removed 2026-07-04), and the `:8445` Neo4j and Redis MCP
routes that depended on them. Verified 2026-11-16: no ASM or MCP memory container exists;
`mcp-nginx-proxy` still listens on 8445 but `/neo4j/`, `/redis/` and `/memory/` do not
answer. Any document that tells you to set up ASM is out of date.

Rule: no new memory store and no new Redis instance. Use what is listed here.

## Criticality

- Network-critical: SVR07, SVR17 (domain, DNS, DHCP).
- Business-critical: SVR12 (SQL Server, MiTek).
- Sales-critical: FC01, FC02 during business hours.
- Infrastructure-critical: SVR02 (everything in Docker), SVR09 (storage and backups).

## Known issues (2026-11-16)

- `kasm_agent` stopped: its `agent.app.config.yaml` is all NUL bytes and needs regenerating.
  `kasm_rdp_https_gateway` restarts on an expired token (2026-11-11).
- `wazuh-manager` restarts: `/srv/sec/wazuh/manager/etc/ossec.conf` is missing.
- `invoiceninja` has crash-looped since 2026-10-18.
- Unhealthy at last check: beszel (healthcheck needs `--url`), bookstack, clearcam-proxy
  (502), graylog, heimdall, kasm_guac, langfuse, snipe-it.
- Host load runs 40 to 60 while the crash loops continue; timing-based tests should wait.
- SVR07 (`.7`) unreachable from SVR02.
- Docs mirror `/home/lmiller/integribilt-docs-mirror` is stale (2026-07-04) and its clone
  has diverged from origin.
