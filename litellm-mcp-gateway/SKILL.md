---
name: litellm-mcp-gateway
description: >-
  Use when designing or operating LiteLLM as the IntegriBilt MCP gateway:
  toolsets as the primary tool surface, context-window control, dynamic
  toolset assignment to projects/models, object_permission ceilings,
  mcp_servers, mcp_access_groups, mcp_tool_permissions, MCP tool search,
  semantic filtering, OAuth, and JWT. Trigger on MCP gateway, toolset,
  too many tools, context window tools, assign toolset, MCP profile,
  x-mcp-servers, or MCP JWT.
version: 1.1.0
author: IntegriBilt
license: Proprietary
metadata:
  hermes:
    tags: [integribilt, litellm, mcp, toolsets, context-window, permissions, oauth]
    related_skills: [litellm-authentication-security, litellm-skills-gateway-integration, litellm-proxy-configuration]
---

# LiteLLM MCP Gateway - IntegriBilt

## Purpose

Operate LiteLLM so agents get the **right tools for the job** without flooding the context window — and without accidentally exposing the whole MCP catalog.

IntegriBilt priorities (2026-07-11):

1. **Correct tools** — missing the browser (or DB, or Revit) tool when needed is worse than a slightly wider allowlist.
2. **Context hygiene** — too many MCP tool schemas cloud the prompt; this is the primary operational worry.
3. **Explicit ceilings** — keys must not omit MCP permissions (omitted ≈ open). OSS only; no Enterprise.

## North-star rules

1. Global MCP registry is not global MCP access.
2. If a harness/project is assigned **N** MCP servers, it must see **those N or fewer** — never the whole registry. N is not capped at 5; 5 was an example, not a limit.
3. **Toolsets are the primary control surface** for what the model actually sees day-to-day.
4. Server allowlists are the **ceiling**; toolsets (and tool permissions) are the **active toolkit**.

## Why toolsets matter more than server count

MCP servers often expose dozens of tools each. A project that needs:

- browser automation
- Slack notify
- internal docs search
- a readonly DB
- filesystem read

…may correctly need **5+ servers**, but the model should still see a **small named toolset** (often ~5–20 tools), not every tool those servers advertise.

| Layer | Job |
| --- | --- |
| `object_permission.mcp_servers` / access groups | Ceiling: which servers this key may ever touch |
| Toolset | Active kit: exact tools visible for this project/mode today |
| `mcp_tool_permissions` | Extra hard deny inside a server |
| MCP tool search | Last resort for legitimately huge catalogs (2 virtual tools) |
| Semantic filter | Relevance shrink only — not authorization; can fail open |

## Context-window guidance (practical)

There is no universal hard limit; schemas vary. Use these operating heuristics:

| Visible tools (approx) | Typical effect |
| --- | --- |
| 1–15 | Sweet spot for focused harnesses |
| 15–40 | OK for broad ops agents if tools are well named |
| 40–80 | Quality drop common; prefer toolsets or tool search |
| 80+ | Context clouding likely; do not leave this as default |

Symptoms of too many tools: wrong-tool calls, ignored tools, long TTFT, repetitive “which tool?” behavior, truncated system prompts.

**Fix order when the model is confused:** shrink toolset → add `mcp_tool_permissions` → enable MCP tool search → only then add semantic filter.

Browser-heavy work: prefer a **browser toolset** (navigate, click, type, snapshot) rather than attaching an entire browser MCP server with every debug/admin tool.

## Dynamic assignment (project / model / day)

Supported operating model:

- **Ceiling stays stable** on the key/team (servers this workload may use).
- **Active toolset changes** when the job changes.

Examples:

| Need | How |
| --- | --- |
| Project P uses toolset X | Key/team metadata `active_toolset: X`; client routes to `/toolset/X/mcp` or attaches toolset X |
| Model alias `ib-code` uses toolset X today, toolset Z tomorrow | Update the key’s attached toolset (or swap which toolset URL the harness points at). Do not recreate the whole key unless rotating |
| Same human, two modes | Two keys or two toolset routes under one team ceiling |

Preferred pattern:

~~~text
Team/key ceiling: [browser, docs, slack, db-readonly, filesystem-readonly]
Today's active toolset: estimating-browser-docs-v1
Tomorrow's active toolset: estimating-db-slack-v1
~~~

Both toolsets must be subsets of the ceiling. Changing the day-to-day kit should be a **toolset reassignment**, not opening MCP permissions.

Do not rely on the client omitting `x-mcp-servers` for safety — the key ceiling must already be correct.

## MCP profile (governance object)

Use a versioned profile (rename mentally to “harness profile” when it also carries models/budget):

~~~yaml
mcp_profile:
  id: project.estimating.v1
  owner_team: estimating
  environment: prod
  # Ceiling — may be >5 when the job truly needs it
  allowed_servers:
    - browser
    - internal-docs
    - spruce-db-readonly
    - filesystem-readonly
    - slack-notify
  # Active kits — swap these without changing the ceiling
  toolsets:
    default: estimating-readonly-v1
    browser_heavy: estimating-browser-docs-v1
    closeout: estimating-db-slack-v1
  default_model_alias: ib-balanced
  content_logging: false
~~~

Reflect ceiling into `object_permission`. Point the harness at the active toolset route.

## Key permission pattern (ceiling)

~~~json
{
  "team_id": "team-estimating",
  "models": ["ib-balanced", "ib-code", "ib-embedding"],
  "object_permission": {
    "mcp_servers": [
      "browser",
      "internal-docs",
      "spruce-db-readonly",
      "filesystem-readonly",
      "slack-notify"
    ]
  },
  "metadata": {
    "owner_team": "estimating",
    "environment": "prod",
    "project": "estimating",
    "active_toolset": "estimating-browser-docs-v1"
  }
}
~~~

Rules:

- Never omit MCP permission fields on production keys (WP-A finding: 18/18 were open).
- Prefer explicit `mcp_servers` snapshots for production; access groups for authoring.
- Before registering the **first** MCP server on the gateway, patch existing keys to deny-by-default or explicit lists.

## Toolsets (primary)

Create named toolsets for task bundles. Examples:

- `posted-journals-prod-v1`
- `estimating-browser-docs-v1`
- `infra-diagnostics-v1`
- `revit-readonly-v1`

Use a toolset when:

- Servers expose unrelated tools
- Tool count risks context clouding
- The same bundle must move between projects/models quickly
- A skill declares `allowed_toolsets`

Client route shape (conceptual):

~~~text
litellm_proxy/mcp/<toolset_name>
# or
/toolset/<toolset_name>/mcp
~~~

## MCP tool search

Replaces a huge catalog with roughly two virtual tools (`mcp_tool_search`, `mcp_tool_call`). Use for exploratory admin/dev agents that legitimately span many servers **after** the ceiling is set.

Do not use tool search as the only isolation mechanism.

## Semantic tool filtering

Shrinks prompt size by relevance. Improves usability; **not** authorization; can fail open. Optional after toolsets.

## Selectors versus enforcement

| Mechanism | Use | Ceiling / auth? |
| --- | --- | --- |
| object_permission.mcp_servers | hard server allowlist | Yes |
| object_permission.mcp_access_groups | group allowlist | Yes (watch drift) |
| object_permission.mcp_tool_permissions | hard tool allowlist | Yes |
| MCP toolsets | exact visible kit | Yes when attached |
| Scoped URL / x-mcp-servers | pick among allowed | No (selector) |
| MCP tool search | catalog minimization | Needs ceiling |
| Semantic filter | relevance | No |

## Zero-trust and OAuth

Dangerous MCP servers should verify LiteLLM-signed JWTs (JWKS) so direct bypass fails. Use PKCE / M2M / OBO intentionally. For OAuth MCPs, gateway key may need `x-litellm-api-key`.

## Phase-1a sequencing (IntegriBilt)

1. Inventory keys (done 2026-07-11).
2. Default-deny / explicit MCP on all keys **before** registering servers.
3. Close ALL_MODELS keys; add budgets/teams.
4. Register MCP servers; define toolsets; wire projects to active toolsets.
5. Skills marketplace publish after Git push.

## Acceptance tests

1. List tools with harness key → only active toolset (or assigned servers) appear.
2. Unassigned server path → deny.
3. `x-mcp-servers` with one assigned + one unassigned → unassigned hidden.
4. Disallowed tool on allowed server → deny.
5. Same key without selector → still within ceiling.
6. Swap active toolset X → Z for same key/model → visible tools change; ceiling unchanged.
7. Tool count under the context heuristic for that harness.
8. Traces/spend include team/harness/toolset metadata.

## Troubleshooting

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| Hundreds of tools | missing permissions or no toolset | ceiling + toolset |
| Right servers, wrong/extra tools | no toolset / tool permissions | attach toolset |
| Missing browser (or needed tool) | toolset too tight or server not in ceiling | widen ceiling or toolset intentionally |
| Model ignores tools / flails | context clouding | shrink toolset or enable tool search |
| OAuth MCP fails | header/token flow | check `x-litellm-api-key` |

## Review checklist

- Is the ceiling explicit on the key/team?
- Is the **active toolset** named, versioned, and small enough for context?
- Can today’s kit swap to tomorrow’s without opening the catalog?
- Are dangerous servers JWT-protected?
- Are traces tagged with project + active_toolset?
