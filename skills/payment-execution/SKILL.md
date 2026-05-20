---
name: payment-execution
description: Convert a stored Lane intent to a VGS intent at pay-time, mint a single-use cryptogram, and record the confirmation. The agent passes a `lint_*` id (from the intent-mcp service) and `lane-cli pay` does the rest.
metadata:
  display_name: Lane — Payment Execution
  version: 2.0.0
disable-model-invocation: true
---

# Payment Execution (Agent Flow)

`lane-cli pay --lane-intent <lint_*>` is the single command that turns
an MCP-authored **Lane intent** into a charge. It:

1. Fetches the stored LaneIntent from Lane.
2. Asks the user to tap their passkey (browser opens once).
3. Converts the LaneIntent's mandates into a freshly-minted **VGS intent**.
4. Mints a single-use cryptogram + records the confirmation, back to back.

The agent never needs to know the VGS intent id. The CLI prints it for
observability, then immediately uses it.

## Prerequisite

The user has:

- A passkey-enabled card on file (`lane-cli wallet ls` shows it without
  `needs enrollment`). If not, run
  [`wallet-setup`](../wallet-setup/SKILL.md).
- A `lint_*` LaneIntent in `active` status. Drafted via the Lane
  **intent-mcp** service (`mcp__intent-mcp__submit` → user approves).

Quick check for active intents:

```bash
lane-cli intents
```

That lists every active LaneIntent for the user, newest first. Copy
the `lint_*` id for the one you want to charge against.

## Default Flow

```bash
lane-cli pay --lane-intent <lint_id>
```

The CLI:

1. GETs `/api/intents/<lint_id>`. Validates `status === "active"` and
   not past `expiresAt`.
2. Picks the user's default passkey-enabled card (override with
   `--card <last4>`).
3. Runs the passkey ceremony — a browser opens; the user taps.
4. POSTs `/api/agentic-tokens/<tokenId>/intents` with the converted
   body (consumer_prompt + assurance + mandates) and captures the
   returned `intent_*` id.
5. POSTs the cryptogram request, prints the network token + cryptogram
   + ECI + expiry.
6. POSTs the confirmation.

Steps 3–6 happen in one `lane-cli pay` call. There is no separate
`lane-cli request` step in this flow.

## Picking a mandate

A LaneIntent can carry multiple mandates (e.g. `$300 at REI` +
`$30 at Walmart`). Today the CLI picks the **first** mandate as the
default for the cryptogram step — the user's `merchant_name` and
`amount` come from that mandate unless you override:

```bash
lane-cli pay --lane-intent lint_… \
  --merchant-name "Walmart" \
  --amount 30.00
```

The VGS intent itself authorizes **all** mandates at once — overriding
amount / merchant only affects which mandate the cryptogram is routed
against this call.

## Items inside a mandate

Each mandate also carries an `items` array — one entry per product the
mandate authorizes. A "s'mores supplies" mandate at Walmart might look
like:

```json
{
  "description": "S'mores supplies at Walmart",
  "preferred_merchant_name": "Walmart",
  "amount": "30.00",
  "items": [
    {"name": "Graham crackers", "quantity": 1},
    {"name": "Marshmallows", "quantity": 1},
    {"name": "Chocolate bars", "quantity": 2}
  ],
  "conditions": [
    {"item": "Marshmallows", "claim": "quantity", "operation": "<=", "value": 4}
  ]
}
```

Use the items list to produce a clean receipt for the user and to drive
merchant-side cart construction. **Item names are unique across the
whole intent**, so they're safe to use as cart-line ids.

Today the items list does **not** flow through to VGS — the VGS intent
sees only the mandate's amount + merchant. The items + conditions are
Lane-side policy, enforced by the LaneIntent layer. That may change as
the pay-time policy enforcement matures.

## Flags

| Flag                       | Required                                              | Default                              |
| -------------------------- | ----------------------------------------------------- | ------------------------------------ |
| `--lane-intent <lint_*>`   | One of `--lane-intent` / `--intent-id`               | —                                    |
| `--intent-id <intent_*>`   | One of `--lane-intent` / `--intent-id`               | — (direct VGS path; non-LLM)         |
| `--card <last4>`           | No                                                    | Default passkey-enabled card         |
| `--pan-alias <alias>`      | No                                                    | —                                    |
| `--amount <decimal>`       | No                                                    | Picked mandate's `amount`            |
| `--currency <ccy>`         | No                                                    | LaneIntent's `currency` (default USD) |
| `--country <cc>`           | No                                                    | `US`                                 |
| `--merchant-name <name>`   | No                                                    | Picked mandate's `preferred_merchant_name` |
| `--merchant-url <url>`     | No                                                    | `https://www.bestbuy.com`            |

`--intent-id <intent_*>` is the **legacy / direct path** — useful when
testing against a pre-existing VGS intent, but NOT the path agents should
drive. Agents should always pass `--lane-intent <lint_*>`.

## Reading the cryptogram response

Stdout includes the cryptogram payload. The fields the agent needs:

- **Network token** (DPAN) — the card number to send to the merchant.
- **Expiry month + year** — card expiry to send.
- **Cryptogram** (TAVV) — the single-use authentication value.
- **ECI** — the ECI indicator (typically `05` or `07`).

Hand these to the merchant via whatever path applies (browser autofill,
merchant API, etc.). Cryptograms are **single-use** — if the merchant
transaction fails, run `lane-cli pay --lane-intent <lint_*>` again to
mint a fresh one.

## Multi-card users

By default the CLI uses the user's default passkey-enabled card. To
charge a different card, add `--card <last4>`:

```bash
lane-cli pay --lane-intent lint_… --card 4242
```

## Security Rules

1. **Treat the network token + cryptogram as one-time secrets.** Don't
   echo them into long-running chat. Pass them to the merchant, then drop them.
2. **Don't display the full DPAN or cryptogram to humans in chat.**
   Mask to last 4 digits if you must show a human.
3. **Don't retry on errors.** Cryptogram declines are deterministic —
   re-running just burns another cryptogram. Re-drafting the LaneIntent
   via the intent-mcp service may be the right move if the underlying
   policy was wrong.

## Common Errors

| Symptom                                              | Fix                                                                                  |
| ---------------------------------------------------- | ------------------------------------------------------------------------------------ |
| "Missing intent id."                                 | Pass `--lane-intent <lint_*>` (LLM flow) or `--intent-id <intent_*>` (direct).       |
| "Pass --lane-intent or --intent-id, not both."       | Pick one.                                                                            |
| "--lane-intent must look like lint_<26 crockford>."  | Use the id from `lane intents`. Format: `lint_…` followed by 26 Crockford chars.     |
| "lane intent not found"                              | Wrong id, or the intent belongs to a different user / has TTL-expired.               |
| "LaneIntent `…` is `<status>`, not active."          | Already consumed / expired / revoked. Draft a new LaneIntent via the intent-mcp.     |
| "LaneIntent `…` expired at `<ts>`."                  | TTL window closed. Re-draft.                                                         |
| "No passkey-enabled card in your wallet"             | Run [`wallet-setup`](../wallet-setup/SKILL.md).                                      |
| "No card ending in `<last4>`"                        | `--card` value doesn't match. Check `lane-cli wallet ls`.                            |
| "Passkey ceremony timed out"                         | User didn't tap within 5 minutes. Re-run `lane-cli pay --lane-intent`.               |
| Cryptogram step errors                               | VGS intent expired or was rejected. Re-run `lane-cli pay --lane-intent`.             |
| "Lane is having a moment"                            | Transient. Retry once.                                                               |

## Generate Receipt

Give the user a final "receipt" of the full e2e purchase, including an
itemized list of every item purchased and a short description of it.
Pull line items from the LaneIntent's `mandates[*].description` plus
any merchant-side detail the agent has.

## Handoff

This is the terminal step. After confirmation lands, the cryptogram is
consumed. For another purchase, draft a new LaneIntent via the
intent-mcp service (`mcp__intent-mcp__submit`) and loop back to this
skill with the new `lint_*` id.
