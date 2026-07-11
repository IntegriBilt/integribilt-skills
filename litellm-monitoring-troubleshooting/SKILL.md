---
name: litellm-monitoring-troubleshooting
description: >-
  Use when monitoring or troubleshooting the IntegriBilt LiteLLM Gateway:
  Langfuse, LangSmith, OpenTelemetry, Prometheus, spend logs, budgets, health
  checks, model failures, MCP failures, callback failures, cache behavior,
  latency, rate limits, routing failures, and safe restart/verification. Trigger
  on LiteLLM down, trace missing, spend, metrics, Prometheus, Langfuse,
  LangSmith, OpenTelemetry, callback, budget, rate limit, 429, fallback,
  timeout, MCP error, or health check.
version: 1.1.0
author: IntegriBilt
license: Proprietary
metadata:
  hermes:
    tags: [integribilt, litellm, monitoring, troubleshooting, langfuse, langsmith, opentelemetry, prometheus, spend, upstream]
    related_skills: [integribilt-infrastructure, langfuse, langsmith, litellm-proxy-configuration, litellm-model-routing, litellm-mcp-gateway]
---

# LiteLLM Monitoring and Troubleshooting - IntegriBilt

## Purpose

Use this skill to understand whether the LiteLLM Gateway is healthy, observable, and accounting correctly. Troubleshooting must preserve secrets and avoid broad restarts unless necessary.

Operational goal: every request should be attributable by key, team, project, model, environment, and harness, while sensitive message content remains private unless explicitly enabled for a debug case.

## Observability stack

| Layer | Preferred tool | Purpose |
| --- | --- | --- |
| Gateway traces | Langfuse or LangSmith | LLM call traces, model behavior, quality review |
| Distributed traces | OpenTelemetry | service-level spans, latency, context propagation |
| Metrics | Prometheus | uptime, latency, error rate, budget/rate-limit signals |
| Cost ledger | LiteLLM spend logs | spend by key, team, user, model, project, tag |
| Infra logs | Docker logs / host logs | startup, DB, Redis, callback, provider errors |

Use gateway callbacks for fleet-wide coverage. Use SDK-level traces in LangChain/LangGraph apps when you need internal spans for retrieval, tool calls, graph nodes, or evaluation.

## Privacy default

Default to no message-content logging for production.

Recommended stance:

~~~yaml
litellm_settings:
  turn_off_message_logging: true
~~~

For temporary debugging, use a short-lived key or explicit metadata redaction policy. Never enable broad production content logging just to debug one app.

## Trace metadata contract

Ask app owners to send metadata like this through OpenAI-compatible request bodies:

~~~json
{
  "metadata": {
    "generation_name": "posted-journals-audit",
    "trace_user_id": "lmiller-or-service-user",
    "trace_metadata": {
      "team": "accounting-ai",
      "project": "posted-journals",
      "harness_id": "posted-journals",
      "mcp_profile": "harness.posted-journals.v1",
      "environment": "prod"
    },
    "tags": [
      "env:prod",
      "team:accounting-ai",
      "project:posted-journals",
      "harness:posted-journals"
    ],
    "spend_logs_metadata": {
      "department": "accounting"
    }
  }
}
~~~

Good traces start with good metadata. Missing metadata is an application bug or key provisioning bug.

## Callback config patterns

Langfuse classic callback:

~~~yaml
litellm_settings:
  success_callback: ["langfuse"]
  failure_callback: ["langfuse"]
~~~

Langfuse OpenTelemetry callback for Langfuse v3-style ingestion:

~~~yaml
litellm_settings:
  callbacks: ["langfuse_otel"]
~~~

LangSmith callback:

~~~yaml
litellm_settings:
  callbacks: ["langsmith"]
~~~

Environment variables for callback credentials must come from BWS or the approved secret path. Do not put keys in config.yaml.

## Fast triage flow

1. Scope the symptom: all calls, one model alias, one provider, one key, one team, one MCP server, or one app.
2. Check gateway reachability from the caller host.
3. Check key validity and model allowlist.
4. Check budget, RPM, and TPM limits.
5. Check provider-specific failure in gateway logs.
6. Check routing/fallback behavior.
7. Check callback/logging backend only after the model call path is understood.
8. For MCP: check effective key/team/agent MCP permissions before blaming the MCP server.
9. Verify fix with a small request and trace metadata.

## Safe read-only commands

Gateway reachability:

~~~bash
curl -sS "$LITELLM_BASE_URL/health" || true
curl -sS "$LITELLM_BASE_URL/v1/models" -H "Authorization: Bearer $LITELLM_VIRTUAL_KEY"
~~~

Model smoke test:

~~~bash
curl -sS "$LITELLM_BASE_URL/v1/chat/completions" \
  -H "Authorization: Bearer $LITELLM_VIRTUAL_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "ib-fast",
    "messages": [{"role": "user", "content": "Reply ok."}],
    "metadata": {"generation_name": "litellm-smoke-test", "tags": ["env:test"]}
  }'
~~~

SVR02 stack inspection, when operating on the host:

~~~bash
cd /home/lmiller/integribilt-stack
docker compose --profile svr02 ps
docker compose --profile svr02 logs --tail=120 litellm-proxy
~~~

Use the exact service name from the live compose file if it differs.

## Common failure map

| Symptom | Likely cause | First check |
| --- | --- | --- |
| 401 or auth failure | wrong virtual key, expired key, using provider key | key info / key alias / expiry |
| 403 model denied | model not in key/team allowlist | key models and team models |
| 403 MCP denied | MCP object_permission intersection blocks it | key/team/agent MCP permissions |
| 429 "insufficient balance / recharge" (Z.AI) or 400 "credit balance too low" (Anthropic) | provider ACCOUNT unfunded — config is correct | recharge the provider account; do NOT re-edit model config |
| 429 rate limit | provider RPM/TPM or LiteLLM RPM/TPM limit | spend/rate settings and provider logs |
| 404 "not a valid model ID" | wrong model name or wrong provider prefix | use the native prefix (e.g. `zai/glm-5.2`, not `openai/glm-5.2`) |
| model vanishes after add / "key disappears when I change it" | DB-managed model churn from wrong prefix / repeated re-adds | `GET /model/info`, delete dupes by `model_info.id`, re-add once with native prefix |
| timeout | provider latency, model overloaded, bad route | route, fallback, provider health |
| trace missing | callback disabled, wrong project/env, batching delay | callback config and env vars |
| spend missing | request bypassed gateway or metadata/key issue | app base_url and LiteLLM spend logs |
| tool list too large | MCP key not scoped, toolsets not used | MCP profile and toolset config |
| semantic cache odd answer | semantic cache too broad | disable cache for that route |

## Spend review

When asked to investigate spend, break down by:

- date range
- model alias
- provider/deployment
- team
- key alias
- user
- project/harness metadata
- tags
- cache hit/miss if available
- retries/fallbacks if cost doubled unexpectedly

Do not assume a high bill is model usage only. Embeddings, retries, long context, MCP/tool loops, and failed calls can contribute.

## Restart policy

Prefer config validation and targeted service restart. For IntegriBilt infrastructure, follow the integribilt-infrastructure skill. On SVR02, the approved pattern is generally the stack helper rather than a bare docker compose up.

Expected pattern:

~~~bash
cd /home/lmiller/integribilt-stack
./start-stack.sh svr02 litellm-proxy
~~~

Do not restart production services during business-impacting periods without confirmation unless the user has explicitly authorized that exact action.

## Upstream watch (daily)

LiteLLM moves quickly (recent weeks: Grok auth paths, MCP access-control defaults, skills gateway). Run a short upstream check **daily** before changing gateway config:

1. GitHub releases / release notes: `https://github.com/BerriAI/litellm/releases`
2. Docs changelog / MCP + auth pages for anything touching:
   - MCP permissions / least-privilege defaults
   - toolsets / tool search
   - skills marketplace
   - provider auth (xAI/Grok, ChatGPT, Gemini)
3. Compare pinned gateway image/tag on SVR02 to latest stable; note breaking defaults.
4. Append one line to the LiteLLM ledger (`LEDGER.md` in the goose blueprint kit) if something actionable appeared.
5. Do **not** upgrade production mid-day without a rollback tag and a smoke plan.

Quick command pattern (read-only):

~~~bash
# from any host with gh auth
gh release list -R BerriAI/litellm -L 5
gh api repos/BerriAI/litellm/releases/latest --jq '{tag:.tag_name, published:.published_at, name:.name}'
~~~

If a release notes MCP “least privilege” or auth changes, re-run key inventory (`/key/list?return_full_object=true`) before assuming old OPEN_MCP behavior still holds.

## Verification checklist

- Gateway health responds.
- Model list responds for the intended key.
- Smoke completion succeeds for intended alias.
- Denial test fails for unauthorized model or MCP server.
- Active toolset tool count is within context heuristics (see litellm-mcp-gateway).
- Trace appears in the expected observability backend.
- Spend/accounting appears with correct key/team/project.
- Error rate returns to baseline.
- Any temporary debug logging or batch-size changes are reverted.
- Upstream watch done if this is a morning ops pass.
