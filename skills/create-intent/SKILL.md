---
name: create-intent
description: NOT the LLM-driven path anymore. LLM agents should draft intents via the intent-mcp service (`mcp__intent-mcp__submit`) and pay via `lane-cli pay --lane-intent <lint_*>`. This skill documents the legacy / direct `lane-cli request` surface for scripts and one-off testing.
metadata:
  display_name: Lane — Create Intent (legacy / direct)
  version: 3.0.0
disable-model-invocation: true
---

# Create Intent (legacy / direct surface)

> ⚠️ **For LLM-driven purchases, do NOT use this skill.**
> The agent flow is now:
> 1. Draft a LaneIntent via the **intent-mcp** service — call
>    `mcp__intent-mcp__submit` with a natural-language prompt, iterate
>    with `needs_info` clarifications, finalize with `approve`. The
>    server persists a `lint_*` LaneIntent.
> 2. Optionally list active drafts:
>    ```bash
>    lane-cli intents
>    ```
> 3. Charge against one with [`payment-execution`](../payment-execution/SKILL.md):
>    ```bash
>    lane-cli pay --lane-intent <lint_*>
>    ```
>    `pay` runs the passkey ceremony, converts the LaneIntent into a
>    fresh VGS intent, mints the cryptogram, and records the
>    confirmation — all in one shot.

This skill describes the **direct `lane-cli request`** path. It's still
useful for:

- Scripts that synthesize Lane-flat JSON and don't want to go through
  the MCP draft/approve loop.
- One-off testing against VGS with a hand-written intent body.
- Humans operating the CLI manually.

The eventual plan is for `lane-cli request` to become a thin
intent-mcp client wrapper. Until then, this is the raw direct surface.

## What `lane-cli request` does

`lane-cli request` authorizes a purchase against a passkey-enabled card.
You write a Lane-flat JSON config describing the intent; the user taps
their passkey when prompted; the CLI POSTs the body to
`/api/agentic-tokens/<tokenId>/intents` and prints VGS's response with
an `intent_*` id. That id is what `lane-cli pay --intent-id <intent_*>`
expects.

It does **not** create a stored LaneIntent. Stored LaneIntents are
authored by the intent-mcp service.

## Prerequisite

The user has at least one passkey-enabled card. If not, send them
through [`wallet-setup`](../wallet-setup/SKILL.md) first.

Quick check:

```bash
lane-cli wallet ls
```

## Direct Flow

Write a JSON file (e.g. `intent.json`) and pass it via `--config`:

```bash
cat > intent.json <<'JSON'
{
  "prompt": "Approve $48 charge at Best Buy for the new soundbar",
  "authentication_amount": "48.00",
  "mandates": [
    {
      "description": "Soundbar",
      "preferred_merchant_name": "Best Buy",
      "amount": "48.00"
    }
  ]
}
JSON

lane-cli request --config intent.json
```

Or pass it inline:

```bash
lane-cli request --json '{"prompt":"Approve $48 at Best Buy","authentication_amount":"48.00","mandates":[{"description":"Soundbar","preferred_merchant_name":"Best Buy","amount":"48.00"}]}'
```

Or pipe via stdin:

```bash
cat intent.json | lane-cli request --config -
```

What happens:

1. The CLI validates the JSON (required fields, sum invariant, types).
2. It picks the user's default passkey-enabled card (or the one named
   in `card.last4` / `card.pan_alias`).
3. A browser opens; the user taps their passkey.
4. The CLI returns VGS's response. The intent id is at `data.id`.

## JSON shape (Lane-flat)

| Field                                | Required | Default                       | Notes |
|--------------------------------------|----------|-------------------------------|-------|
| `card`                               | no       | default passkey-enabled card  | Object. At most one of `last4` / `pan_alias`. |
| `card.last4`                         | no       | —                             | Last 4 digits of the card. |
| `card.pan_alias`                     | no       | —                             | Power-user override (`tok_…`). Skip unless you know what this is. |
| `prompt`                             | **yes**  | —                             | Human-readable summary of the authorization. Non-empty. |
| `authentication_amount`              | **yes**  | —                             | Total authorized amount, as a positive decimal string (e.g. `"48.00"`). |
| `currency`                           | no       | `"USD"`                       | 3-letter uppercase ISO code. |
| `mandates`                           | **yes**  | —                             | Array, length ≥ 1. Sum of `amount` values must equal `authentication_amount`. |
| `mandates[].description`             | **yes**  | —                             | Non-empty. |
| `mandates[].preferred_merchant_name` | **yes**  | —                             | Non-empty. |
| `mandates[].amount`                  | **yes**  | —                             | Positive decimal string. |
| `mandates[].merchant_category`       | no       | `"Electronics"`               | Non-empty if provided. |
| `mandates[].merchant_category_code`  | no       | `"1234"`                      | Non-empty if provided. |
| `mandates[].effective_until`         | no       | ISO timestamp at `now + 1d`   | Parseable ISO, strictly in the future. |
| `mandates[].quantity`                | no       | `1`                           | Positive integer. |

Unknown top-level or mandate keys are rejected so typos
(`consumerPrompt`, `decline_threshold`, etc.) fail fast.

## Multi-mandate example

```json
{
  "prompt": "Approve $80 split: $48 Best Buy soundbar + $32 Amazon cables",
  "authentication_amount": "80.00",
  "mandates": [
    {
      "description": "Soundbar",
      "preferred_merchant_name": "Best Buy",
      "merchant_category": "Electronics",
      "merchant_category_code": "5732",
      "amount": "48.00"
    },
    {
      "description": "HDMI cables",
      "preferred_merchant_name": "Amazon",
      "merchant_category": "Electronics",
      "merchant_category_code": "5732",
      "amount": "32.00"
    }
  ]
}
```

## Targeting a specific card

```json
{
  "card": { "last4": "4242" },
  "prompt": "...",
  "authentication_amount": "48.00",
  "mandates": [ { "description": "...", "preferred_merchant_name": "...", "amount": "48.00" } ]
}
```

If two cards share a last4, use `card.pan_alias` instead.

## Validation

The CLI validates the config before any network mutation and reports
**every** issue at once. Example output:

```
✗ Invalid intent config:
  - prompt: required
  - mandates[0].amount: must be a positive decimal string (e.g. "48.00")
  - sum of mandate amounts (40.00) does not match authentication_amount (48.00)
```

Fix all listed issues before re-running.

## Flags

| Flag              | Notes                                                                |
|-------------------|----------------------------------------------------------------------|
| `--config <path>` | Read JSON from file. Use `-` for stdin.                              |
| `--json <string>` | Inline JSON string. Mutually exclusive with `--config`.              |
| `--no-attest`     | Debug only. Skips the passkey ceremony — any subsequent `lane-cli pay` will fail. |
| `-h, --help`      | Show inline help.                                                    |

## Capturing the intent id

The CLI prints VGS's response to stdout:

```json
{
  "data": {
    "id": "intent_xxx",
    "type": "intents",
    "attributes": { ... }
  }
}
```

Extract `data.id`. That's what `lane-cli pay --intent-id <id>` expects.

## Where this differs from the LLM flow

| | LLM flow (preferred) | This skill (direct) |
|---|---|---|
| **Where the intent is authored** | `mcp__intent-mcp__submit` (LLM drafts, user clarifies, user approves) | Agent / script hand-writes Lane-flat JSON |
| **Where it's persisted** | LaneIntents DDB table (status active, listable via `lane intents`) | Not persisted — only the VGS intent exists |
| **Pay command** | `lane-cli pay --lane-intent <lint_*>` (single command, includes passkey ceremony) | `lane-cli request` → captures `intent_*` → `lane-cli pay --intent-id <intent_*>` (two commands) |
| **Passkey ceremony** | Runs inside `pay` | Runs inside `request` |
| **Use when** | LLM agent driving a purchase end-to-end | Scripts, fixtures, manual CLI testing |

## Common Errors

| Symptom                                                                | Fix                                                                                  |
|------------------------------------------------------------------------|--------------------------------------------------------------------------------------|
| `Invalid intent config: …`                                             | Read the listed issues and fix the JSON before re-running.                           |
| `sum of mandate amounts (X) does not match authentication_amount (Y)`  | Make the mandate amounts add up to `authentication_amount`.                          |
| `Pass --config or --json, not both.`                                   | Pick one form.                                                                       |
| `No intent config provided.`                                           | Add `--config <path>` or `--json '<inline>'`.                                        |
| `Invalid JSON from <source>: …`                                        | The JSON didn't parse. Most often a missing quote or trailing comma.                 |
| `No passkey-enabled card in your wallet`                               | Run [`wallet-setup`](../wallet-setup/SKILL.md): `lane-cli wallet enable-agentic`.    |
| `No card ending in <last4>`                                            | The `card.last4` value doesn't match anything. Check `lane-cli wallet ls`.           |
| `Multiple cards end in <last4>`                                        | Use `card.pan_alias` to disambiguate.                                                |
| `Passkey ceremony timed out`                                           | User didn't tap within 5 minutes. Re-run.                                            |
| `Lane is having a moment`                                              | Network/transient. Retry once.                                                       |

## Handoff

Pass the captured `intent_*` id to `lane-cli pay --intent-id <intent_*>`.
If you're an LLM agent reading this and wondering whether to use this
flow — you almost certainly want
[`payment-execution`](../payment-execution/SKILL.md) with a `lint_*`
id from the intent-mcp service instead.
