---
name: integribilt-infrastructure
description: IntegriBilt infrastructure facts and rules. Hosts and addresses, Tailscale-only remote access, the single shared docker-compose.yml (SVR02 master, OFC01 clone), Bitwarden Secrets (bws), the LiteLLM gateway for models, MCP tools and skills, local models on OFC01, Hermes, Paperclip, Honcho, Buzz, monitoring, backups, and safe change procedures. Use for any question or task about IntegriBilt servers, services, ports, deployments, secrets, model names, or how an agent connects to something.
version: 2.1
---

# IntegriBilt Infrastructure

Version 2.1, 2026-11-16. Merged from 2.0 (2026-10-03) plus facts verified live on SVR02
on 2026-11-16. This skill holds facts and procedures. The rules themselves are in
`AGENTS.md` (IntegriBilt Operating Doctrine). If this skill and the doctrine disagree, the
doctrine wins. If this skill and the live system disagree, the live system wins: verify
before you change anything.

Canonical copy: `integribilt-infrastructure/` in the GitHub repo
`IntegriBilt/integribilt-skills` (branch `master`). Every change is committed there first,
then published to the LiteLLM skills gateway on SVR02 (see "Skills and MCP"), then
installed to `~/.agents/skills/` (and `~/.claude/skills/`) on every machine. Do not edit
an installed copy. The repo path named by 2.0, `integribilt-stack/agents/skills/`, does
not exist. Commits in this repo before 2026-11-16 still documented ASM and the `:8445`
memory routes; both are retired.

## The five rules that cause the most damage when broken

1. **Tailscale only.** Reach hosts over the tailnet. SVR02 is
   `ssh lmiller@integribilt.local@100.84.138.13` (or `ssh svr02` where the alias is
   installed). No `ssh -i`, no keys, no LAN SSH to a tailnet host. If Tailscale fails,
   report it and stop.
2. **One YAML.** One `docker-compose.yml` for SVR02 and OFC01. No override files, no
   copies, no `docker run` for managed services. Per-host differences are `.env` variables.
   Known exception on disk: SVR02 has a `docker-compose.override.yml` (Zabbix ports and
   agent hostname, dated 2026-07-15) that Compose loads automatically. Fold it into `.env`
   variables; do not add to it and do not create another.
3. **Bitwarden Secrets (`bws`) always.** Never write, echo, or paste a secret. Name it.
4. **One door.** Models, MCP tools, and skills come through LiteLLM on SVR02. Hermes keeps
   its own skills and MCP servers. Claude Code and Codex use their subscriptions.
5. **Read-only first.** Diagnose with read-only commands, show the evidence, then act.

High-risk actions need explicit confirmation from Lester: disk or partition changes,
deleting data, Docker volume or system prune, credential rotation, database restore,
firewall or routing changes, OS upgrades, compose edits on a live host, anything touching
domain controllers, SQL, MiTek, or the front counter during business hours.

## Hosts

| Host | LAN | Tailnet | Role |
|---|---|---|---|
| SVR02 | 192.168.254.2 | 100.84.138.13, `svr02` | Ubuntu 25.10 Docker hub. iDRAC 192.168.254.202 |
| OFC01 | 192.168.254.86 | `ofc01-windows` | Windows 11 workstation. RTX 3090 24 GB + RTX 2080 Super 8 GB |
| SVR12 | 192.168.254.12 | `svr12` | SQL Server and MiTek. Business-critical |
| SVR15 | 192.168.254.15 | `svr15-1` | Print server, agent host. iDRAC .215 |
| SVR07, SVR17 | .7, .17 | - | Domain controllers, DNS, DHCP. Network-critical. Use .17 first |
| SVR09 | 192.168.254.9 | `truenas-scale` | TrueNAS storage, NFS exports. iDRAC .209 |
| FC01, FC02 | verify | `fc01`, `fc02` | Front counter, cash drawers, card machines. Sales-critical |
| LT01 | verify | `lt01` | Lester's laptop |
| Spruce | 192.168.254.29 | - | Legacy ERP. Read-only |
| SVR10 | - | - | Removed from inventory. Do not plan work for it |

Tailnet name suffix: `tail7254e6.ts.net`. Only SVR02 runs the Tailscale SSH server today.
Windows hosts cannot run it; use RDP or PowerShell remoting over the tailnet address.
Gateway is a Fortinet at 192.168.254.1. The site WAN is a Verizon hotspot: slow pulls are
normal, not a fault (see `references/infrastructure.md`, Network).

## Where things run

SVR02 (`svr02` profile), ports verified listening 2026-11-16:

| Service | Address | Notes |
|---|---|---|
| LiteLLM gateway | `http://192.168.254.2:4000` | Models at `/v1`, MCP at `/mcp/`, skills index at `/.well-known/agent-skills/index.json`, admin UI at `/ui` |
| Paperclip | `http://192.168.254.2:3110` | Agent company, tickets `INT-###`. Public URL `https://svr02.tail7254e6.ts.net:8443`. Runs in `authenticated` mode: API writes need a board session or board API key |
| Honcho | `http://192.168.254.2:8008` | Hermes memory. Self-hosted |
| Open WebUI | `http://192.168.254.2:3005` | Chat UI on LiteLLM |
| Langfuse | `:3006` | Defined, not wired to LiteLLM yet |
| Omnigent | `:8005` | Agent coordinator, dormant |
| Neo4j | `:7474`, `:7687` | Graph store on `/srv/graphdb`. Access through MCP, not raw |
| redis-cache | `:6381` | Scratch. DB 7 reserved for agent state |
| Ollama | `:11434` | Embedding model only |
| Grafana / Prometheus / Graylog | `:3003` / `:9091` / `:9000` | Monitoring |
| Zabbix web | `:8093` | Zabbix now runs on SVR02 |
| gitea-skills | `:3002` | Git host for skills (web UI only; its API path returned 404 on 2026-11-16) |

OFC01:

| Service | Address | Notes |
|---|---|---|
| Hermes gateway API | `http://192.168.254.86:8642` | One gateway, profiles default, cletus, jackson, rocky |
| LM Studio / Bionic server | `http://192.168.254.86:1234/v1` | Backs LiteLLM `local/*`. Must be started |
| Docker Model Runner | `127.0.0.1:12434` | Loopback only |
| Buzz relay (self-hosted) | `ws://192.168.254.86:3220` | Idle. The live relay is Block-hosted |

Live Buzz relay: `wss://integribilt.communities.buzz.xyz`. See the `integribilt-buzz` skill.

## Models

Base URL for every OpenAI-compatible client: `http://192.168.254.2:4000/v1`.
Full list: `GET /v1/models` with your virtual key. All names below existed on 2026-11-16
(94 models registered).

| Lane | Names | Use for |
|---|---|---|
| Local, free | `local/qwen3-14b`, `local/gpt-oss-20b` | Bulk work, drafts, privacy-sensitive text |
| Free cloud | `free/gemma-4-31b`, `free/gpt-oss-20b`, `free/nemotron-super-120b` | Drafts. Rate-limited |
| Cheap | `ib-fast`, `ib-code`, `ib-smart`, `ib-balanced`, `glm-5.3`, `kimi-k3` | Daily work |
| Frontier | `claude-fable-5`, `claude-sonnet-5`, `codex-5.6` | Leadership, architecture, security |
| Embeddings | `ib-embedding`, `ib-embedding-local`, `ib-embedding-ollama` | Retrieval |

`dmr/*` and `docker-*` names point at Docker Model Runner and are unreachable from SVR02.
Models live in LiteLLM's database, not a config file. Change them in the admin UI.
Every consumer has its own named virtual key with a budget (`paperclip`, `hermes`, `codex`,
`claude`, `opencode`, `openwebui`, the `buzz-*` agents, and so on).

## Skills and MCP

- Skills: `~/.agents/skills/<name>/SKILL.md` on every machine. OpenCode, Goose, and
  LM Studio read that folder. Claude Code reads `~/.claude/skills/`, which the installer
  fills with copies.
- Published skills: LiteLLM stores them in its database. Discover with
  `GET http://192.168.254.2:4000/.well-known/agent-skills/index.json`; each entry's `url`
  is `/v1/skills/<id>/archive`, a zip with `SKILL.md` at the root. Publish with
  `POST /v1/skills?custom_llm_provider=litellm_proxy` (admin key, multipart zip). The
  Anthropic-hosted `skill_01...` records that `GET /v1/skills` also lists are not served
  by the archive route.
- MCP: `http://192.168.254.2:4000/mcp/`, header `x-litellm-api-key: Bearer <virtual key>`.
  Servers are registered on the gateway and granted per key.
- Hermes: skills in `%LOCALAPPDATA%\hermes\skills\` and `profiles\<name>\skills\`; MCP
  servers under `mcp_servers:` in each profile's `config.yaml`.

## Reference files

- `references/infrastructure.md`: service map, disks, network, backups, memory stores,
  criticality, known issues.
- `references/procedures.md`: command patterns for access, health checks, compose changes,
  secrets, LiteLLM, backups, and the guarded hosts.
