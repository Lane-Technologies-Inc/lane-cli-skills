---
name: wallet-setup
description: Human-driven card management. Walks the user through `lane-cli wallet add` and `lane-cli wallet enable-agentic` in the browser. A passkey-enabled card is a hard prerequisite for `lane-cli request`.
metadata:
  display_name: Lane — Wallet Setup
  version: 1.0.0
disable-model-invocation: true
---

# Lane Wallet Setup (Human Flow)

Two interactive commands take a freshly-signed-up user from "no card" to "ready to make payments":

1. `lane-cli wallet add` — collect card details in the browser (Lane never sees the raw card number).
2. `lane-cli wallet enable-agentic` — complete the FIDO passkey ceremony so the card can be used for agent-initiated payments.

Both open browser windows. **Hand the user the command and wait.**

## Prerequisite

The user has a Lane account locally. If `lane-cli wallet ls` reports "Lane isn't set up on this machine yet", run [`account-setup`](../account-setup/SKILL.md) first.

## Step 1 — Add a card

```bash
lane-cli wallet add
```

The CLI opens a browser to a secure card-entry form. The user enters PAN, expiry, CVC, and billing/shipping address. On submit, the CLI confirms the card is saved.

If the user finished the auto-redirected passkey ceremony in the same browser session, **Step 2 is already done** — verify with `lane-cli wallet ls`.

## Step 2 — Enable agentic (passkey ceremony)

```bash
lane-cli wallet enable-agentic <last4>
```

`<last4>` is optional. With it, the CLI targets that specific card. Without it, the user gets an interactive picker.

The user does Touch ID / passkey / OTP step-up in the browser. The CLI waits for completion.

**This must complete before any agent-initiated payment will work.** Without it, `lane-cli request` errors with "card not found".

## Verifying

```bash
lane-cli wallet ls
```

The user's cards appear, with the default flagged. To confirm a card is fully enabled, the cleanest signal is to retry `lane-cli wallet enable-agentic <last4>` — it prints "Already enabled for AI-agent payments" if the ceremony has already landed.

## Other Wallet Commands

| Command                            | Purpose                                               | Driver                       |
| ---------------------------------- | ----------------------------------------------------- | ---------------------------- |
| `lane-cli wallet`                  | Interactive home menu — Wallet / Create Intent / Pay. | Human                        |
| `lane-cli wallet ls`               | List cards with default flag.                         | Either                       |
| `lane-cli wallet default <last4>`  | Set the default card.                                 | Either                       |
| `lane-cli wallet rm <last4> --yes` | Remove a card.                                        | **Human only** — destructive |

`lane-cli wallet ls` and `lane-cli wallet default` are safe for an agent to call. `add`, `enable-agentic`, and `rm` all have human-in-the-loop steps.

## What the agent must NOT do

- Don't try to script card entry. Card numbers can only be entered through the secure browser form.
- Don't run `lane-cli wallet rm` unattended. The user must explicitly authorize.
- Don't bypass the passkey ceremony. Agentic payments require it.

## Common Issues

| Symptom                                        | Fix                                                                         |
| ---------------------------------------------- | --------------------------------------------------------------------------- |
| Browser closes mid-flow                        | Re-run the command.                                                         |
| `enable-agentic` says "Already enabled"        | Card is already passkey-enabled. Move to `create-intent`.                   |
| `lane-cli request` fails with "card not found" | Passkey ceremony was skipped. Run `lane-cli wallet enable-agentic <last4>`. |
| Multiple cards, no default                     | Run `lane-cli wallet default <last4>`.                                      |

## Handoff

When the user has at least one card and `lane-cli wallet enable-agentic` reports "Already enabled" for it, the wallet is ready. Move to [`create-intent`](../create-intent/SKILL.md).
