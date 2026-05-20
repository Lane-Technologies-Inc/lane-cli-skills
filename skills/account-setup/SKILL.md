---
name: account-setup
description: Human-driven onboarding. The agent hands the user the `lane-cli init` command and waits for the browser sign-up to complete.
metadata:
  display_name: Lane — Account Setup
  version: 1.0.0
disable-model-invocation: true
---

# Lane Account Setup (Human Flow)

`lane-cli init` is a browser-driven sign-up / log-in. The agent's job is to hand the user one command and wait.

## Prerequisites

- Node.js v18+ on the user's machine.
- `@getonlane/lane-cli` installed (`npm install -g @getonlane/lane-cli`) or available via `npx`.

## Step 1 — Run the command

Tell the user to run:

```bash
lane-cli init
```

Or one-shot:

```bash
npx @getonlane/lane-cli init
```

The CLI prints the Lane banner, asks **Sign up** or **Log in**, then opens the browser.

## Step 2 — User completes the browser flow

The user signs up (or logs in) in the browser. The CLI shows a `Waiting for sign-up…` spinner until the browser flow finishes.

If the user closes the browser by accident, the CLI keeps spinning until the timeout. They should re-run `lane-cli init`.

## Step 3 — Add a card (optional chain)

After successful sign-up, the CLI prompts:

> Want to add a card now?

- **Yes** → chains directly into the wallet flow.
- **Skip** → finishes onboarding without a card.

## Verifying

```bash
lane-cli wallet ls
```

- Empty wallet → user signed up but skipped the card step. Direct them to [`wallet-setup`](../wallet-setup/SKILL.md).
- "Lane isn't set up on this machine yet" → `init` did not complete; have the user retry.

## What the agent must NOT do

- Don't try to script the browser flow. There's no headless mode.
- Don't pipe input into `lane-cli init`. The interactive picker requires a TTY.

## Common Issues

| Symptom                 | Fix                                                      |
| ----------------------- | -------------------------------------------------------- |
| Browser doesn't open    | The CLI prints the URL — user copies and opens manually. |
| Spinner hangs forever   | User closed the browser early. Re-run `lane-cli init`.   |
| "Already authenticated" | Account already exists locally. Skip to `wallet-setup`.  |
| Times out               | Re-run `lane-cli init`.                                  |

## Handoff

Once the user is signed in, move to [`wallet-setup`](../wallet-setup/SKILL.md) to add a card and enable it for agentic payments.
