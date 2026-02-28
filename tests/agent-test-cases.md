# Agent Test Cases

Test prompts to verify that an AI agent can use the KyberSwap skills correctly. Each test case has an input prompt, expected behavior, and validation criteria.

Run these prompts against an AI agent that has the `quote`, `swap-build`, `swap-execute`, `swap-execute-fast`, and `error-handling` skills loaded. Check the output against the validation criteria.

---

## Test 1: Basic Quote (Registry Tokens)

**Prompt:**
```
/quote 1 ETH to USDC on ethereum
```

**Expected behavior:**
1. Agent reads `references/token-registry.md`
2. Resolves ETH → native address (`0xEeee...`), 18 decimals
3. Resolves USDC → `0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48`, 6 decimals
4. Converts 1 ETH to `1000000000000000000` wei
5. Calls GET `https://aggregator-api.kyberswap.com/ethereum/api/v1/routes?tokenIn=0xEeee...&tokenOut=0xA0b8...&amountIn=1000000000000000000&source=ai-agent-skills`
6. Displays formatted quote with rate, gas, route

**Validate:**
- [ ] Output amount is reasonable (>$1000 worth of USDC)
- [ ] Rate is shown (1 ETH = X USDC)
- [ ] Gas estimate is shown
- [ ] Router address is shown
- [ ] No errors

---

## Test 2: Quote with Token API Fallback

**Prompt:**
```
/quote 1 LINK to USDC on ethereum
```

**Expected behavior:**
1. Agent reads token registry — LINK is NOT in the registry
2. Falls back to Token API: `?chainIds=1&name=LINK&isWhitelisted=true`
3. Resolves LINK to its contract address, 18 decimals
4. Checks honeypot/FOT API for LINK (non-registry token)
5. Converts 1 LINK to `1000000000000000000` wei (1 * 10^18)
6. Calls routes API and displays quote

**Validate:**
- [ ] LINK resolved with 18 decimals
- [ ] Honeypot check was performed for LINK
- [ ] Amount in wei is `1000000000000000000`
- [ ] Output amount is reasonable (LINK ~$10-30)

> **Note:** WBTC is not currently in the Token API's searchable results. If testing WBTC, the agent should fall back to CoinGecko API or ask the user for the address manually. This is a known limitation.

---

## Test 3: Quote on L2 Chain

**Prompt:**
```
/quote 0.1 ETH to USDC on arbitrum
```

**Expected behavior:**
1. Resolves tokens on Arbitrum (chain ID 42161)
2. ETH → native address, USDC → `0xaf88d065e77c8cC2239327C5EDb3A432268e5831`
3. Calls routes API with `arbitrum` path slug
4. May show L1 fee (l1FeeUsd) since Arbitrum is an L2

**Validate:**
- [ ] Chain is Arbitrum
- [ ] USDC address is Arbitrum's USDC (not Ethereum's)
- [ ] Quote succeeds

---

## Test 4: Quote with Default Chain

**Prompt:**
```
/quote 100 USDC to ETH
```

**Expected behavior:**
1. No chain specified → defaults to `ethereum`
2. Resolves normally on Ethereum

**Validate:**
- [ ] Chain defaults to Ethereum
- [ ] Quote succeeds

---

## Test 5: Stablecoin Quote

**Prompt:**
```
/quote 1000 USDC to USDT on ethereum
```

**Expected behavior:**
1. Both tokens are in the registry with 6 decimals
2. Output should be very close to 1000 USDT (±0.1%)
3. No honeypot check needed (both in registry)

**Validate:**
- [ ] Output is ~999-1001 USDT
- [ ] No honeypot warning

---

## Test 6: Swap — Sender Required

**Prompt:**
```
/swap-build 1 ETH to USDC on ethereum
```

**Expected behavior:**
1. Agent notices no sender address was provided
2. Agent asks the user for their sender address before proceeding
3. Does NOT proceed with a placeholder address

**Validate:**
- [ ] Agent asks for sender address
- [ ] Does not use a fake/placeholder address

---

## Test 7: Swap — Quote Confirmation Required

**Prompt:**
```
/swap-build 0.001 ETH to USDC on ethereum from 0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045
```

**Expected behavior:**
1. Resolves tokens (ETH native, USDC from registry)
2. GET routes API → extracts routeSummary
3. **Shows quote details with confirmation prompt:**
   - Exchange rate (1 ETH = X USDC)
   - Expected output amount
   - Minimum received (after slippage)
   - Gas estimate
   - Router address
4. Asks: "Do you want to proceed with building this swap transaction? (yes/no)"
5. Waits for user confirmation before building

**Validate:**
- [ ] Quote details shown before building
- [ ] Exchange rate displayed
- [ ] Minimum received shown
- [ ] Explicit confirmation requested
- [ ] Does NOT build without user saying "yes"

---

## Test 7b: Swap — Full Flow After Confirmation

**Prompt:**
```
/swap-build 0.001 ETH to USDC on ethereum from 0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045
```
*Then user responds:* `yes`

**Expected behavior:**
1. After user confirms, POST route/build with routeSummary, sender, slippage=50 bps
2. Displays transaction details (to, value, data, router)
3. Does NOT add ERC-20 approval reminder (ETH is native)

**Validate:**
- [ ] Transaction calldata is shown (0x...)
- [ ] Router address is shown
- [ ] tx.value is non-zero (native token input)
- [ ] No ERC-20 approval section (native token)
- [ ] Warning about reviewing before submitting

---

## Test 7c: Swap — User Cancels

**Prompt:**
```
/swap-build 1 ETH to USDC on ethereum from 0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045
```
*Then user responds:* `no`

**Expected behavior:**
1. Agent shows quote confirmation details
2. User says "no" or "cancel"
3. Agent aborts and confirms swap was cancelled
4. Does NOT build the transaction

**Validate:**
- [ ] Swap cancelled message shown
- [ ] No transaction built
- [ ] No calldata generated

---

## Test 8: Swap — ERC-20 Approval Reminder

**Prompt:**
```
/swap-build 100 USDC to ETH on ethereum from 0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045
```
*Then user responds:* `yes`

**Expected behavior:**
1. Shows quote confirmation, user confirms
2. Builds transaction
3. Since tokenIn is USDC (ERC-20, not native), shows approval reminder
4. Approval section includes USDC contract address and router as spender

**Validate:**
- [ ] ERC-20 approval reminder is shown
- [ ] Approval spender matches router address
- [ ] Approval token matches USDC address

---

## Test 9: Swap — Slippage Defaults

**Prompt:**
```
/swap-build 100 USDC to USDT on ethereum from 0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045
```
*Then user responds:* `yes`

**Expected behavior:**
1. Shows quote with slippage info
2. USDC→USDT is a stablecoin↔stablecoin pair
3. Agent uses 5 bps (0.05%) slippage, not the default 50 bps

**Validate:**
- [ ] Slippage shown as 5 bps or 0.05% in quote confirmation
- [ ] Minimum received reflects 5 bps slippage

---

## Test 10: Swap — User-Specified Slippage

**Prompt:**
```
/swap-build 1 ETH to USDC on ethereum from 0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045 slippage 100
```
*Then user responds:* `yes`

**Expected behavior:**
1. Shows quote with slippage info
2. Agent uses 100 bps (1%) slippage as specified by user
3. Overrides the default 50 bps for common tokens

**Validate:**
- [ ] Slippage shown as 100 bps or 1% in quote confirmation
- [ ] Minimum received reflects 100 bps slippage

---

## Test 11: Error — Unsupported Chain

**Prompt:**
```
/quote 1 ETH to USDC on solana
```

**Expected behavior:**
1. Solana is not in the supported chains list
2. Agent either reports it's unsupported or checks the supported-chains API
3. Does NOT make a routes API call with "solana" slug

**Validate:**
- [ ] Error message about unsupported chain
- [ ] No crash or undefined behavior

---

## Test 12: Error — Route Not Found

**Prompt:**
```
/quote 0.000000001 ETH to USDC on ethereum
```

**Expected behavior:**
1. Very small amount may result in no route (dust amount)
2. If API returns error 4008 or 4010, agent explains the error

**Validate:**
- [ ] Either succeeds with a valid quote OR
- [ ] Shows a clear error about no route/pool available

---

## Test 13: Native Token Aliases

**Prompt:**
```
/quote 1 MATIC to USDC on polygon
```

**Expected behavior:**
1. "MATIC" is an alias for POL on Polygon
2. Resolves to native address (`0xEeee...`)

**Validate:**
- [ ] MATIC resolves to native token
- [ ] Quote succeeds on Polygon

---

## Test 14: Multi-Chain Token Resolution

**Prompt:**
```
/quote 1 USDC to ETH on base
```

**Expected behavior:**
1. USDC on Base has a DIFFERENT address than Ethereum
2. Base USDC = `0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913`
3. Not Ethereum's USDC (`0xA0b8...`)

**Validate:**
- [ ] USDC address is Base's address, not Ethereum's
- [ ] Quote succeeds

---

## Test 15: Wei Conversion — Large Amount

**Prompt:**
```
/quote 1000000 USDC to ETH on ethereum
```

**Expected behavior:**
1. 1,000,000 USDC (6 decimals) = `1000000000000` wei
2. No scientific notation in the API call
3. May get error 4009 (amountIn too large) — that's OK

**Validate:**
- [ ] Amount in wei is `1000000000000` (not `1e12`)
- [ ] Either succeeds or shows clear error about max amount

---

## Test 16: Swap Execute — Basic

**Prerequisite:** Run `/swap-build 0.01 ETH to USDC on arbitrum from 0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045` first (confirm with "yes") to get swap JSON.

**Prompt:**
```
/swap-execute
```

**Expected behavior:**
1. Agent reads the swap JSON from previous output
2. Shows confirmation with transaction details (router, value, gas)
3. Warns that transaction is irreversible
4. Asks "Do you want to execute this swap?"
5. Asks for wallet method (env var, Ledger, keystore, etc.)
6. Builds correct `cast send` command

**Validate:**
- [ ] Confirmation shown before execution
- [ ] Router address shown: `0x6131B5fae19EA4f9D964eAc0408E4408b66337b5`
- [ ] Correct RPC URL for arbitrum: `https://arb1.arbitrum.io/rpc`
- [ ] `cast send` command includes `--value`, `--gas-limit`, router, calldata

---

## Test 17: Swap Execute — ERC-20 Approval Check

**Prerequisite:** Run `/swap-build 10 USDC to ETH on ethereum from 0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045` first (confirm with "yes").

**Prompt:**
```
/swap-execute
```

**Expected behavior:**
1. Agent notices tokenIn is ERC-20 (not native)
2. Mentions need to check/set approval before executing
3. Shows `cast call` command to check allowance
4. Shows `cast send` command to approve if needed
5. Then shows execute command with `--value 0`

**Validate:**
- [ ] Approval check mentioned for ERC-20 input
- [ ] `--value 0` in cast send (not native token)
- [ ] Approval command uses correct USDC address and router

---

## Test 18: Swap Execute — User Cancels

**Prerequisite:** Have swap JSON available from previous build.

**Prompt:**
```
/swap-execute
```

Then when asked to confirm, respond: `no`

**Expected behavior:**
1. Agent shows confirmation prompt
2. User says "no"
3. Agent cancels execution, does NOT run cast send
4. Confirms cancellation to user

**Validate:**
- [ ] No `cast send` command executed
- [ ] Agent confirms cancellation

---

## Test 19: Swap Execute Fast — Basic

**Prerequisite:**
1. Keystore configured with password file (`~/.foundry/.password`)
2. Sufficient ETH balance for swap and gas

**Prompt:**
```
/swap-execute-fast 0.001 ETH to USDC on base from 0xYourAddress
```

**Expected behavior:**
1. Agent runs the execute-swap.sh script with swap parameters
2. Script internally calls fast-swap.sh to build the transaction
3. No confirmation prompt — executes immediately
4. Displays transaction hash and explorer link
5. Shows warning about no confirmation

**Validate:**
- [ ] Script executed with correct arguments (amount, tokenIn, tokenOut, chain, sender)
- [ ] Transaction hash returned in output
- [ ] Explorer URL shown (basescan.org)
- [ ] Warning about immediate execution mentioned

---

## Test 20: Swap Execute Fast — With Wallet Method

**Prerequisite:** `PRIVATE_KEY` environment variable set

**Prompt:**
```
/swap-execute-fast 0.001 ETH to USDC on arbitrum from 0xYourAddress env
```

**Expected behavior:**
1. Agent runs script with `env` as wallet method (8th argument)
2. Script uses `$PRIVATE_KEY` from environment
3. Builds and executes in one step
4. Returns transaction result

**Validate:**
- [ ] `env` wallet method used
- [ ] No keystore/password required
- [ ] Transaction hash returned
- [ ] Transaction executes or clear error if PRIVATE_KEY not set

---

## Test 21: Error Handling — API Error Code Lookup

**Prompt:**
```
I'm getting error code 4227 from KyberSwap API when building a swap. The message says "gas estimation failed: Return amount is not enough". What does this mean and how do I fix it?
```

**Expected behavior:**
1. Agent recognizes this as a KyberSwap Aggregator API error
2. Identifies error 4227 as "Gas Estimation Failed"
3. Explains the "Return amount is not enough" variant means slippage is too tight or the route is stale
4. Recommends: increase slippage tolerance, re-fetch the route (don't cache > 5-10 seconds), try a smaller amount

**Validate:**
- [ ] Error code 4227 correctly identified
- [ ] "Return amount is not enough" variant explained
- [ ] Actionable fix suggestions provided (increase slippage, re-fetch route)
- [ ] Does not make API calls (this is a knowledge question)

---

## Test 22: Error Handling — On-Chain Error Diagnosis

**Prompt:**
```
My swap transaction reverted on-chain with TRANSFER_FROM_FAILED. What went wrong?
```

**Expected behavior:**
1. Agent identifies this as an on-chain error (Phase 3)
2. Explains: the router couldn't pull tokens from the user's wallet
3. Lists likely causes: insufficient allowance, insufficient token balance, token has transfer restrictions
4. Recommends: check approval to router, check token balance, check if token is fee-on-transfer

**Validate:**
- [ ] Error correctly categorized as on-chain
- [ ] Root cause explained (approval or balance issue)
- [ ] Actionable fixes listed
- [ ] Mentions checking token allowance to router

---

## Test 23: Error Handling — Route Not Found Guidance

**Prompt:**
```
KyberSwap is returning error 4010 when I try to swap a small amount of a new token. How do I troubleshoot?
```

**Expected behavior:**
1. Agent identifies error 4010 as "No Eligible Pools"
2. Explains: no liquidity pool exists for this pair, or pools are filtered out
3. Suggests: try a different pair (route through WETH/USDC), check if the token has liquidity on this chain, try a larger amount, verify the token address is correct

**Validate:**
- [ ] Error 4010 correctly identified
- [ ] "No eligible pools" explanation provided
- [ ] Multiple troubleshooting steps suggested
- [ ] Does not attempt to make a swap

---

## Test 24: Error Handling — Pre-Transaction Error

**Prompt:**
```
I got "insufficient funds for gas * price + value" before my swap transaction was even submitted. Is this a KyberSwap bug?
```

**Expected behavior:**
1. Agent identifies this as a pre-transaction error (Phase 2)
2. Explains: the wallet doesn't have enough native token (ETH/BNB/etc.) to cover gas fees plus the swap value
3. Clarifies this is not a KyberSwap bug — it's a wallet balance issue
4. Recommends: check native token balance, reduce swap amount, or top up wallet

**Validate:**
- [ ] Error correctly categorized as pre-transaction
- [ ] Wallet balance issue explained clearly
- [ ] Not blamed on KyberSwap
- [ ] Actionable fix provided

## Scoring

Count how many test cases the agent handles correctly:

| Score | Rating |
|---|---|
| 22/22 | All skills work flawlessly |
| 18-21 | Minor issues, skills are usable |
| 13-17 | Some gaps, needs improvement |
| <13 | Significant problems |

**Common failure modes to watch for:**
- Using wrong token address for the chain
- Wrong decimals (especially WBTC=8, BSC stables=18)
- Scientific notation in wei amounts
- Missing honeypot check for non-registry tokens
- Wrong slippage defaults
- Not asking for sender address in swap skill
- Missing ERC-20 approval reminder
- Building swap transaction without showing quote confirmation
- Not waiting for user confirmation before building
