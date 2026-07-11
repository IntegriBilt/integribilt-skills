---
name: litellm-proxy-configuration
description: >-
  Use when reading, planning, or changing the IntegriBilt LiteLLM proxy config:
  config.yaml, model_list, litellm_settings, router_settings, general_settings,
  DB-stored models, Redis/Postgres settings, callbacks, guardrails, vector store
  registry, MCP servers, Docker compose wiring, environment variables, and safe
  validation/restart. Trigger on LiteLLM config, proxy, config.yaml, add model,
  add callback, Redis, Postgres, DATABASE_URL, STORE_MODEL_IN_DB, mcp_servers,
  vector_store_registry, or restart LiteLLM.
version: 1.1.0
author: IntegriBilt
license: Proprietary
metadata:
  hermes:
    tags: [integribilt, litellm, proxy, config, docker, yaml, redis, postgres, mcp, vectors]
    related_skills: [integribilt-infrastructure, litellm-model-routing, litellm-authentication-security, litellm-monitoring-troubleshooting]
---

# LiteLLM Proxy Configuration - IntegriBilt

## Purpose

Use this skill when working with the LiteLLM proxy configuration. It is an operating playbook for safe config design, not permission to mutate the live gateway without confirmation.

The proxy config is the foundation for model routing, callbacks, caching, guardrails, MCP registration, vector-store registration, and database-backed gateway behavior.

## Source of truth

Expected locations:

- Gateway URL: http://192.168.254.2:4000
- SVR02 live LiteLLM config: /srv/core/litellm/config.yaml
- SVR02 shared stack: /home/lmiller/integribilt-stack/docker-compose.yml

Before changing anything, verify live state. If a local checkout conflicts with SVR02, treat SVR02 as live and call out the mismatch.

## Non-negotiables

1. Read first, change second.
2. Validate YAML before restart.
3. Secrets are environment references only, never plaintext in config.yaml.
4. Use Docker Compose V2: docker compose, not docker-compose.
5. Follow the shared compose stack. Do not create a sidecar compose file unless explicitly approved.
6. Do not use localhost in docs or app config for cross-host clients.
7. Do not widen model or MCP access as a quick fix.
8. Use the approved stack restart helper on SVR02 when possible.

## Config anatomy

| Section | Purpose |
| --- | --- |
| model_list | Public aliases and provider deployments |
| litellm_settings | callbacks, caching, fallbacks, logging, guardrails integration |
| router_settings | routing strategy, retries, timeouts, cooldowns |
| general_settings | proxy-wide behavior such as database, auth, UI, master key behavior |
| mcp_servers | registered MCP backends and auth/transport settings |
| guardrails | pre-call, post-call, and MCP guardrail definitions |
| vector_store_registry | named vector stores for search/file_search/RAG patterns |
| environment variables | provider keys, DB URLs, Redis, callback credentials, master key |

## Minimal safe config skeleton

~~~yaml
model_list:
  - model_name: ib-fast
    litellm_params:
      model: openai/gpt-4o-mini
      api_key: os.environ/OPENAI_API_KEY

  - model_name: ib-balanced
    litellm_params:
      model: openai/gpt-4o
      api_key: os.environ/OPENAI_API_KEY

  - model_name: ib-embedding
    litellm_params:
      model: openai/text-embedding-3-small
      api_key: os.environ/OPENAI_API_KEY

router_settings:
  routing_strategy: usage-based-routing-v2
  num_retries: 2
  timeout: 60

litellm_settings:
  turn_off_message_logging: true
  success_callback: ["langfuse"]
  failure_callback: ["langfuse"]
  cache: true
  cache_params:
    type: redis

# Secrets are supplied by environment, not literal values.
~~~

Use actual model/provider choices from the live gateway plan.

## Environment variables

Common env categories:

- LITELLM_MASTER_KEY
- DATABASE_URL
- STORE_MODEL_IN_DB
- REDIS_HOST, REDIS_PORT, REDIS_PASSWORD or equivalent Redis URL
- Provider keys such as OPENAI_API_KEY, ANTHROPIC_API_KEY, GEMINI_API_KEY, Azure OpenAI values
- LANGFUSE_PUBLIC_KEY, LANGFUSE_SECRET_KEY, LANGFUSE_HOST or LANGFUSE_OTEL_HOST
- LANGSMITH_API_KEY and LANGSMITH_PROJECT
- OTEL exporter values
- MCP OAuth/client credentials

All secret values come from BWS or the approved secret manager. Config files should reference os.environ values.

## DB-stored models and config drift

LiteLLM can store models and related objects in the database. When STORE_MODEL_IN_DB or DB model management is enabled, the file is not the whole truth.

Before declaring a model missing or stale, check:

- config.yaml model_list
- LiteLLM Admin UI
- LiteLLM model management API
- database-backed models
- team/key model allowlists

Document whether an object is file-managed, DB-managed, or both.

## Runtime model management (Admin API)

Models added via the Admin API are DB-managed (STORE_MODEL_IN_DB) — they persist
across restarts and are INVISIBLE to a file-only review of config.yaml. Manage
them at runtime with the master key (`Authorization: Bearer $LITELLM_MASTER_KEY`,
BWS `LITELLM_MASTER_KEY`):

- List:   `GET  /model/info`  — each entry's `model_info.id` is the delete handle
- Add:    `POST /model/new`   `{model_name, litellm_params:{model, api_key}, model_info:{mode:"chat", tags:[...]}}`
- Delete: `POST /model/delete` `{"id":"<model_info.id>"}`

Caveat: `/model/new` triggers a worker reload → a brief connection-refused window
(~10-20s). Poll `/health/readiness` before continuing; retry on ConnectionError.

Purge a family of stale/duplicate models: `GET /model/info`, filter by
name/model substring, `/model/delete` each id. (2026-07-08: cleared 7 accumulated
GLM duplicates this way.)

## Provider prefix — use the native one, not openai/ + manual api_base

LiteLLM has first-class prefixes for most providers. Use them; do NOT force
`openai/<model>` with a hand-set `api_base` unless the provider genuinely has no
native support (that path causes registry churn and the "key disappears when I
change it" confusion).

- Z.AI (Zhipu GLM) — standard pay-per-token API: `zai/glm-4.7`, `zai/glm-5.2`,
  `zai/glm-4.5-flash` (free tier) with `api_key: os.environ/ZAI_API_KEY` and NO
  `api_base`. Wrong forms that wasted hours: `openai/glm-5.2` + manual api_base,
  and `zhipuai/…`.
- **Z.AI GLM CODING PLAN — THE exception to the native-prefix rule.** Subscription
  ("burn or lose") tokens live at `https://api.z.ai/api/coding/paas/v4`, NOT the
  standard `/api/paas/v4` the `zai/` prefix defaults to. Symptom of getting this
  wrong: HTTP 429 "insufficient balance" on `zai/glm-*` even though the plan has
  tokens. Correct form: `model: openai/glm-4.7`, `api_base:
  https://api.z.ai/api/coding/paas/v4`, `api_key: os.environ/ZAI_API_KEY`.
  (IntegriBilt 2026-07-08: glm-4.7 + glm-4.6 registered this way = primary cheap lane.)
- Truly OpenAI-compatible providers with no native prefix: add them once in
  `litellm/llms/openai_like/providers.json` (`base_url` + `api_key_env`) rather
  than per-model `api_base` hacks.

## Diagnose by status code — funding vs config

- `429 / RateLimitError … Insufficient balance / please recharge` (Z.AI) or
  `400 … credit balance too low` (Anthropic) → wiring is CORRECT; the provider
  ACCOUNT is unfunded. Stop editing config; recharge the account.
- `401 invalid api key / x-api-key` → bad/wrong/empty key, or an OAuth token
  being sent on an api_key path.
- `404 … not a valid model ID` → wrong model name or wrong provider prefix.

A clean, specific upstream error means the request reached the provider — the
gateway config is right. Only vague/local errors point back at config.yaml.

## MCP server config rule

MCP servers may be globally registered, but they must not be globally exposed. Registering a server is not the same as granting every key access to it.

For MCP gateway design, use:

- mcp_servers for registry
- object_permission.mcp_servers or mcp_access_groups for access
- mcp_tool_permissions or toolsets for exact tool exposure
- MCP JWT signer guardrail for zero-trust protected servers

Load litellm-mcp-gateway for exact isolation design.

## Vector store config rule

Use vector_store_registry for named vector stores and use ib-embedding or another explicit embedding alias. Do not let RAG apps choose provider credentials directly.

Vector stores should have metadata:

- owner_team
- data_domain
- sensitivity
- environment
- embedding_model
- retention policy

Load litellm-vectors-rag for RAG architecture.

## Safe change workflow

1. State what needs to change and why.
2. Locate live config and stack file.
3. Take a read-only snapshot of relevant sections.
4. Prepare a minimal diff.
5. Validate YAML and compose config.
6. Confirm if production impact or secrets are involved.
7. Apply the smallest change.
8. Restart only the required service.
9. Smoke test route/key/callback/MCP behavior.
10. Record rollback.

## Validation commands

On SVR02, adapt service names to the live compose file:

~~~bash
cd /home/lmiller/integribilt-stack
docker compose --profile svr02 config --quiet
docker compose --profile svr02 ps
docker compose --profile svr02 logs --tail=100 litellm-proxy
~~~

Gateway smoke tests from a caller host:

~~~bash
curl -sS "$LITELLM_BASE_URL/health"
curl -sS "$LITELLM_BASE_URL/v1/models" -H "Authorization: Bearer $LITELLM_VIRTUAL_KEY"
~~~

## Restart pattern

Use the approved helper instead of a broad compose command when operating the IntegriBilt stack:

~~~bash
cd /home/lmiller/integribilt-stack
./start-stack.sh svr02 litellm-proxy
~~~

Do not restart during sensitive business windows without confirmation.

## Acceptance checklist

- No plaintext secrets in config or logs.
- YAML validates.
- Compose config validates.
- Gateway starts cleanly.
- Intended model alias works.
- Unintended model access is not created.
- MCP permissions remain least-privilege.
- Observability callback still works.
- Spend attribution still works.
- Rollback path is known.
