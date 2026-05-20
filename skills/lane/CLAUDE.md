---
name: lane
description: Lane CLI router skill. Decides which sub-skill applies based on whether the user needs to set up an account / cards (human flows), draft a purchase via the intent-mcp (LLM flow), or pay a stored LaneIntent (agent-scriptable flow).
metadata:
  display_name: Lane — Agentic Commerce
  version: 5.0.0
  triggers:
    - lane
    - lane-cli cli
    - agentic commerce
    - agentic payment
    - buy
    - purchase
    - pay
    - intent
    - mandate
    - wallet
    - card
    - cryptogram
---

# Lane — Agentic Commerce CLI

Lane lets an AI agent authorize and execute payments on the user's card. The CLI is split into two surfaces, and the right one depends on whether a human or an LLM is driving:

- **Human-driven setup** is interactive — the user opens a browser and clicks through prompts. The LLM should NOT try to script these; it should hand the user a single command and step back.
- **Agent-driven payment** is a two-half flow: (a) draft a LaneIntent via the **intent-mcp** service (`mcp__intent-mcp__submit`), (b) charge it with `lane-cli pay --lane-intent <lint_*>`. The agent passes flags on the command line, captures structured stdout, and threads the resulting ids between calls.

Pick the workflow below based on what the user is asking for.

---

## Decision Tree

| User says...                                                    | Where to go                                                                                       | Driver |
| --------------------------------------------------------------- | ------------------------------------------------------------------------------------------------- | ------ |
| "Sign me up" / "create an account" / "log in to Lane"           | **`account-setup`**                                                                               | Human  |
| "Add a card" / "enable agentic" / "set up my wallet"            | **`wallet-setup`**                                                                                | Human  |
| "Buy X" / "I need a flight" / "approve $N for Y"                | `mcp__intent-mcp__submit` to draft, then **`payment-execution`** to charge                        | Agent  |
| "Pay this draft" / "charge `lint_…`" / "complete the purchase"  | **`payment-execution`** with `lane-cli pay --lane-intent <lint_*>`                                | Agent  |
| "Show me my drafts" / "list my intents"                         | `lane-cli intents`                                                                                | Either |

If the user starts with no Lane account, walk them through `account-setup` → `wallet-setup` once. After that, the per-purchase loop is: **(a)** draft via intent-mcp → **(b)** `payment-execution`.

---

## Quick Command Map

| Command                                                                  | Surface | Notes                                                                                          |
| ------------------------------------------------------------------------ | ------- | ---------------------------------------------------------------------------------------------- |
| `lane-cli init`                                                          | Human   | Sign-up / log-in via browser.                                                                  |
| `lane-cli` (no args)                                                     | Human   | Interactive home menu.                                                                          |
| `lane-cli wallet add`                                                    | Human   | Add a card.                                                                                    |
| `lane-cli wallet enable-agentic [last4]`                                 | Human   | Required passkey ceremony before payments work.                                                |
| `lane-cli wallet ls`                                                     | Either  | Read-only — safe for an agent.                                                                 |
| `lane-cli wallet default <last4>`                                        | Either  | Set the default card.                                                                          |
| `lane-cli wallet rm <last4> --yes`                                       | Human   | Destructive — agent must NOT run unattended.                                                   |
| `lane-cli intents` / `lane-cli intents ls [--status=<s>]`                | Either  | List active LaneIntents on file.                                                               |
| `mcp__intent-mcp__submit({prompt, session_id?})`                         | Agent   | Draft / advance / approve a LaneIntent. Returns `lint_*` on completion. The LLM-driven path.   |
| `lane-cli pay --lane-intent <lint_*> --card <last4>`                     | Agent   | One-shot: passkey ceremony + VGS intent + cryptogram + confirmation. The LLM-driven path.      |
| `lane-cli request --config <intent.json>`                                | Direct  | **Legacy / non-LLM**. Hand-rolled VGS intent for scripts & manual testing. Returns `intent_*`. |
| `lane-cli pay --intent-id <intent_*>`                                    | Direct  | **Legacy / non-LLM**. Cryptogram + confirmation against an existing VGS intent.                |
| `lane-cli logout`                                                        | Human   | Clear local credentials.                                                                       |

---

## Hard Rules

1. **Don't script `lane-cli init`, `lane-cli wallet add`, `lane-cli wallet enable-agentic`, or `lane-cli wallet rm` from the agent.** They open browsers, prompt for choices, and assume a human at the keyboard. Hand the user the command and wait.
2. **The LLM-driven purchase flow uses the intent-mcp + `lane-cli pay --lane-intent`.** Do NOT use `lane-cli request` for LLM-driven purchases — `request` is the direct / script path that skips the conversational drafting.
3. **A card must be passkey-enabled** before `lane-cli pay` will work. If the user just added a card, walk them through `wallet-setup` (`lane-cli wallet enable-agentic`) before any purchase flow.
4. **Treat cryptograms and network tokens as one-time secrets.** Pass them to the merchant; don't echo them into long-lived chat history.

---

## Status Check

Before any purchase flow, confirm the user is set up:

```bash
lane-cli wallet ls
```

- "Lane isn't set up on this machine yet" → start with `account-setup`.
- "No cards yet" → start with `wallet-setup`.
- Cards listed but none agentic-enabled → run `lane-cli wallet enable-agentic <last4>`.
- At least one enabled card → safe to call `mcp__intent-mcp__submit`.

---

## Sub-Skills

- [`account-setup`](../account-setup/SKILL.md) — `lane-cli init`.
- [`wallet-setup`](../wallet-setup/SKILL.md) — `lane-cli wallet add` + `enable-agentic`.
- [`create-intent`](../create-intent/SKILL.md) — **legacy / direct** `lane-cli request` path. NOT for LLM-driven purchases.
- [`payment-execution`](../payment-execution/SKILL.md) — `lane-cli pay --lane-intent <lint_*>`.
