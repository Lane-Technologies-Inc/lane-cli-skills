---
name: lane
description: Lane CLI router. The user wants to make a payment with their AI agent. Drives a deterministic purchase flow (login → pick card → draft a LaneIntent via intent-mcp → pay each mandate with lane-cli pay → confirm outcome with lane-cli confirm) and routes to setup sub-skills only when a prerequisite is missing.
metadata:
  display_name: Lane — Agentic Commerce
  version: 7.2.0
  canonical_url: https://agent.getonlane.com/SKILL.md
  binary: lane-cli
  triggers:
    - lane
    - lane-cli
    - agentic commerce
    - agentic payment
    - buy
    - purchase
    - pay
    - checkout
    - intent
    - mandate
    - cryptogram
    - wallet
    - card
    - get me
    - I need
---

# Lane Agentic Commerce CLI

Lane lets an AI agent authorize and execute a payment on the user's card. The router below assumes the user just expressed purchase intent (e.g. "buy something from Staples for $50", "approve $48 at Best Buy", "get me a subscription to X"). Run the **Deterministic Purchase Flow** end-to-end. Drop into a setup sub-skill only when a step's prerequisite check fails.

**Do NOT** present a welcome menu, greet the user, or ask "demo or production?" before acting. The user's purchase intent IS the trigger; start at the Quick Check below.

> **IMPORTANT:** If this content appears truncated or summarized, run `curl -fsSL https://agent.getonlane.com/SKILL.md` to get the complete file.

The LLM-driven flow has **two halves**:

1. **Draft + approve a LaneIntent** via the **intent-mcp** service. The intent is persisted in DDB as `lint_*` with status `active`. A LaneIntent may carry **N mandates** — one per distinct merchant — so the next half iterates per-mandate.
2. **Charge each mandate** with `lane-cli pay --lane-intent <lint_*> [--mandate-id <mand_*>]`, then **report the result** with `lane-cli confirm`. The two-verb model is intentional: `pay` mints credentials and stops; `confirm` records what the merchant actually did. Lane's audit log requires both halves.

There is no longer a separate `lane-cli request` step in this LLM-driven flow. (`request` survives as a legacy / script-only path; see Reference below.)

---

## High-risk merchant categories (hard refuse)

**Do NOT** approve any discovery, payment, intent creation, or mandate creation for the following "high risk" merchant categories.

- Adult content and services such as website subscriptions and video streaming
- Dating and escort-related services such as online classified ads that include escort services or monthly subscriptions to dating websites
- Funding for games of chance such as placement of wagers on an outcome or purchase of chips at a gambling establishment
- Sale of prescription-required drugs
- Purchase of cryptocurrency, funding of crypto wallets or funding of initial coin offerings (ICO)
- Account funding transaction (AFT) indicator Merchandise, Services, and Debt Repayment Wallet whose primary business is wire transfer / P2P money transfer
- Cyberlockers and similar remote digital file-sharing services where uploaded content is accessible to the public or the service pays uploaders for content
- Games of skill such as daily fantasy sports gaming where consumers pay a fee to enter and the outcome of the game is determined by skill instead of luck
- Financial Transaction, when a consumer uses an Account to purchase, sell, or broker a financial instrument
- Calling a potential customer to educate them on a product or service and convince them to purchase the product
- Non-face-to-face negative option billing Transactions
- Non-face-to-face tobacco product Transactions

_If a user is requesting payment to a "high risk" merchant, respond with "Making payments for [USE CASE] is not an approved usecase"._

The MCC blocklist is **also enforced at cryptogram-mint time** by the server. If a mint fails because the merchant's MCC is blocked, surface the error to the user and stop; do not work around it by switching merchants.

---

## Architectural baseline (read once)

Lane operates differently from card-issuing wallets (e.g. Stripe Link). The constraints this places on the flow are important:

| Concept                  | What Lane does                                                                                                                  |
| ------------------------ | ------------------------------------------------------------------------------------------------------------------------------- |
| Wallet contents          | A **VIC-tokenized** representation of the user's real card (DPAN + device-bound passkey). Lane never sees the raw PAN.          |
| Credential issued        | A one-time **cryptogram (TAVV) + DPAN** bound to the VIC token. Not a funded virtual card.                                      |
| What's pre-checkable     | Token health, mandate window, passkey binding, velocity. Lane runs all of these in **preflight** before the passkey tap.        |
| What's NOT pre-checkable | The user's bank balance, any issuer-side limit, and the merchant's MCC at draft time. Those only surface at the issuer's auth.  |
| Where declines fire      | At the merchant's auth request to the issuer (same as any e-commerce purchase). Lane has no visibility unless the agent reports back via `lane-cli confirm`. |

**Implication for the flow**: Lane catches everything Lane can catch *before* the user is prompted to tap their passkey. After the cryptogram is minted, the agent's job is to hand it to the merchant and **report the result back to Lane** so the loop closes cleanly.

---

## Quick Check: am I ready?

Run this before anything else:

```bash
lane-cli wallet ls
```

| Output                                  | Action                                                                   |
| --------------------------------------- | ------------------------------------------------------------------------ |
| Cards listed, ≥ 1 passkey-enabled       | Continue to Step 1.                                                      |
| `Lane isn't set up on this machine yet` | Run [`account-setup`](../account-setup/SKILL.md), then resume at Step 1. |
| `No cards yet`                          | Run [`wallet-setup`](../wallet-setup/SKILL.md), then resume at Step 1.   |
| Cards listed but none agentic-enabled   | Run `lane-cli wallet enable-agentic <last4>` for one card, then resume.  |

---

## Deterministic Purchase Flow

Six steps, in this exact order. Each step has a prerequisite check; if it fails, branch to the named sub-skill, then resume at the failing step.

### Step 1 — Confirm the user is logged in

Same as Quick Check above. Don't skip it even if a previous command in the conversation showed success; wallet state changes (cards revoked, passkey expired, etc.) outside the agent's visibility.

### Step 2 — Ask the user which card to charge

Even when only one card is enabled, **show it and confirm**. Never silently pick the default.

Format the prompt like:

> You have 2 passkey-enabled cards on file:
>
> 1. Visa •••• 4242 (default)
> 2. Mastercard •••• 1881
>
> Which card should I use for the $50 charge at Staples?

Capture the chosen card's `last4` for use in Steps 4–6.

### Step 3 — Draft + approve a LaneIntent (via intent-mcp)

Call the **intent-mcp** server to draft a LaneIntent from the user's natural-language request:

```
mcp__intent-mcp__submit({
  prompt: "<the user's purchase request, verbatim>"
})
```

The server responds with one of:

- **`needs_info`** — a list of clarifying questions (budget cap? merchant? quantity?). Ask the user, then call `submit` again with the same `session_id` and the answers inlined into the prompt.
- **`draft_ready`** — a structured LaneIntent the user should review. Summarize the draft (mandates, items, amounts, merchants) and ask the user to approve / modify. To finalize, call `submit` again with `session_id` and the literal reply `approve`.
- **`complete`** — returns `lane_intent_id` (a `lint_*` value) plus the full list of mandate ids (`mand_<lint>_<index>`). **Capture both** for Steps 4–6.

Notes:

- The MCP draft loop is conversational. Treat each `needs_info` round as a real clarification — don't synthesize answers the user hasn't given.
- The draft does **not** trigger a passkey ceremony. It just persists the intent + mandates + items + conditions in DDB. The passkey tap happens in Step 4, inside `lane-cli pay`.
- Each mandate carries an `items` array — one entry per product covered (e.g. a "s'mores supplies" mandate has `items: ["graham crackers", "marshmallows", "chocolate bars"]`). Conditions reference items by name (`{"item":"marshmallows","claim":"quantity","operation":"<=","value":4}`). When showing the draft, surface the items, not just the mandate amounts.
- Multi-merchant intents have **N mandates, one per merchant**. Example: a single intent for "buy camping gear under $100" can carry `mand_xyz_0` REI $60 (tent + backpack) and `mand_xyz_1` KIND $40 (bars). Steps 4–6 iterate per mandate.
- To inspect drafts the user has on file, run `lane-cli intents` (lists active LaneIntents newest-first). To inspect mandates under a specific intent (e.g. after losing the mandate list to long conversation scroll), run `lane-cli intent status <lint_*>` — it lists every mandate with its current `status` (`active`, `used`) and a `_next:` hint pointing at the next active mandate.

### Step 4 — Pay one mandate

For a single-mandate intent:

```bash
lane-cli pay --lane-intent <lint_id> --card <last4>
```

For a multi-mandate intent, address the specific mandate you're executing right now (parent-first flag ordering):

```bash
lane-cli pay --lane-intent <lint_id> --mandate-id <mand_id> --card <last4>
```

What this does, in one CLI call:

1. Fetches the LaneIntent from `/api/intents/<lint_id>` and validates `status === "active"`.
2. Runs **preflight** against three locally-knowable conditions before any passkey prompt fires:
   - `token_live` — VIC token is ACTIVE (not revoked or suspended).
   - `device_bound` — passkey ceremony is complete and `assurance_data` is populated for this card.
   - `velocity_ok` — no excessive recent mints for this token (default ceiling: 10 cryptograms / 60s).

   Two server-side checks return permissive defaults plus a warning because the signal isn't locally exposed: `mandate_within_visa_limit` (the VIC scope lives inside an opaque issuer-side token) and `mcc_allowed` (enforced at cryptogram-mint instead). **Preflight failures throw before the user is prompted to tap.** See Recovery Patterns below.
3. Opens the browser for the passkey ceremony. Tell the user: _"A passkey prompt opened in your browser — tap to authorize the $X charge."_ The CLI blocks until the ceremony completes (up to 5 minutes).
4. POSTs the converted body to `/api/agentic-tokens/<tokenId>/intents`, getting back an `intent_*` id.
5. POSTs the cryptogram-mint request and prints the network token + cryptogram + ECI + expiry.

By default the cryptogram is routed against the **mandate addressed by `--mandate-id`** (or the first mandate if you omit the flag on a single-mandate intent). To override mandate-derived defaults, add `--merchant-name <name>`, `--merchant-url <url>`, and `--amount <decimal>` explicitly.

`lane-cli pay` does **not** record a confirmation — that's Step 6's job, after the agent observes the merchant outcome. The credentials in the response are **single-use**. If the merchant transaction fails, do NOT call `pay` again on the same `intent_id`; re-run `lane-cli pay --lane-intent <lint_id>` to mint a fresh cryptogram against the intent.

### Step 5 — Checkout at the merchant (Lane does NOT help here)

The agent uses the DPAN + cryptogram + expiry + ECI at the merchant's checkout. This is out-of-band: browser autofill, merchant API, ACP/UCP endpoints, MCP merchant tools, Lane Instant Checkout, Playwright, whatever channel applies. Lane's role ends with minting the credentials.

**Security:**

- Do not echo the full DPAN or cryptogram into chat history. Mask to last 4 of DPAN if you must show a human.
- The cryptogram is single-use; the merchant has roughly 5 minutes to use it before it expires.

Capture the merchant's outcome (success, declined, error) for Step 6.

### Step 6 — Close the loop with `lane-cli confirm`

Reporting the actual outcome is **mandatory**. Without it Lane's audit log shows a minted cryptogram with no recorded result, and recovery on the next purchase cannot account for prior declines.

Multi-mandate intents (preferred): close each mandate individually so the audit log records per-merchant outcomes correctly.

```bash
lane-cli confirm --intent-id <intent_id> --mandate-id <mand_id> \
  --result <approved|declined> \
  [--decline-reason "<reason>"] \
  [--network-response-code "<code>"]
```

Single-mandate (legacy) intents: omit `--mandate-id`.

```bash
lane-cli confirm --intent-id <intent_id> --result <approved|declined> \
  [--decline-reason "<reason>"] \
  [--network-response-code "<code>"]
```

| Merchant outcome             | Command (multi-mandate)                                                                                                                              |
| ---------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------- |
| Charged successfully         | `lane-cli confirm --intent-id <iid> --mandate-id <mid> --result approved`                                                                            |
| Declined (known reason)      | `lane-cli confirm --intent-id <iid> --mandate-id <mid> --result declined --decline-reason "<merchant message>" --network-response-code "<code>"`     |
| Network error or timeout     | `lane-cli confirm --intent-id <iid> --mandate-id <mid> --result declined --decline-reason "checkout error"`                                          |

A declined confirmation exits the CLI with code 5 and prints structured `error_code`, `decline_source`, `decline_reason`, and `network_response_code` lines on stdout. Use Recovery Patterns below to pick the next action.

**Iterating multi-mandate intents:** after confirming one mandate, run `lane-cli intent status <intent_id>` to see which mandates remain, then return to Step 4 for the next active mandate. The CLI's `_next:` hint after each step also points at the next mandate id automatically. Iterate **sequentially** — never run mandates in parallel. The server-side guard fires `MANDATE_ALREADY_USED` on the second mint attempt against the same mandate; treat that as a hard error and pivot to the next pending mandate.

---

## Recovery Patterns

When a step fails, follow this table. Do not improvise. Each `error_code` has a single correct action.

| `error_code`                  | What it means                                                                                                                                                          | Agent action                                                                                                                              |
| ----------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------- |
| `PREFLIGHT_TOKEN_REVOKED`     | VIC token is not ACTIVE (revoked, suspended, or deactivated).                                                                                                          | Run `lane-cli wallet enable-agentic <last4>` to re-enroll, then retry Step 4.                                                             |
| `PREFLIGHT_DEVICE_NOT_BOUND`  | Passkey ceremony never completed for this card.                                                                                                                        | Run `lane-cli wallet enable-agentic <last4>`; wait for the passkey session to land in `complete` state, then retry Step 4.                |
| `PREFLIGHT_VELOCITY`          | Too many recent mint attempts on this token.                                                                                                                           | Wait the suggested cooldown (printed in the error), then retry. Do not loop.                                                              |
| `MERCHANT_DECLINE_ISSUER`     | Merchant relayed an issuer decline (insufficient funds, fraud hold, etc.) via `lane-cli confirm --result declined`.                                                    | Re-run Step 4 with `--card <other_last4>` to switch funding sources. Do **not** retry the same card.                                      |
| `MERCHANT_DECLINE_FRAUD_HOLD` | Issuer fraud rule fired on the user's card.                                                                                                                            | Ask the user to contact their bank. Lane cannot fix this from the CLI.                                                                    |
| `CRYPTOGRAM_EXPIRED`          | Cryptogram older than its validity window.                                                                                                                             | Re-run Step 4 (`lane-cli pay`) for the same mandate to mint a fresh cryptogram.                                                           |
| `INTENT_EXPIRED`              | Intent past its `effective_until` timestamp.                                                                                                                           | Re-draft via intent-mcp (Step 3). The old intent can't be revived; preflight will reject it.                                              |
| `CRYPTOGRAM_REPLAY`           | The cryptogram has already been spent.                                                                                                                                 | Mint a new cryptogram for the same mandate via Step 4. Never reuse a cryptogram across two checkouts.                                     |
| `MANDATE_ALREADY_USED`        | Server-side guard fired: this mandate is already in `status: used`. The conditional update on `LaneMandates` blocks a second mint against the same mandate.            | Run `lane-cli intent status <intent_id>` to find the next active mandate. Do NOT retry the used mandate.                                  |
| `MCC_BLOCKED`                 | Cryptogram-mint refused because the merchant's resolved MCC is on the blocklist (see High-risk merchant categories above).                                              | Stop. Surface the block to the user; do not switch merchants to work around it.                                                           |

**Universal rule**: never retry the same cryptogram, never silently retry on decline, and always show the user which `error_code` fired plus the action you propose to take.

---

## Hard Rules

1. **No welcome menu, no demo prompt.** Purchase intent triggers the flow above.
2. **LLM-driven purchases go through the intent-mcp service** in Step 3. Do NOT call `lane-cli request` for an LLM-driven purchase — `request` is the direct / script path (see [`create-intent`](../create-intent/SKILL.md)) and skips the conversational drafting that the MCP provides.
3. **Always pass `--card <last4>` explicitly** to `lane-cli pay` and `lane-cli confirm`. Card selection is the agent's job, not the CLI's default.
4. **Don't script `lane-cli init`, `lane-cli wallet add`, `lane-cli wallet enable-agentic`, or `lane-cli wallet rm` from the agent.** These open browsers and assume a human at the keyboard. Hand the command to the user and wait.
5. **Treat the cryptogram and network token as one-time secrets.** Pass them to the merchant; don't echo into long-lived chat history.
6. **Never retry a declined cryptogram.** Re-run `lane-cli pay --lane-intent <lint_id> --mandate-id <mand_id>` to mint a fresh one, or re-draft via the intent-mcp if the underlying policy was wrong.
7. **Always close the loop with `lane-cli confirm`** after Step 5 finishes. Without it Lane's audit log is incomplete and recovery on the next purchase can't account for prior outcomes.
8. **Iterate multi-mandate intents sequentially.** Mint for mandate N, hand it to merchant N, confirm; only then move to mandate N+1. Never run mandates in parallel.

---

## Safeguards

Before requesting credentials for any merchant the agent hasn't transacted with before:

- **Verify merchant legitimacy.** Probe `/agents.txt`, `/llms.txt`, `/.well-known/acp`, `/.well-known/ucp` for protocol manifests. If none exist, treat the merchant with extra scrutiny.
- **Respect `/agents.txt` and `/llms.txt` directives** if present. Bot-disallow rules apply to agents acting on behalf of users.
- **Confirm the user understands the merchant.** If the merchant is unusual for this user (geography, category, amount), state it clearly before Step 3.
- **Mask sensitive output by default.** DPANs, cryptograms, billing addresses are PII. Show only what the user needs to verify the action.
- **MCC blocklist is enforced at cryptogram-mint, not preflight.** The agent does not classify merchant categories at intent-creation time; Lane resolves the MCC after the user has authorized the intent. If a cryptogram-mint fails because the merchant's MCC is blocked, surface it to the user and stop. Do not work around it.

---

## Reference: Sub-Skill Routing

Use these only when the deterministic flow detects a missing prerequisite.

| Sub-skill                                            | Triggers when…                                                                                       |
| ---------------------------------------------------- | ---------------------------------------------------------------------------------------------------- |
| [`account-setup`](../account-setup/SKILL.md)         | `lane-cli wallet ls` reports `Lane isn't set up on this machine yet`.                                |
| [`wallet-setup`](../wallet-setup/SKILL.md)           | Logged in but no cards, or cards present but none agentic-enabled.                                   |
| [`create-intent`](../create-intent/SKILL.md)         | **Legacy / direct path only.** `lane-cli request` with a hand-written JSON config. NOT the LLM flow. |
| [`payment-execution`](../payment-execution/SKILL.md) | Detailed reference for Steps 4–6 (cryptogram fields, security, retries, error table).                |

---

## Command Map

| Command                                                                                                                                          | Driver | Purpose                                                                                                                |
| ------------------------------------------------------------------------------------------------------------------------------------------------ | ------ | ---------------------------------------------------------------------------------------------------------------------- |
| `lane-cli init`                                                                                                                                  | Human  | Sign up / log in via browser.                                                                                          |
| `lane-cli` (no args)                                                                                                                             | Human  | Interactive home menu — Wallet / Create Intent / Pay / Help.                                                           |
| `lane-cli wallet add`                                                                                                                            | Human  | Add a card.                                                                                                            |
| `lane-cli wallet enable-agentic [last4]`                                                                                                         | Human  | Passkey ceremony required before payments.                                                                             |
| `lane-cli wallet ls`                                                                                                                             | Either | Read-only — safe for an agent.                                                                                         |
| `lane-cli wallet default <last4>`                                                                                                                | Either | Set the default card. Agents should still pass `--card` explicitly.                                                    |
| `lane-cli wallet rm <last4> --yes`                                                                                                               | Human  | Destructive — agent must NOT run unattended.                                                                           |
| `lane-cli intents` / `lane-cli intents ls`                                                                                                       | Either | List active LaneIntents on file (read-only).                                                                           |
| `lane-cli intent status <lint_*>`                                                                                                                | Agent  | List mandates under an intent + their fulfillment state. Returns a `_next:` hint pointing at the next active mandate.   |
| `mcp__intent-mcp__submit({prompt})`                                                                                                              | Agent  | Step 3 — draft / advance / approve a LaneIntent. Returns `lint_*` and mandate ids on completion.                       |
| `lane-cli pay --lane-intent <lint_*> [--mandate-id <mand_*>] --card <last4>`                                                                     | Agent  | Step 4 — preflight + passkey ceremony + VGS intent + cryptogram. Iterates per mandate; does NOT auto-confirm.          |
| `lane-cli confirm --intent-id <iid> [--mandate-id <mid>] --result <approved\|declined> [--decline-reason "…"] [--network-response-code "…"]`     | Agent  | Step 6 — report the merchant outcome so Lane closes the loop.                                                          |
| `lane-cli request --config <intent.json>`                                                                                                        | Direct | **Legacy / non-LLM**. Hand-rolled VGS intent for scripts & manual testing. Returns `intent_*`.                          |
| `lane-cli pay --intent-id <intent_*> --card <last4>`                                                                                             | Direct | **Legacy / non-LLM**. Cryptogram against a pre-existing VGS intent (skips the intent-mcp draft).                       |
| `lane-cli logout`                                                                                                                                | Human  | Clear local credentials.                                                                                               |

---

## Self-test (verify this file is current)

If the agent is unsure whether it has the latest contract, run:

```bash
curl -fsSL https://agent.getonlane.com/SKILL.md | head -10
```

The frontmatter `version:` field should read `7.2.0` or later. If older, refetch. v7.2.0 makes the intent-mcp flow canonical and folds in multi-mandate iteration + the recovery-patterns table; v7.1.1 was the last `lane-cli request`-based revision.

```bash
lane-cli --version
```

Should report `1.3.0` or later. Older builds lack `--mandate-id` on `lane-cli pay` and `lane-cli confirm` and have no `lane-cli intent status` subcommand; multi-mandate intents will not iterate correctly without those primitives. Even older builds (< 1.2.0) had `lane-cli pay` auto-recording APPROVED at mint time, which lies to the audit log; never use that for production work.
