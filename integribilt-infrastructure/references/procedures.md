# IntegriBilt Procedures

Approved command patterns. Verify the target host, service, and current state before any
change. Never paste a secret into chat, a log, or a file.

## Remote access (Tailscale only)

SVR02 from any tailnet machine, no setup needed:

```bash
ssh lmiller@integribilt.local@100.84.138.13 'hostnamectl; uptime'
```

Copy a file:

```bash
scp lmiller@integribilt.local@100.84.138.13:/home/lmiller/integribilt-stack/RUNBOOK.md .
```

Where the IntegriBilt SSH alias is installed (`install-doctrine` adds it to
`~/.ssh/config`), `svr02` is shorthand for the same thing, and the examples below use it:

```bash
ssh svr02 'hostnamectl; uptime'
```

To check whether the alias is installed: `ssh -G svr02` prints `hostname 100.84.138.13`.
If it prints anything else, use the full form.

Checks when it fails:

```bash
tailscale status
tailscale ping svr02
tailscale ip -4 svr02
```

- "Could not resolve hostname": tailnet DNS is broken on this machine. Use the `100.x`
  address. Do not switch to the LAN address.
- "tailnet policy does not permit you to SSH": retry once. If it repeats, the Tailscale
  ACL needs a rule. Report it. Do not use a key.
- Never use `ssh -i`, `ssh-keygen`, `ssh-copy-id`, or `authorized_keys`.

Windows hosts: `Enter-PSSession -ComputerName <tailnet-name>` or RDP to the tailnet
address, under the AD account.

## SVR02 health snapshot (read-only)

```bash
ssh svr02 'uptime; free -h; df -h | grep -E "Filesystem| /$|/srv|/mnt/nas"; docker ps --format "table {{.Names}}\t{{.Status}}" | head -100'
ssh svr02 'docker ps -a --filter status=restarting --filter status=exited --format "{{.Names}}|{{.Status}}"'
```

Logs for one service:

```bash
ssh svr02 'docker logs --tail=100 <container-name>'
```

Host DNS and Docker DNS (both must point at `.17`):

```bash
ssh svr02 'resolvectl dns bond0; ls -l /etc/resolv.conf; docker exec paperclip getent hosts api.anthropic.com'
```

If `docker` commands hang, check `uptime` first: load above 40 from crash-looping
containers makes the daemon slow. Do not restart Docker to "fix" that.

## Compose: the one YAML

Paths:

- SVR02 master: `/home/lmiller@integribilt.local/integribilt-stack/docker-compose.yml`
  (`/home/lmiller/integribilt-stack` is a symlink to it).
- OFC01 clone: `E:\clones\docs\integribilt-stack\docker-compose.yml`.
- Known exception: SVR02 also has `docker-compose.override.yml` (Zabbix ports, agent
  hostname, docker group). Compose loads it automatically. It should be folded into
  `.env` variables; do not extend it.

Plain `docker compose config`, `ps`, `up` and `logs` fail on both hosts unless the
Bitwarden secrets are in the environment, because some services declare required
variables (for example paperless-ngx needs `MAXMIND_LICENSE_KEY`). So:

- Read-only checks: use `docker ps`, `docker logs`, and `docker inspect`. They need no
  secrets.
- Start, update, restart: use the start scripts. They inject the secrets themselves.
  `start-stack.sh` loads `.env`, reads the BWS token from
  `~/.config/integribilt/bws.env` (or `/etc/integribilt/bws.env`), injects `bws secret
  list` into the compose process, and falls back to `.env` with a warning if BWS fails.
  Verified working 2026-11-16.
- Validate a compose edit: `bws run -- docker compose --profile <profile> config --quiet`.

Reported blocker (2026-10-03, not re-verified since): `bws run` stops with "Multiple
secrets with name: 'Paperless_NGX'". Until that duplicate secret is renamed in Bitwarden,
`bws run` may fail on any host. Do not work around it by exporting every secret into
your shell. Ask for the duplicate to be fixed, and validate through the start script on
the next deploy.

Start or update:

```bash
ssh svr02 'cd /home/lmiller/integribilt-stack && ./start-stack.sh svr02 <service>'
```

```powershell
cd E:\clones\docs\integribilt-stack; .\start-stack.ps1
```

Change flow for any compose edit:

1. `git pull` on the host you are editing.
2. Edit `docker-compose.yml`. A per-host value becomes `${NAME:-default}` with the real
   value in that host's `.env`. Never create `docker-compose.override.yml`.
3. Validate both profiles.
4. `git add docker-compose.yml && git commit && git push` the same day.
5. `git pull` on the other host.
6. Only then start or restart the affected service.

Per-host variables already in use:

| Variable | SVR02 `.env` | OFC01 `.env` |
|---|---|---|
| `ZABBIX_WEB_PORT` | 8093 | default 8090 |
| `ZABBIX_SNMPTRAPS_PORT` | 1162 | default 162 |
| `ZABBIX_AGENT_HOSTNAME` | Zabbix server | default |
| `DOCKER_SOCK_GID` | 987 | default 0 |
| `NET_MONITORING_SUBNET` | default 172.22.0.0/16 | 10.86.22.0/24 |
| `NET_SECURITY_SUBNET` | default 172.23.0.0/16 | 10.86.23.0/24 |
| `NET_BEASTMODE_SUBNET` | default 172.24.0.0/16 | 10.86.24.0/24 |
| `NET_OPENREMOTE_SUBNET` | default 172.25.0.0/16 | 10.86.25.0/24 |

OFC01 needs the subnet overrides because Docker Desktop extensions already hold
172.22 through 172.25 there.

Cleanup guardrail: `docker system df` is safe. Anything that deletes containers, images,
networks, or volumes needs Lester's explicit approval. Never prune volumes. Run large
prunes (`docker builder prune`) off-hours: on 2026-11-16 a 106 GB build-cache prune drove
load to 57 and stalled the daemon for an hour.

Docker daemon changes (`/etc/docker/daemon.json`) need `live-restore: true` so a daemon
restart keeps containers running. After a DNS change there, recreate the containers that
need the new list; they do not pick it up on their own.

## Secrets (Bitwarden Secrets Manager)

Inject for one command, nothing written to disk (may be blocked by the duplicate secret
name noted above):

```bash
bws run -- <command>
```

Read one value inside a script without printing it:

```bash
VALUE="$(bws secret get <SECRET_ID> | jq -r '.value')"
```

```powershell
$value = (bws secret get <SECRET_ID> | ConvertFrom-Json).value
```

Check availability without revealing anything:

```powershell
Get-Command bws; if ($env:BWS_ACCESS_TOKEN) { "token set" } else { "token missing" }
```

Rules: refer to secrets by name. Do not create local password files. Do not put a secret
in a compose file, an MCP config, or a Buzz message. If one leaks, rotate it in Bitwarden
at once; deleting the message is not enough. When you must inspect a container's
environment, print variable names only (`env | cut -d= -f1`), never values.

## LiteLLM gateway

Health, then what your key can see. `$env:LITELLM_API_KEY` stands for your own virtual
key, already in your environment; never type a key into a command:

```powershell
Invoke-RestMethod http://192.168.254.2:4000/health/readiness
$h = @{ 'x-litellm-api-key' = "Bearer $env:LITELLM_API_KEY" }
(Invoke-RestMethod http://192.168.254.2:4000/v1/models -Headers $h).data.id
```

MCP servers registered on the gateway (names only):

```powershell
Invoke-RestMethod http://192.168.254.2:4000/v1/mcp/server -Headers $h | ForEach-Object { $_.alias }
```

Skills published on the gateway (no key needed once the index is on):

```bash
curl -s http://192.168.254.2:4000/.well-known/agent-skills/index.json | jq '.skills[] | {name, url, digest}'
curl -s -o integribilt-infrastructure.zip "$(curl -s http://192.168.254.2:4000/.well-known/agent-skills/index.json | jq -r '.skills[] | select(.name=="integribilt-infrastructure") | .url')"
unzip -l integribilt-infrastructure.zip
```

Publish a new skill version (admin key, DB-backed, no YAML):

```bash
cd <skill folder> && zip -r ../skill.zip SKILL.md references/
curl -s -X POST "http://192.168.254.2:4000/v1/skills?custom_llm_provider=litellm_proxy&beta=true" \
  -H "Authorization: Bearer $LITELLM_ADMIN_KEY" \
  -F "display_title=<name>" -F "description=<one line>" -F "files[]=@../skill.zip"
```

Rules: one virtual key per consumer, named for the consumer, with a budget. Models, keys,
MCP servers, and skills are stored in LiteLLM's database; change them in the admin UI
(`http://192.168.254.2:4000/ui`) or the API, not in a file. `/srv/core/litellm/config.yaml`
holds only process-level settings and an empty `model_list`; leave it alone.

Local models: LiteLLM's `local/*` names forward to LM Studio on OFC01 port 1234. If they
fail, start the server on OFC01:

```powershell
& "$env:USERPROFILE\.lmstudio\bin\lms.exe" server start --bind 0.0.0.0 --port 1234
```

## Paperclip

Paperclip runs in `authenticated` mode. `GET /api/companies` returns 403 without a board
session or a board API key. Create board API keys in the UI, store them in Bitwarden, and
never pass one on a command line. Agent keys are created with `POST /api/agents/{id}/keys`
and shown once. If connectors fail to add, check Docker DNS first (see health snapshot):
on 2026-11-16 a stale container DNS list made every outbound lookup take 8 to 24 s.

## Odoo backups

```bash
ssh svr02 'systemctl list-timers odoo-backup.timer; journalctl -u odoo-backup -n 30 --no-pager'
ssh svr02 'df -h / /srv/keystore; ls /srv/keystore/odoo-backups; ls /mnt/nas/odoo'
```

If `/mnt/nas/odoo` is empty, start the automount: `systemctl start mnt-nas-odoo.automount`
then list it again. A manual run is `systemctl start odoo-backup.service`; it prunes
local staging first, dumps, copies to the NAS, and verifies the copy.

## Guarded hosts

Domain controllers (SVR07, SVR17): read-only checks only without explicit approval.

```powershell
nltest /dsgetdc:integribilt.local
repadmin /replsummary
```

SVR12 (SQL and MiTek): confirm the instance, the database, the backup state, and the
maintenance window before any change. No generic SQL without the exact database and a
rollback.

```powershell
Get-Service | Where-Object { $_.DisplayName -match 'SQL|MiTek' }
```

Front counter (FC01, FC02): confirm nobody is selling, get approval for downtime, and
verify the cash drawer and card machine afterward.

## Storage triage

```bash
ssh svr02 'df -h; docker system df; sudo du -h --max-depth=2 /srv | sort -rh | head -20'
```

Run `du` with `sudo`; without it root-only directories read as 4 KB and hide the problem.
Deletion, truncation, or cleanup needs explicit confirmation and a rollback note.
