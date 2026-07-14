---
name: bws-secrets
description: >-
  Retrieve and inject IntegriBilt secrets via Bitwarden Secrets Manager (bws).
  Use when the user mentions BWS, Bitwarden Secrets Manager, bws secret get,
  BWS_ACCESS_TOKEN, machine accounts, rotating API keys, mapping secret names
  to env vars (e.g. GITHUB_TOKEN → GITHUB_PERSONAL_ACCESS_TOKEN), Hermes
  secrets.bitwarden, start-stack secret injection, or Cursor MCP auth that
  needs an env var from BWS. Never print secret values into chat or logs.
version: 1.0.0
author: IntegriBilt
license: Proprietary
metadata:
  hermes:
    tags: [integribilt, bws, bitwarden, secrets, env, litellm, hermes, cursor]
    related_skills: [litellm-authentication-security, litellm-skill-manager, integribilt-infrastructure]
---

# BWS Secrets (IntegriBilt)

## Mental model

| Piece | Role |
|---|---|
| **Machine account access token** | Bootstrap only. Lives in env / Hermes `.env` as `BWS_ACCESS_TOKEN` (starts with `0.`). |
| **Project** | Bucket of secrets the machine account can read. |
| **Secret Name (key)** | Becomes the **environment variable name** when injected. |
| **Secret UUID (id)** | What `bws secret get <id>` requires — **not** the key name. |

Apps that wire BWS correctly (Hermes, `start-stack.sh`) call `bws secret list` at startup and export each secret’s **key → value** into the process env. **Cursor does not do this by itself.**

## Hard rules (agents)

1. **Never** print, paste, or log a secret value (including into terminal transcripts).
2. **Never** write secrets to disk in cleartext (no `.env` dumps of PATs).
3. Prefer `bws run -- <command>` so secrets stay in the child process env.
4. If a secret was exposed in a log, tell the user to **rotate** it in Bitwarden + GitHub/etc.
5. `bws secret get GITHUB_TOKEN` **fails** — that argument must be a **UUID**, not the name.

## Why your `GITHUB_TOKEN` get failed

```text
error: invalid value 'GITHUB_TOKEN' for '<SECRET_ID>': invalid character: found `G` at 1
```

`bws secret get` only accepts the secret **id** (UUID). Resolve name → id first, then get — or use the helper script / `bws run`.

## Common patterns

### List key names only (safe)

```powershell
bws secret list -o json | ConvertFrom-Json | Select-Object -ExpandProperty key | Sort-Object
```

### Get by key name without echoing (PowerShell)

```powershell
# Writes to a variable only — do not Write-Host / print $val
$val = & "$env:USERPROFILE\.cursor\skills\bws-secrets\scripts\Get-BwsSecret.ps1" -Key GITHUB_TOKEN
[Environment]::SetEnvironmentVariable("GITHUB_PERSONAL_ACCESS_TOKEN", $val, "User")
# Fully quit and reopen Cursor after User-env changes
```

### Inject all project secrets into one command

```powershell
# Child process gets every secret key as an env var (e.g. GITHUB_TOKEN=...)
bws run -- your-command-here
```

Optional project pin: `bws run --project-id <uuid> -- ...`

### Cursor + GitHub MCP

Cursor’s GitHub MCP header is:

```text
Authorization: Bearer ${GITHUB_PERSONAL_ACCESS_TOKEN}
```

BWS often stores `GITHUB_TOKEN`. Fix with **one** of:

1. **Create a BWS secret named `GITHUB_PERSONAL_ACCESS_TOKEN`** (same PAT value). Then inject into Cursor’s env (User env, or launch Cursor via `bws run`).
2. **Map at set time** (no second secret):
   ```powershell
   $val = & "$env:USERPROFILE\.cursor\skills\bws-secrets\scripts\Get-BwsSecret.ps1" -Key GITHUB_TOKEN
   [Environment]::SetEnvironmentVariable("GITHUB_PERSONAL_ACCESS_TOKEN", $val, "User")
   ```
3. Launch Cursor under injection **and** ensure the MCP name exists in BWS:
   ```powershell
   bws run -- cursor
   ```
   Only works if a secret **named** `GITHUB_PERSONAL_ACCESS_TOKEN` exists (injection uses key names).

Then fully restart Cursor and confirm MCP no longer logs `Authorization header is badly formatted`.

### Hermes (auto)

Hermes stores `BWS_ACCESS_TOKEN` + `secrets.bitwarden.project_id`, then on each start runs `bws secret list` and sets `os.environ` from secret **names**. Rotate in Bitwarden → next Hermes start picks it up. See Hermes docs: `hermes secrets bitwarden setup|status|sync`.

### Stack / compose (SVR02)

`start-stack.sh` pulls via `bws secret list` and exports into the compose process. Same rule: **secret Name = env var**.

## Naming convention

- Prefer secret keys that match the **consumer’s exact env var** (`GITHUB_PERSONAL_ACCESS_TOKEN`, `OMNIGENT_ACCOUNTS_COOKIE_SECRET`, `LITELLM_MASTER_KEY`).
- If two consumers need different names for the same value, either duplicate the secret under both keys or map once at inject time — do not put plaintext copies in repo configs.

## Failure cheat sheet

| Symptom | Cause | Fix |
|---|---|---|
| `invalid value 'NAME' for '<SECRET_ID>'` | Used key name with `secret get` | Resolve UUID via list, or use `Get-BwsSecret.ps1` / `bws run` |
| `BWS_ACCESS_TOKEN is not set` | Bootstrap missing | Set user/machine env or Hermes `.env` |
| `invalid access token` / `invalid_client` | Wrong/revoked token or wrong region | New machine-account token; set `BWS_SERVER_URL` if EU/self-hosted |
| Cursor MCP `Authorization header is badly formatted` | Empty `${GITHUB_PERSONAL_ACCESS_TOKEN}` | Map/create that env name from BWS; restart Cursor |
| Hermes/stack has keys but Cursor does not | Cursor never auto-syncs BWS | User env or `bws run -- cursor` |

## Agent checklist when wiring a new secret

1. Confirm secret **key** name matches the app’s env var (or document the mapping).
2. Confirm `BWS_ACCESS_TOKEN` is available in the target process.
3. Prefer `bws run` or existing injectors (Hermes / start-stack) over manual get.
4. Never display the value. Verify with “is env var non-empty?” only:
   ```powershell
   [bool]$env:GITHUB_PERSONAL_ACCESS_TOKEN
   ```
