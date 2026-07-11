# LiteLLM decisions (IntegriBilt)

Date: 2026-07-11

| Decision | Choice |
|---|---|
| Phase | **1a** first (lock keys/budgets/teams before MCP register) |
| Enterprise | **No** — OSS only |
| MCP “five” | Example only — assign whatever servers the job needs; never the whole catalog |
| Primary MCP UX control | **Toolsets** (correct tools + context hygiene) |
| Primary worry | Context-window clouding from too many tool schemas (security ceilings still mandatory) |
| Flexibility | Toolset X on project/model today; toolset Z tomorrow without widening ceiling |
| Upstream | Check BerriAI/litellm GitHub releases **daily** |
| Skills SoT | `IntegriGit/integribilt-skills` |

WP-A inventory: see goose blueprint `inventory/WORK-PACKAGE-A-INVENTORY.md`
