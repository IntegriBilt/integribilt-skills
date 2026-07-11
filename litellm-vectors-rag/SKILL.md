---
name: litellm-vectors-rag
description: >-
  Use when designing LiteLLM-backed embeddings, vector stores, semantic cache,
  RAG, knowledgebase/file_search, Redis/Valkey vector search, Milvus/Qdrant,
  Azure AI Search, Bedrock Knowledge Bases, Neo4j graph RAG, Honcho/mem0/Zep
  memory, or LangChain/LangGraph retrieval through the IntegriBilt gateway.
  Trigger on embeddings, vectors, vector_store_registry, RAG, Redis semantic
  cache, Neo4j, memory, file_search, knowledgebase, or semantic search.
version: 1.0.0
author: IntegriBilt
license: Proprietary
metadata:
  hermes:
    tags: [integribilt, litellm, embeddings, vectors, rag, redis, neo4j, langchain, langgraph, memory]
    related_skills: [litellm-model-routing, langchain, langgraph, litellm-monitoring-troubleshooting]
---

# LiteLLM Vectors and RAG - IntegriBilt

## Purpose

Use this skill when routing embeddings, vector search, RAG, semantic cache, or agent memory through the IntegriBilt AI gateway architecture.

LiteLLM should own gateway concerns: embedding provider abstraction, keys, budgets, tracing, vector-store API access, and unified model aliases. Specialized systems should own retrieval, graph reasoning, and long-term memory.

## Layer responsibility

| Need | Preferred owner |
| --- | --- |
| Embedding provider abstraction | LiteLLM |
| Embedding key management | LiteLLM |
| Embedding cost tracking | LiteLLM spend logs |
| Vector-store proxy/registry | LiteLLM where supported |
| RAG orchestration | LangChain or LangGraph |
| Exact/semantic cache | Redis or Valkey through LiteLLM/cache layer |
| Document vector search | Milvus, Qdrant, pgvector, Azure AI Search, Bedrock KB, RedisVL |
| Entity relationship memory | Neo4j |
| Agent/user long-term memory | Honcho, mem0, Zep-like systems |
| Observability | LiteLLM callbacks plus Langfuse/LangSmith/OTel |

Do not force every memory problem into one vector database.

## Embeddings rule

All app and agent embedding calls should go through the gateway alias, normally ib-embedding.

Benefits:

- provider keys stay out of app code
- embedding spend is visible
- provider can be swapped centrally
- rate limits and budgets apply
- traces can include project/harness metadata

Example:

~~~bash
curl -sS "$LITELLM_BASE_URL/v1/embeddings" \
  -H "Authorization: Bearer $LITELLM_VIRTUAL_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "ib-embedding",
    "input": "text to embed",
    "metadata": {
      "generation_name": "rag-embed-test",
      "tags": ["env:test", "component:rag"]
    }
  }'
~~~

## Vector-store registry pattern

Use named vector stores with metadata. Example shape:

~~~yaml
vector_store_registry:
  - vector_store_name: ib-docs-kb
    litellm_params:
      vector_store_id: ib-docs-kb-prod
      custom_llm_provider: bedrock
      vector_store_description: IntegriBilt internal documentation knowledge base
      vector_store_metadata:
        owner_team: platform-ai
        data_domain: internal-docs
        sensitivity: internal
        environment: prod
        embedding_model: ib-embedding
~~~

Actual provider fields vary by backend. Verify current LiteLLM docs and provider docs before production config.

## RAG profile standard

Every production RAG app should have a profile:

~~~yaml
rag_profile:
  id: accounting-docs-rag.v1
  owner_team: accounting-ai
  environment: prod
  embedding_model: ib-embedding
  vector_store: ib-docs-kb
  graph_store: neo4j-accounting
  memory_scope: team/accounting-ai
  max_context_chunks: 8
  citation_required: true
  content_logging: false
  required_mcp_profile: harness.accounting-docs.v1
~~~

This profile should connect the application, LiteLLM key, vector store, MCP permissions, and observability metadata.

## Store selection

| Requirement | Good fit |
| --- | --- |
| Repeat exact prompts | Redis exact cache |
| Similar read-only FAQ answers | Redis/Valkey semantic cache |
| Large document semantic search | Milvus, Qdrant, pgvector, Azure AI Search, Bedrock KB |
| Low-latency hot vectors | RedisVL / RediSearch |
| Business relationships and lineage | Neo4j |
| User/agent long-term memory | Honcho, mem0, Zep |
| Complex workflows over retrieval | LangGraph |
| Simple RAG chains | LangChain |

## Semantic cache policy

Semantic cache can save money but can also return a plausible answer for the wrong question.

Allow semantic cache for:

- public or internal documentation Q&A
- non-mutating helpdesk responses
- repeated explanations where exact freshness is not critical

Block semantic cache for:

- accounting actions
- security decisions
- HR/legal/private data
- tool execution planning
- anything with side effects
- questions requiring current database state

If in doubt, use exact cache only or disable cache for that route.

## Knowledgebase/file_search guidance

LiteLLM's knowledgebase and vector-store APIs can support file_search-style retrieval. Use them when you want an OpenAI-compatible retrieval path managed through the gateway. Use LangChain/LangGraph when you need richer chunking, reranking, graph joins, tool orchestration, or human-in-the-loop review.

Recommended split:

- LiteLLM: auth, model/embedding route, spend, logs, vector API proxy.
- LangChain: simple loaders, splitters, retrievers, chains.
- LangGraph: durable multi-step retrieval workflows, HITL, retry, state.
- Neo4j: entity facts and graph traversal.
- Redis: cache and hot state.
- Honcho/mem0/Zep: durable user/agent memory.

## Metadata contract

RAG and vector calls should include:

- rag_profile
- vector_store
- embedding_model
- owner_team
- environment
- app_id or harness_id
- document_corpus
- retrieval_version
- data_sensitivity
- trace_user_id when user-scoped

Use tags such as:

- env:prod
- team:accounting-ai
- rag_profile:accounting-docs-rag.v1
- vector_store:ib-docs-kb
- corpus:internal-docs

## Evaluation requirement

Before production, every RAG profile needs:

- golden question set
- expected citations or source docs
- hallucination checks
- latency budget
- token/cost budget
- retrieval freshness policy
- cache policy
- access control test
- trace visibility test

Use Langfuse or LangSmith datasets/evals where practical.

## Acceptance checklist

- Embeddings route through LiteLLM alias.
- Vector/RAG key has explicit budget and owner metadata.
- Vector store has owner, sensitivity, and environment metadata.
- RAG profile exists and is versioned.
- Semantic cache is disabled unless explicitly approved.
- Retrieval traces show query, store, chunk count, and model route where privacy policy allows.
- Sensitive content is not logged by default.
- Access control prevents querying unauthorized corpora.
- Citations are required where answers affect decisions.
