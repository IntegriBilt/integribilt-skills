---
name: litellm-model-routing
description: >-
  Use when designing or changing LiteLLM model routing at IntegriBilt: model
  aliases, provider routing, load balancing, fallbacks, retries, timeouts,
  health-check routing, context-window fallbacks, content-policy fallbacks,
  caching, embedding aliases, vector-store model choices, and model access by
  team/key. Trigger on route model, add model, fallback, load balance, cache,
  embedding model, LiteLLM router, model alias, or provider failover.
version: 1.0.0
author: IntegriBilt
license: Proprietary
metadata:
  hermes:
    tags: [integribilt, litellm, routing, model-aliases, load-balancing, fallbacks, cache, embeddings]
    related_skills: [litellm-proxy-configuration, litellm-authentication-security, litellm-vectors-rag, litellm-monitoring-troubleshooting]
---

# LiteLLM Model Routing - IntegriBilt

## Purpose

Use this skill when deciding how IntegriBilt exposes models through LiteLLM. The gateway should hide provider complexity behind stable business aliases, route traffic by policy, fail over safely, and keep spend visible.

The goal is not to expose every provider model. The goal is to expose a small, reliable model catalog with explicit ownership and behavior.

## Gateway facts

- Gateway base URL: http://192.168.254.2:4000
- Cross-host clients must not use localhost.
- App code should call LiteLLM with virtual keys and model aliases.
- Provider keys stay in the gateway environment or approved secret manager.
- Gateway config is expected at /srv/core/litellm/config.yaml on SVR02; live state may also include DB-stored models.

## Recommended public model catalog

Expose purpose-driven aliases instead of provider-specific deployments.

| Alias | Purpose |
| --- | --- |
| ib-fast | Cheap, fast summarization, extraction, simple transformations |
| ib-balanced | Default business assistant model |
| ib-smart | Higher reasoning and difficult analysis |
| ib-code | Code and agentic development work |
| ib-long-context | Long documents and large context windows |
| ib-vision | Image/PDF/vision tasks |
| ib-local-private | Sensitive/private routing to local or private model paths |
| ib-embedding | Default embedding endpoint |
| ib-rerank | Reranking where supported |

When adding a model, map it to one of these aliases or propose a new alias only if the capability is genuinely different.

## Routing design rules

1. One alias can have multiple provider deployments behind it.
2. App code should never depend on a provider deployment name.
3. Team and key allowlists should use aliases.
4. Fallbacks should preserve data policy. Do not fall back from private/local to public provider unless explicitly approved.
5. Context-window fallback should go to a larger-context alias, not an arbitrary stronger model.
6. Content-policy fallback should be intentional and logged.
7. Expensive models need budget guardrails and restricted team access.
8. Test every route with a real completion and trace metadata before announcing it.

## Config pattern

Use this shape as the starting point. Fill actual provider keys from environment variables, not plaintext.

~~~yaml
model_list:
  - model_name: ib-balanced
    litellm_params:
      model: openai/gpt-4o
      api_key: os.environ/OPENAI_API_KEY
    model_info:
      tags:
        - tier:balanced
        - data:external
        - region:us

  - model_name: ib-balanced
    litellm_params:
      model: azure/gpt-4o
      api_key: os.environ/AZURE_OPENAI_API_KEY
      api_base: os.environ/AZURE_OPENAI_API_BASE
    model_info:
      tags:
        - tier:balanced
        - data:external
        - region:us

  - model_name: ib-embedding
    litellm_params:
      model: openai/text-embedding-3-small
      api_key: os.environ/OPENAI_API_KEY
    model_info:
      mode: embedding
      tags:
        - embedding
        - default

router_settings:
  routing_strategy: usage-based-routing-v2
  num_retries: 2
  timeout: 60

litellm_settings:
  fallbacks:
    - ib-smart: [ib-balanced]
    - ib-balanced: [ib-fast]
  context_window_fallbacks:
    - ib-balanced: [ib-long-context]
~~~

Adjust the routing strategy to match live LiteLLM version and desired behavior. Verify against current docs before production change.

## Fallback policy

| Fallback type | Use when | Safety note |
| --- | --- | --- |
| Model fallback | provider outage, rate limit, transient failure | Same data classification only |
| Context-window fallback | context too large | Use larger context alias |
| Content-policy fallback | provider blocks a request unexpectedly | Must not bypass company policy |
| Budget fallback | expensive route unavailable due to budget | Prefer cheaper alias or fail closed |
| Region/provider fallback | regional outage | Preserve compliance/geography |

Do not silently fall back to a model with weaker privacy, weaker tool support, or unacceptable output behavior.

## Load balancing policy

Use load balancing when multiple deployments are equivalent enough that the user should not care which one answers. Group only comparable deployments under a shared alias.

Good grouping:

- Same model family in two regions.
- Same model behind OpenAI and Azure when output quality is acceptable.
- Multiple identical local deployments.

Bad grouping:

- Cheap model and flagship reasoning model under one alias.
- Public provider and private/local route under one alias without data classification rules.
- Model with tool support and model without tool support under a tool-heavy agent alias.

## Caching policy

Use exact Redis cache where repeat prompts are safe. Use semantic cache only for narrow, read-only, non-sensitive workloads.

Safe semantic-cache candidates:

- internal documentation Q&A
- repeated public product explanations
- non-mutating support FAQ

Avoid semantic cache for:

- tool execution decisions
- financial/accounting actions
- HR/security/legal sensitive content
- agent loops with side effects
- anything where similar is not identical

## Embeddings and vectors

All embedding calls should go through LiteLLM using an alias such as ib-embedding. This gives cost tracking, key control, provider swap flexibility, and trace metadata. RAG systems can use LangChain, LangGraph, Redis, Neo4j, Milvus, Qdrant, Azure AI Search, or Bedrock KB behind the scenes, but embeddings should still be gateway-routed.

For deeper vector/RAG work, load litellm-vectors-rag.

## Test commands

List models:

~~~bash
curl -sS "$LITELLM_BASE_URL/v1/models" \
  -H "Authorization: Bearer $LITELLM_VIRTUAL_KEY"
~~~

Test a chat route:

~~~bash
curl -sS "$LITELLM_BASE_URL/v1/chat/completions" \
  -H "Authorization: Bearer $LITELLM_VIRTUAL_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "ib-balanced",
    "messages": [{"role": "user", "content": "Reply with route test ok."}],
    "metadata": {
      "generation_name": "route-smoke-test",
      "tags": ["env:test", "component:litellm-routing"]
    }
  }'
~~~

Test embeddings:

~~~bash
curl -sS "$LITELLM_BASE_URL/v1/embeddings" \
  -H "Authorization: Bearer $LITELLM_VIRTUAL_KEY" \
  -H "Content-Type: application/json" \
  -d '{"model": "ib-embedding", "input": "embedding route test"}'
~~~

## Acceptance checklist

- Alias name is purpose-based and stable.
- Provider credentials come from environment/BWS.
- Team/key model allowlists are updated intentionally.
- Fallbacks preserve data policy.
- Budget impact is understood.
- Health check or smoke test passed.
- Trace appears in Langfuse/LangSmith/OTel if callbacks are enabled.
- Spend is attributed to key/team/project/model.
- Rollback is documented.
