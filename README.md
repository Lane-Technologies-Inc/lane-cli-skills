# Lane Agent Skills

Server-delivered skills for AI coding agents. They describe the Lane CLI's command surface and a deterministic 6-step purchase flow that fires the moment the user expresses purchase intent.

## Install the Lane CLI

```bash
npm install -g @getonlane/lane-cli
```

Or run without installing:

```bash
npx @getonlane/lane-cli init
```

## Skill Layout

Skills are organized around the split between **human-driven** flows (interactive browser ceremonies) and **agent-driven** flows (CLI args + structured stdout). The router skill walks the agent through the deterministic flow and routes to setup sub-skills only when a prerequisite check fails.

| Skill                                                | Purpose                                                                                              | Driver |
| ---------------------------------------------------- | ---------------------------------------------------------------------------------------------------- | ------ |
| [`lane`](./skills/lane/SKILL.md)                     | Router. Owns the deterministic purchase flow and dispatches to setup sub-skills on missing state.    | —      |
| [`account-setup`](./skills/account-setup/SKILL.md)   | `lane-cli init` — sign up / log in via browser.                                                      | Human  |
| [`wallet-setup`](./skills/wallet-setup/SKILL.md)     | `lane-cli wallet add` + `lane-cli wallet enable-agentic`.                                            | Human  |
| [`create-intent`](./skills/create-intent/SKILL.md)   | `lane-cli request` — Step 3, authorize a purchase.                                                   | Agent  |
| [`payment-execution`](./skills/payment-execution/SKILL.md) | `lane-cli pay` — Steps 4–6, mint credentials + confirm.                                        | Agent  |

## Deterministic Purchase Flow

Six steps; the router runs them in order:

1. **Login check** — `lane-cli wallet ls`. Branch to `account-setup` / `wallet-setup` if needed.
2. **Pick a card** — show all passkey-enabled cards and ask the user. Never auto-pick the default.
3. **Create intent** — `lane-cli request --card <last4> --prompt "…" --authentication-amount "…"`.
4. **Mint credentials** — `lane-cli pay --intent-id <id> --card <last4> --amount "…" --merchant-name "…" --merchant-url "…"`.
5. **Checkout at the merchant** — out-of-band; Lane does not help with this step.
6. **Confirm with Lane** — today bundled into Step 4. A separate `lane-cli confirm` is planned.

## Quick Reference

### Human-driven (agent hands command to user and waits)

```bash
lane-cli init                                 # Sign up / log in
lane-cli wallet add                           # Add a card
lane-cli wallet enable-agentic <last4>        # Passkey ceremony
lane-cli wallet ls                            # List cards
lane-cli wallet default <last4>               # Set default
lane-cli wallet rm <last4> --yes              # Remove (destructive — human only)
```

### Agent-driven (scriptable)

The agent always picks the card explicitly via `--card <last4>`.

```bash
# Step 3 — Create intent (browser passkey tap required)
lane-cli request \
  --card 4242 \
  --prompt "Approve $48 charge at Best Buy" \
  --authentication-amount "48.00"

# Steps 4 + 6 — Mint cryptogram + record confirmation
lane-cli pay \
  --intent-id <intent-id> \
  --card 4242 \
  --amount "48.00" \
  --merchant-name "Best Buy" \
  --merchant-url "https://www.bestbuy.com"
```

Env-var equivalents: `VGS_INTENT_ID`, `VGS_CARD_LAST4`, `VGS_PAN_ALIAS`, `VGS_AUTHENTICATION_AMOUNT`.

## Hard Rules

1. **No welcome menu, no demo prompt.** Purchase intent fires the deterministic flow.
2. **Always pass `--card <last4>` explicitly** to `lane-cli request` and `lane-cli pay`. Card selection is the agent's job.
3. **Don't script** `lane-cli init` / `lane-cli wallet add` / `lane-cli wallet enable-agentic` / `lane-cli wallet rm` from the agent. Hand the command to the user.
4. **Treat cryptograms and network tokens as one-time secrets.** Don't echo into long-lived chat. Mask to last 4 of DPAN if showing a human; never show the cryptogram.

## License

MIT
