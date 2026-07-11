---
name: litellm-skills-gateway-integration
description: >-
  Use when designing or operating LiteLLM as the IntegriBilt skills registry and
  gateway: Claude Code plugins, Agent Skills, Skill Hub, marketplace.json,
  /public/skill_hub, /claude-code/plugins, Anthropic-compatible /v1/skills,
  skill metadata, publication workflow, skill validation, and coupling skills to
  MCP profiles. Trigger on skill gateway, Claude Code skill, plugin marketplace,
  SKILL.md, publish skill, skill hub, marketplace.json, or required_mcp_profile.
version: 1.0.0
author: IntegriBilt
license: Proprietary
metadata:
  hermes:
    tags: [integribilt, litellm, skills, skill-gateway, claude-code, marketplace, mcp-profiles]
    related_skills: [litellm-mcp-gateway, litellm-authentication-security, litellm-proxy-configuration]
---

# LiteLLM Skills Gateway Integration - IntegriBilt

## Purpose

Use this skill when improving or operating the IntegriBilt skills gateway. LiteLLM can act as the central registry for reusable agent skills and Claude Code plugins, while Git remains the source of truth for skill content.

Target state: one skill catalog, one publication workflow, one marketplace endpoint, and every production skill declares the model/MCP/budget profile it needs.

## LiteLLM skills surfaces

| Surface | Endpoint | Use |
| --- | --- | --- |
| Admin plugin registry | POST /claude-code/plugins | Register a skill/plugin |
| Admin list | GET /claude-code/plugins | List all registered skills |
| Publish | POST /claude-code/plugins/name/enable | Make a skill public |
| Unpublish | POST /claude-code/plugins/name/disable | Remove from public hub |
| Public skill hub | GET /public/skill_hub | Public catalog for humans/tools |
| Claude Code marketplace | GET /claude-code/marketplace.json | Claude Code plugin marketplace |
| Anthropic-compatible skills | /v1/skills?beta=true | Anthropic Skills API compatibility |

Use the Claude Code plugin registry for organizational skill discovery. Use /v1/skills when specifically testing Anthropic-compatible skill create/list/get/delete behavior.

## Source-of-truth rule

Git is the canonical source for skill content. LiteLLM is the registry and publication gateway.

Recommended flow:

1. Skill source lives in Git with SKILL.md and references.
2. Review validates frontmatter, safety, MCP profile, and docs.
3. Admin registers skill in LiteLLM from GitHub URL or git subdir.
4. Admin publishes skill to public hub/marketplace.
5. Agents install from the LiteLLM marketplace endpoint.
6. Updates flow through Git review and registry update.

Do not hand-edit production skill content only inside the gateway UI without syncing back to Git.

## Required skill metadata standard

Every production IntegriBilt skill should include frontmatter like this:

~~~yaml
---
name: posted-journals-auditor
description: >-
  Audit posted GL journal reports using approved accounting tools and internal
  documents. Use for posted-journals reconciliation, report checks, and variance
  explanation.
version: 1.0.0
author: IntegriBilt
license: Proprietary
metadata:
  integribilt:
    owner_team: accounting-ai
    domain: Accounting
    namespace: spruce
    environment: prod
    risk_level: medium
    required_model: ib-balanced
    required_embedding_model: ib-embedding
    required_mcp_profile: harness.posted-journals.v1
    required_mcp_servers:
      - spruce-db-readonly
      - posted-journals-search
      - internal-docs
    allowed_toolsets:
      - posted-journals-prod-v1
---
~~~

LiteLLM's public skill fields include name, source, description, domain, namespace, keywords, and version. The nested metadata is an IntegriBilt governance convention for review and automation.

## Registration example

Use the admin key from BWS. Do not paste real secrets into examples or logs.

~~~bash
curl -sS -X POST "$LITELLM_BASE_URL/claude-code/plugins" \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "posted-journals-auditor",
    "source": {
      "source": "git-subdir",
      "url": "https://github.com/integribilt/ai-skills",
      "path": "posted-journals-auditor"
    },
    "description": "Audit posted GL journal reports using approved accounting tools.",
    "domain": "Accounting",
    "namespace": "spruce",
    "keywords": ["accounting", "spruce", "journals", "audit"],
    "version": "1.0.0"
  }'
~~~

Publish:

~~~bash
curl -sS -X POST "$LITELLM_BASE_URL/claude-code/plugins/posted-journals-auditor/enable" \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY"
~~~

Unpublish:

~~~bash
curl -sS -X POST "$LITELLM_BASE_URL/claude-code/plugins/posted-journals-auditor/disable" \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY"
~~~

## Claude Code marketplace wiring

Client setting shape:

~~~json
{
  "extraKnownMarketplaces": {
    "integribilt": {
      "source": "url",
      "url": "http://192.168.254.2:4000/claude-code/marketplace.json"
    }
  }
}
~~~

Then install through Claude Code marketplace commands. Prefer the gateway endpoint over scattered direct Git installs so publication status and discovery stay centralized.

## Skill plus MCP coupling

A skill that uses tools must declare the MCP profile it expects. The MCP profile is the authority for which servers and tools can be used.

Rule:

- The skill describes how to operate.
- The MCP profile enforces what tools exist.
- The LiteLLM key/team/agent permissions enforce what the skill can reach.

A skill should not instruct an agent to use a tool that is not present in its required MCP profile. A skill should not be published until the MCP profile passes exact-access tests.

## Publication workflow

Recommended statuses:

1. draft - source exists, not validated.
2. review - metadata, safety, and tool access under review.
3. approved - safe to register or update.
4. public - visible in Skill Hub and marketplace.
5. deprecated - still available but scheduled for replacement.
6. retired - unpublished and removed from default recommendations.

Only approved/public skills should be shown to general users.

## Validation checklist

Before publishing a skill:

- SKILL.md exists.
- name is stable, kebab-case, and unique.
- description is trigger-rich and explains when to use the skill.
- version is semver.
- owner_team exists.
- domain and namespace are present.
- risk_level is set.
- required_model is a LiteLLM alias, not a provider deployment.
- required_mcp_profile exists if tools are used.
- required_mcp_servers match the MCP profile.
- skill instructions do not include secrets.
- destructive actions require confirmation.
- BWS handling is explicit when secrets are involved.
- observability metadata expectations are documented.
- examples use the gateway URL and virtual keys, not provider keys.

## Governance improvement

Add an automated linter later that checks skill frontmatter and compares required_mcp_profile against LiteLLM MCP profiles. The linter should fail publication if:

- MCP profile is missing.
- skill names tools outside the profile.
- required_model is not available to the owning team.
- owner_team is missing.
- risk_level is missing.
- text contains likely secrets.
- examples use localhost for cross-host gateway calls.

## Acceptance checklist

- Skill appears in GET /claude-code/plugins for admins.
- Skill appears in GET /public/skill_hub only after publish.
- marketplace.json includes the published skill.
- Claude Code can add/install from the marketplace endpoint.
- Skill metadata maps to owner, model alias, and MCP profile.
- Tool-using skill cannot exceed its MCP profile.
- Retired skills are unpublished.
