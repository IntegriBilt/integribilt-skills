---
name: litellm-authentication-security
description: >-
  Use when securing the IntegriBilt LiteLLM Gateway: virtual keys, users, teams,
  organizations, budgets, rate limits, model allowlists, JWT/SSO/RBAC,
  guardrails, MCP object permissions, admin-key handling, BWS secret handling,
  and enterprise security tradeoffs. Trigger on LiteLLM auth, API key, virtual
  key, team, user, budget, RBAC, JWT, SSO, MCP permissions, guardrail, secret,
  admin key, object_permission, exact MCP access, or enterprise security.
version: 1.1.0
author: IntegriBilt
license: Proprietary
metadata:
  hermes:
    tags: [integribilt, litellm, security, auth, virtual-keys, teams, budgets, mcp, guardrails, bws]
    related_skills: [integribilt-infrastructure, litellm-proxy-configuration, litellm-mcp-gateway, litellm-monitoring-troubleshooting]
---

# LiteLLM Authentication and Security - IntegriBilt

## Purpose

Use this skill when the task touches security or governance for the IntegriBilt LiteLLM Gateway. The gateway is the control point for model access, provider secrets, virtual keys, teams, budgets, MCP server visibility, guardrails, spend attribution, and auditability.

Default stance: read-only first, least privilege always, no plaintext secrets ever.

## Known IntegriBilt gateway facts

- Gateway base URL for cross-host clients: http://192.168.254.2:4000
- Use explicit IP or DNS name for cross-host calls. Do not use localhost from another host.
- Gateway config source of truth is expected on SVR02 at /srv/core/litellm/config.yaml.
- Live stack source of truth is expected on SVR02 at /home/lmiller/integribilt-stack/docker-compose.yml.
- LiteLLM virtual keys are the only keys app code should see.
- Provider keys, master keys, OAuth client secrets, JWT signing keys, and database credentials come from BWS or the approved secret manager.

If any of those facts conflict with live state, live state wins, but call out the discrepancy.

## Non-negotiables

1. Never hardcode, print, echo, screenshot, commit, or save plaintext secrets.
2. Never put a provider key directly in an app, skill, LangChain app, LangGraph app, MCP server, notebook, or agent harness.
3. Use a LiteLLM virtual key for workloads; reserve the LiteLLM master/admin key for administration only.
4. Production keys must have an owner, team, environment, model allowlist, budget, and metadata.
5. Production keys that can use MCP must have explicit MCP permissions. Omitted MCP permissions can mean broad access.
6. If a harness is assigned five MCP servers, the key/team/agent permissions must expose exactly those five or fewer.
7. Do not broaden model or MCP access to make an error disappear. Fix the scoped policy.
8. Ask before destructive or broad administrative changes such as deleting keys, rotating shared secrets, changing RBAC, changing SSO/JWT config, or widening production access.

## Security object model

Use this mental model before changing anything:

| Object | What it controls | Required production fields |
| --- | --- | --- |
| Organization | Top-level ceiling for users/teams/projects | owner, budget, model ceiling, admin contacts |
| Team | Department/app/project access boundary | models, budget, TPM/RPM, MCP ceiling, logging policy |
| User | Human identity and accountability | email/user id, role, team membership, optional budget |
| Virtual key | Workload or user credential | key_alias, team_id, models, budget, duration, metadata, MCP permissions |
| Agent | Agent/harness identity | model, team, MCP profile, budget, trace metadata |
| End user | Per-user runtime scope | x-litellm-end-user-id when user-level MCP/budget enforcement matters |

The safest pattern is org ceiling > team policy > workload virtual key > optional agent/end-user intersection.

## Standard workflow

1. Identify the actor: human, service, harness, app, agent, CI job, or MCP client.
2. Identify the owner team and environment.
3. Identify required model aliases only.
4. Identify required MCP profile, if any.
5. Set budget and rate limits before issuing credentials.
6. Add trace and spend metadata.
7. Test least-privilege access, then test denial of unassigned access.
8. Store any newly generated secret only in BWS or the approved secret path.

## Virtual key generation pattern

Use the LiteLLM admin API only with the master/admin key loaded from BWS into an environment variable. Do not paste secrets into the shell history.

~~~bash
export LITELLM_BASE_URL=http://192.168.254.2:4000
export LITELLM_MASTER_KEY="from BWS at runtime"

curl -sS -X POST "$LITELLM_BASE_URL/key/generate" \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d @key-request.json
~~~

Example key-request.json shape:

~~~json
{
  "key_alias": "svc-posted-journals-prod",
  "team_id": "team-accounting-ai",
  "models": ["ib-fast", "ib-balanced", "ib-embedding"],
  "max_budget": 100,
  "budget_duration": "30d",
  "tpm_limit": 100000,
  "rpm_limit": 600,
  "duration": "90d",
  "metadata": {
    "owner_team": "accounting-ai",
    "environment": "prod",
    "harness_id": "posted-journals",
    "mcp_profile": "harness.posted-journals.v1",
    "created_by": "admin-or-ticket-id"
  },
  "object_permission": {
    "mcp_servers": [
      "spruce-db-readonly",
      "posted-journals-search",
      "internal-docs",
      "filesystem-readonly",
      "slack-notify"
    ]
  }
}
~~~

Treat returned key values as secrets. Save once, then redact from all logs.

## MCP security rule

LiteLLM's MCP permissions can be applied at key, team, organization, end-user, and agent levels. The effective access is the most restrictive intersection. If no MCP permissions exist at any level, access can be broad. Therefore:

- Every production MCP-capable key must specify object_permission.mcp_servers or object_permission.mcp_access_groups.
- Prefer explicit mcp_servers for production enforcement snapshots.
- Use mcp_access_groups for authoring convenience, but watch group drift.
- Use mcp_tool_permissions or toolsets when server-level access still exposes too many tools.
- Use x-mcp-servers or scoped MCP URLs only as selectors, not as the security boundary.

For detailed MCP isolation work, load the litellm-mcp-gateway skill.

## Model access rule

Do not issue wildcard model access for production workloads. Use business aliases instead of provider deployments.

Good examples:

- ib-fast
- ib-balanced
- ib-smart
- ib-code
- ib-long-context
- ib-embedding

Bad examples for app ownership:

- direct provider model names in app code
- raw Azure deployment names in user-facing docs
- keys with all models unless it is a short-lived admin/dev exception

## Budget and rate-limit baseline

At minimum, production keys need:

- max_budget
- budget_duration
- team_id
- models
- tpm_limit or rpm_limit when traffic can spike
- metadata.owner_team
- metadata.environment
- metadata.harness_id or app_id

Use smaller daily limits for new harnesses until behavior is proven. Increase intentionally after spend review.

## Guardrail baseline

Use guardrails for policy, not as a substitute for authorization.

Recommended baseline:

- PII masking/redaction where sensitive data may enter prompts.
- Secret detection before logging or external calls.
- MCP JWT signer for protected MCP servers so they reject calls that bypass LiteLLM.
- Tool permission guardrails for dangerous tools.
- Custom/OSS guardrails (Presidio PII, MCP JWT signer, request defaults) — **IntegriBilt runs OSS only; no Enterprise**.

Never depend on semantic tool filtering as a security boundary; it is relevance filtering and may fail open.

## Licensing stance (locked)

**No LiteLLM Enterprise.** Design for OSS capabilities only:

- Virtual keys, teams, budgets, model allowlists
- MCP object permissions, toolsets, tool search
- Langfuse / OTel / Prometheus callbacks
- Custom guardrails and JWT signer where available

If a requested control only exists in Enterprise, say so and propose an OSS workaround (key metadata + CI policy, external audit log, GitOps key reconcile, etc.). Do not plan Enterprise trials unless leadership reopens that decision.

## Phase-1a security focus

Before registering MCP servers or publishing skills broadly:

1. Explicit MCP permissions on every production key (deny-by-default if unused).
2. No `all-proxy-models` / empty model lists on production keys.
3. Team + budget on every production key.
4. Owner/environment/harness metadata present.

Live WP-A (2026-07-11): 18/18 keys lacked MCP object_permission and budgets; 3 keys were ALL_MODELS.

## Review checklist before approving a security change

- Does this change reduce or increase access?
- Is the owner team explicit?
- Are secrets still secret after the change?
- Is the key scoped to specific models?
- Is MCP access explicit (ceiling) and is the active toolset small enough for context?
- Does the budget match expected blast radius?
- Is tracing/spend metadata present?
- Is rollback obvious?
- Is the design achievable on OSS without Enterprise?
