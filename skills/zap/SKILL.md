---
name: zap
description: This skill should be used when the user asks to "zap into a pool", "add liquidity", "zap in", "provide liquidity", "LP into", "zap out", "remove liquidity from pool", "withdraw from position", "migrate position", "move liquidity", "migrate LP", "rebalance position", or wants to add, remove, or migrate liquidity in concentrated liquidity pools in one transaction. Uses KyberSwap Zap as a Service (ZaaS) API to handle token ratio calculation, swaps, and deposits in a single transaction across 13 EVM chains.
metadata:
  tags:
    - defi
    - kyberswap
    - zap
    - liquidity
    - evm
    - concentrated-liquidity
  provider: KyberSwap
  homepage: https://kyberswap.com
---

# KyberSwap Zap Skill

Zap into, out of, or migrate between concentrated liquidity positions using KyberSwap Zap as a Service (ZaaS). Given a pool, token(s), amount(s), and tick range, fetch the optimal zap route and build a transaction that handles token ratio calculation, swaps, and liquidity deposit in a single transaction.

**This skill supports three flows:**

1. **Zap In** — Add liquidity to a concentrated liquidity pool in one transaction
   - GET the optimal zap-in route
   - Show zap details and ask for user confirmation
   - POST to build the encoded transaction calldata

2. **Zap Out** — Remove liquidity from an existing position in one transaction
   - GET the optimal zap-out route
   - Show zap details and ask for user confirmation
   - POST to build the encoded transaction calldata

3. **Migrate** — Move liquidity from one pool/position to another in one transaction
   - GET the optimal migrate route
   - Show migration details and ask for user confirmation
   - POST to build the encoded transaction calldata

## Input Parsing

### Zap In

The user will provide input like:
- `zap 1 ETH into the USDC/ETH pool on arbitrum from 0xAbc123...`
- `add liquidity 1000 USDC to UniswapV3 ETH/USDC 0.3% pool on ethereum from 0xAbc123...`
- `LP 0.5 ETH and 1000 USDC into pool 0xPoolAddress on base from 0xAbc123...`
- `zap 1 ETH into ETH/USDC full range on arbitrum from 0xAbc123...`

Extract these fields:
- **tokensIn** — one or two input token symbols
- **amountsIn** — the human-readable amount(s) to zap (one per token)
- **pool** — pool address or description (pair + DEX + fee tier)
- **dex** — the DEX identifier in API enum format (e.g., `DEX_UNISWAPV3`, `DEX_PANCAKESWAPV3`). If user provides shorthand like `uniswapv3`, normalize to `DEX_UNISWAPV3` before calling the API
- **chain** — the chain slug (default: `ethereum`)
- **sender** — the address that will send the transaction (**required**)
- **tickLower / tickUpper** — position tick range (or "full range")
- **slippage** — slippage in basis points (see [Slippage Defaults](#slippage-defaults) below)

### Zap Out

The user will provide input like:
- `zap out position #12345 on arbitrum from 0xAbc123...`
- `remove liquidity from NFT 12345 to USDC on ethereum from 0xAbc123...`
- `withdraw my position 12345 on base from 0xAbc123...`

Extract these fields:
- **positionId** — the NFT token ID of the liquidity position
- **chain** — the chain slug (default: `ethereum`)
- **sender** — the address that owns the position (**required**)
- **tokenOut** — desired output token (optional; if omitted, receive both pool tokens)
- **slippage** — slippage in basis points (see [Slippage Defaults](#slippage-defaults) below)

### Migrate

The user will provide input like:
- `migrate position #12345 from uniswapv3 to pool 0xNewPool456 ticks -887220 887220 on arbitrum from 0xAbc123...`
- `move my liquidity from position 12345 to 0xNewPool456 uniswapv3 full range on ethereum from 0xAbc123...`
- `migrate LP #12345 to pancakeswapv3 pool 0xNewPool456 -100 100 on base from 0xAbc123...`

Extract these fields:
- **positionId** — the NFT token ID of the source liquidity position (**required**)
- **poolTo** — the destination pool address (**required**)
- **dex** — the DEX identifier for the destination pool in API format (e.g., `DEX_UNISWAPV3`, `DEX_PANCAKESWAPV3`)
- **tickLower / tickUpper** — tick range for the new position in the destination pool (or "full range")
- **chain** — the chain slug (default: `ethereum`)
- **sender** — the address that owns the source position (**required**)
- **slippage** — slippage in basis points (see [Slippage Defaults](#slippage-defaults) below)

> **Note:** The migrate route API also accepts `poolFrom` (source pool address). If the user does not provide it, the API infers it from the position ID. You can omit `poolFrom` unless the user explicitly provides the source pool address.

**If the sender address is not provided, ask the user for it before proceeding.** Do not guess or use a placeholder address.

**Sender address validation:** See `${CLAUDE_PLUGIN_ROOT}/references/address-validation.md` for validation rules.

### Slippage Defaults

If the user does not specify slippage, choose based on the pool pair type:

| Pair type | Default | Rationale |
|---|---|---|
| Stablecoin pairs (e.g. USDC/USDT) | **5 bps** (0.05%) | Minimal price deviation between pegged assets |
| Common token pairs (e.g. ETH/USDC, WBTC/ETH) | **50 bps** (0.50%) | Standard volatility buffer |
| All other / unknown pairs | **100 bps** (1.00%) | Conservative default for long-tail or volatile tokens |

> These are recommended defaults. The ZaaS API requires an explicit `slippage` value in basis points.

### Supported Chains (13)

See `${CLAUDE_PLUGIN_ROOT}/references/supported-chains.md` (ZaaS section) for the full chain list. ZaaS supports 13 chains — fewer than the Aggregator's 18. Mantle, Unichain, HyperEVM, Plasma, Etherlink, Monad, and MegaETH are **not** supported for zap operations.

### Supported DEX Identifiers

See `${CLAUDE_PLUGIN_ROOT}/references/dex-identifiers.md` for the complete list of 71 supported DEX IDs. When a user provides shorthand (e.g., `uniswapv3`), normalize to API format (e.g., `DEX_UNISWAPV3`) before calling the API.

## Workflow — Zap In

### Step 1: Resolve Token Addresses

Read the token registry at `${CLAUDE_PLUGIN_ROOT}/references/token-registry.md`.

Look up each token in `tokensIn` for the specified chain. Match case-insensitively. Note the **decimals** for each token.

**Aliases to handle:**
- "ETH" on Ethereum/Arbitrum/Optimism/Base/Linea → native token address
- "MATIC" or "POL" on Polygon → native token address
- "BNB" on BSC → native token address
- "AVAX" on Avalanche → native token address
- "S" on Sonic → native token address
- "BERA" on Berachain → native token address
- "RON" on Ronin → native token address

**If a token is not found in the registry:**
Use the fallback sequence described at the bottom of `${CLAUDE_PLUGIN_ROOT}/references/token-registry.md`:
1. **KyberSwap Token API** (preferred) — search whitelisted tokens first: `https://token-api.kyberswap.com/api/v1/public/tokens?chainIds={chainId}&name={symbol}&isWhitelisted=true` via WebFetch. Pick the result whose `symbol` matches exactly with the highest `marketCap`. If no whitelisted match, retry without `isWhitelisted` (only trust verified or market-cap tokens). If still nothing, browse `page=1&pageSize=100` (try up to 3 pages).
2. **CoinGecko API** (secondary fallback) — search CoinGecko for verified contract addresses if the Token API doesn't have it.
3. **Ask user manually** (final fallback) — if CoinGecko also fails, ask the user to provide the contract address. Never guess or fabricate addresses.

### Step 2: Check Token Safety

For any token **not** in the built-in registry and **not** a native token, check the honeypot/FOT API:

```
GET https://token-api.kyberswap.com/api/v1/public/tokens/honeypot-fot-info?chainId={chainId}&address={tokenAddress}
```

Via **WebFetch**, check each input token:
- If `isHoneypot: true` — **refuse the zap** and warn the user that this token is flagged as a honeypot (cannot be sold after buying).
- If `isFOT: true` — warn the user that this token has a fee-on-transfer (tax: `{tax}%`). The actual deposited amount will be less than expected. Proceed only if the user acknowledges the tax.

### Step 2a: Price Context

Before zapping, fetch the current USD price of each input token to give the user context about the value they are depositing. Use the KyberSwap Aggregator to quote 1 unit of each token against USDC:

```
GET https://aggregator-api.kyberswap.com/{chain}/api/v1/routes?tokenIn={tokenAddress}&tokenOut={usdcAddress}&amountIn={oneUnitInWei}&source=ai-agent-skills
```

Via **WebFetch**. Use the USDC address from `${CLAUDE_PLUGIN_ROOT}/references/token-registry.md` for the given chain. If the route fails, try USDT as fallback.

**Calculate USD value of the zap:**
```
tokenPriceUsd = amountOut / 10^6   (USDC has 6 decimals)
zapValueUsd = tokenPriceUsd * amountIn
```

**Display in the confirmation step (Step 4b):**
Include the live USD value in the confirmation table so the user can verify they are zapping the intended amount:

| Input token(s) | {amount} {token} (~${zapValueUsd}) |

**Warn if the token price seems anomalous:**
- If the USD price is `0` or the route returns no results, warn: *"Could not fetch a live USD price for {token}. The token may have very low liquidity. Proceed with caution."*
- If the fetched price differs significantly from the pool's implied price (from the route response `amountInUsd`), warn: *"The live token price (~${price}) differs from the pool's implied value (~${poolImpliedPrice}). This may indicate price manipulation or stale pool state."*

**If the USDC and USDT routes both fail**, skip the price check and note: *"Could not fetch live USD price for {token}. Price context unavailable."*

> **Tip:** Use `/token-info {token} on {chain}` for detailed token information including market cap and safety status before zapping.

### Step 3: Convert Amounts to Wei

For each token in `tokensIn`:

```
amountInWei = amount * 10^(token decimals)
```

The result must be a plain integer string with no decimals, no scientific notation, and no separators.

**For wei conversion, use a deterministic method instead of relying on AI mental math:**
```bash
python3 -c "print(int(AMOUNT * 10**DECIMALS))"
# or
echo "AMOUNT * 10^DECIMALS" | bc
```
**Verify known reference values:** 1 ETH = 1000000000000000000 (18 decimals), 1 USDC = 1000000 (6 decimals)

### Step 4: Get the Zap In Route (GET request)

Read the API reference at `${CLAUDE_PLUGIN_ROOT}/references/api-reference.md` for supplementary context.

Make the request using **WebFetch**:

```
URL: https://zap-api.kyberswap.com/{chain}/api/v1/in/route?dex={dex}&pool.id={poolAddress}&position.tickLower={tickLower}&position.tickUpper={tickUpper}&tokensIn={tokenAddress1},{tokenAddress2}&amountsIn={amountInWei1},{amountInWei2}&slippage={slippageBps}&sender={sender}
Prompt: Return the full JSON response body exactly as received. I need the complete route data object.
```

**Parameters:**
- `dex` — the DEX identifier in API format (e.g., `DEX_UNISWAPV3`)
- `pool.id` — the pool contract address
- `position.tickLower` — lower tick of the position range
- `position.tickUpper` — upper tick of the position range
- `tokensIn` — comma-separated token addresses (one or two)
- `amountsIn` — comma-separated amounts in wei (matching order of `tokensIn`)
- `slippage` — slippage tolerance in basis points
- `sender` — the sender address

**Single token zap:** If the user provides only one token, pass a single address in `tokensIn` and a single amount in `amountsIn`. The ZaaS router will automatically swap the optimal portion into the other pool token.

**Full range:** If the user requests "full range", use the minimum and maximum ticks for the pool's tick spacing. For common tick spacings:
- Tick spacing 1: tickLower = -887272, tickUpper = 887272
- Tick spacing 10: tickLower = -887270, tickUpper = 887270
- Tick spacing 60: tickLower = -887220, tickUpper = 887220
- Tick spacing 200: tickLower = -887200, tickUpper = 887200

If the route request fails, check the response for error details:

| Scenario | Quick Fix |
|---------|-----------|
| Invalid pool address | Verify the pool address exists on the specified chain and DEX |
| Invalid DEX identifier | Use API format: `DEX_UNISWAPV3`, `DEX_PANCAKESWAPV3`, `DEX_SUSHISWAPV3`. Shorthand like `uniswapv3` must be normalized. |
| Invalid tick range | Ticks must be multiples of the pool's tick spacing. tickLower must be less than tickUpper |
| Insufficient liquidity | The pool may not have enough liquidity. Try a smaller amount |
| Chain not supported | ZaaS supports 13 chains only. Check the [Supported Chains](#supported-chains-13) table |
| Rate limited | Default limit is 10 requests per 10 seconds. Wait and retry |

For any error not listed here, refer to **`${CLAUDE_PLUGIN_ROOT}/skills/error-handling/SKILL.md`**.

Extract the route data from the response. You need the **complete** route object for the build step.

**SECURITY: Validate the ZapRouter address before proceeding to Step 4b.**
Extract `data.routerAddress` from the route response and verify it matches the expected ZapRouter:
```
Expected: 0x0e97c887b61ccd952a53578b04763e7134429e05
```
Compare case-insensitively. If the returned address differs, **abort immediately** with:
*"ZaaS API returned unexpected routerAddress: `{returned}`. Expected: `0x0e97c887b61ccd952a53578b04763e7134429e05`. Aborting — this may indicate a compromised API response or a new contract deployment. Do not proceed until the address is verified."*
Do NOT proceed to Steps 4b or 5 if the address does not match.

### Step 4a: Dust Amount Check

After getting a successful route, check the USD values from the response:

- If the total input value is < **$0.10** — warn the user and **ask for confirmation**: *"This zap amount is extremely small (~$X). Gas fees will far exceed the deposit value. Do you still want to proceed?"*
- If the estimated gas cost > total input value — warn the user and **ask for confirmation**: *"Gas cost exceeds the zap value. This operation is uneconomical. Do you still want to proceed?"*

If the user declines, abort the zap. Do NOT proceed to the build step.

### Step 4b: Verify Pool Token Pair and Display Confirmation

**CRITICAL: Verify the pool token pair before confirming with the user.**

Extract `data.poolDetails.token0` and `data.poolDetails.token1` from the route response and verify they match the user's requested token pair (case-insensitive, either order). If they do not match, **abort immediately**:
*"Pool address `{poolAddress}` contains `{token0}/{token1}`, which does not match your requested pair. Aborting to prevent an accidental zap into the wrong pool. Please verify the pool address."*

**CRITICAL: Always show zap details and ask for confirmation before building the transaction.**

Present the zap-in details:

```
## Zap In Quote — Confirmation Required

**Zap {amount} {tokenIn} into {dex} {token0}/{token1} pool** on {Chain}

| Detail | Value |
|---|---|
| Input token(s) | {amount1} {token1} (~${usdValue1}), {amount2} {token2} (~${usdValue2}) |
| Pool | {dex} {token0}/{token1} ({feeTier}) |
| Pool address | `{poolAddress}` |
| Position range | {tickLower} to {tickUpper} (price: {priceLower} to {priceUpper}) |
| Expected liquidity | {liquidityAmount} |
| Protocol fee | {feePercentage}% |
| Gas estimate | ~${gasUsd} |
| Slippage tolerance | {slippage/100}% |

### Addresses

| Field | Value |
|---|---|
| ZapRouter | `0x0e97c887b61ccd952a53578b04763e7134429e05` |
| Sender | `{sender}` |

---

**WARNING — Impermanent Loss Risk:**
Providing liquidity carries impermanent loss risk. The value of your position may decrease relative to simply holding the tokens.

**WARNING — Concentrated Liquidity:**
Concentrated liquidity positions require active management. If the price moves outside your range, your position stops earning fees.

**WARNING — ZapRouter Address:**
The ZaaS router address is different from the Aggregator router. Approve `0x0e97c887b61ccd952a53578b04763e7134429e05` (KSZapRouterPosition), NOT the Aggregator router.

Review the zap details carefully.

**Do you want to proceed with building this zap transaction?** (yes/no)
```

**Wait for the user to explicitly confirm with "yes", "confirm", "proceed", or similar affirmative response before building the transaction.**

If the user says "no", "cancel", or similar, abort and inform them the zap was cancelled. Do NOT proceed to Step 5.

**Note:** Routes expire quickly (~30 seconds). If the user takes too long to confirm, warn them that the quote may be stale and offer to re-fetch.

### Step 5: Build the Zap In Transaction (POST request)

**Only proceed to this step after the user confirms in Step 4b.**

**WebFetch only supports GET requests**, so use `Bash(curl)` for this POST request.

Construct the curl command:

```bash
curl -s --connect-timeout 10 --max-time 30 \
  -X POST "https://zap-api.kyberswap.com/{chain}/api/v1/in/route/build" \
  -H "Content-Type: application/json" \
  -H "X-Client-Id: ai-agent-skills" \
  -d '{
    "sender": "{sender}",
    "route": {PASTE THE COMPLETE route OBJECT FROM STEP 4},
    "deadline": {CURRENT_UNIX_TIMESTAMP + 1200},
    "source": "ai-agent-skills"
  }'
```

**To get the current unix timestamp + 20 minutes for the deadline:**
```bash
echo $(($(date +%s) + 1200))
```

**Important:** The `route` field must contain the **exact** JSON object returned from Step 4. Do not modify, truncate, or reformat it.

### Step 5b: Handle Build Errors

If the build request fails, check the response for error details:

| Scenario | Quick Fix |
|---------|-----------|
| Route expired | The route data is stale. Fetch a fresh route from the GET endpoint and retry |
| Price moved | Price changed significantly since route fetch. Fetch fresh route or increase slippage |
| Insufficient balance | Sender doesn't have enough tokens. Check balance and reduce amount |
| Insufficient gas | Sender doesn't have enough native token for gas. Top up wallet |
| Invalid sender | Verify the sender address is correct and not the zero address |
| Approval missing | Sender hasn't approved the ZapRouter to spend the input token(s) |

For any error not listed here, refer to **`${CLAUDE_PLUGIN_ROOT}/skills/error-handling/SKILL.md`**.

### Step 6: Format the Output

Present the results:

```
## KyberSwap Zap In Transaction

**Zap {amount} {tokenIn} into {dex} {token0}/{token1} pool** on {Chain}

| Detail | Value |
|---|---|
| Input | {amount1} {token1} (~${usdValue1}), {amount2} {token2} (~${usdValue2}) |
| Pool | {dex} {token0}/{token1} ({feeTier}) |
| Pool address | `{poolAddress}` |
| Position range | {tickLower} to {tickUpper} |
| Expected liquidity | {liquidityAmount} |
| Protocol fee | {feePercentage}% |
| Slippage tolerance | {slippage/100}% |
| Gas estimate | ~${gasUsd} |

### Transaction Details

| Field | Value |
|---|---|
| To (ZapRouter) | `0x0e97c887b61ccd952a53578b04763e7134429e05` |
| Value | `{value}` (in wei — non-zero only for native token input) |
| Data | `{encodedCalldata}` |
| Sender | `{sender}` |

> **WARNING:** Review the transaction details carefully before submitting on-chain. This plugin does NOT submit transactions — it only builds the calldata. You are responsible for verifying the ZapRouter address, amounts, and calldata before signing and broadcasting.

> **WARNING:** Providing liquidity carries impermanent loss risk. The value of your position may decrease relative to simply holding the tokens. Concentrated liquidity positions require active management — if the price moves outside your range, your position stops earning fees.
```

### Structured JSON Output

After the markdown table, always include a JSON code block so other plugins or agents can consume the result programmatically:

````
```json
{
  "type": "kyberswap-zap-in",
  "chain": "{chain}",
  "pool": {
    "address": "{poolAddress}",
    "dex": "{dex}",
    "token0": "{token0Symbol}",
    "token1": "{token1Symbol}",
    "feeTier": "{feeTier}"
  },
  "position": {
    "tickLower": {tickLower},
    "tickUpper": {tickUpper}
  },
  "tokensIn": [
    {
      "symbol": "{token1Symbol}",
      "address": "{token1Address}",
      "decimals": {token1Decimals},
      "amount": "{amount1}",
      "amountWei": "{amount1Wei}"
    }
  ],
  "tx": {
    "to": "0x0e97c887b61ccd952a53578b04763e7134429e05",
    "data": "{encodedCalldata}",
    "value": "{transactionValue}",
    "gas": "{gas}",
    "gasUsd": "{gasUsd}"
  },
  "sender": "{sender}",
  "slippageBps": {slippage}
}
```
````

This JSON block enables downstream agents or plugins to parse the zap result without scraping the markdown table.

### Step 7: ERC-20 Approval Reminder

If any token in `tokensIn` is **not** the native token, remind the user about token approval. See `${CLAUDE_PLUGIN_ROOT}/references/approval-guide.md` (ERC-20 section). Use:

- **Token contract:** `{tokenIn address}`
- **Spender (ZapRouter):** `0x0e97c887b61ccd952a53578b04763e7134429e05`
- **Amount:** `{amountInWei}`

**IMPORTANT:** Approve the ZapRouter (`0x0e97c887b61ccd952a53578b04763e7134429e05`), NOT the Aggregator router.

## Workflow — Zap Out

### Step 1: Get the Zap Out Route (GET request)

Make the request using **WebFetch**:

```
URL: https://zap-api.kyberswap.com/{chain}/api/v1/out/route?dex={dex}&positionId={nftTokenId}&tokensOut={tokenOutAddress}&slippage={slippageBps}&sender={sender}
Prompt: Return the full JSON response body exactly as received. I need the complete route data object.
```

**Parameters:**
- `dex` — the DEX identifier
- `positionId` — the NFT token ID of the position to withdraw
- `tokensOut` — the desired output token address (optional; omit to receive both pool tokens)
- `slippage` — slippage tolerance in basis points
- `sender` — the address that owns the position

If the route request fails, check the response for error details:

| Scenario | Quick Fix |
|---------|-----------|
| Invalid position ID | Verify the NFT token ID exists and is owned by the sender |
| Position has no liquidity | The position may already be empty. Check on-chain |
| Invalid DEX identifier | Check the DEX ID against the supported list |
| Chain not supported | ZaaS supports 13 chains only |

### Step 2: Display Zap Out Details and Request Confirmation

**CRITICAL: Always show zap details and ask for confirmation before building the transaction.**

Present the zap-out details:

```
## Zap Out Quote — Confirmation Required

**Withdraw position #{positionId} from {dex} {token0}/{token1} pool** on {Chain}

| Detail | Value |
|---|---|
| Position ID | #{positionId} |
| Pool | {dex} {token0}/{token1} ({feeTier}) |
| Liquidity to remove | {liquidityAmount} |
| Expected output | {amountOut1} {token1} (~${usdValue1}), {amountOut2} {token2} (~${usdValue2}) |
| Unclaimed fees | {fees0} {token0}, {fees1} {token1} |
| Gas estimate | ~${gasUsd} |
| Slippage tolerance | {slippage/100}% |

### Addresses

| Field | Value |
|---|---|
| ZapRouter | `0x0e97c887b61ccd952a53578b04763e7134429e05` |
| Sender | `{sender}` |

---

Review the zap-out details carefully.

**Do you want to proceed with building this zap-out transaction?** (yes/no)
```

**Wait for the user to explicitly confirm before proceeding.**

### Step 3: Build the Zap Out Transaction (POST request)

**Only proceed to this step after the user confirms in Step 2.**

```bash
curl -s --connect-timeout 10 --max-time 30 \
  -X POST "https://zap-api.kyberswap.com/{chain}/api/v1/out/route/build" \
  -H "Content-Type: application/json" \
  -H "X-Client-Id: ai-agent-skills" \
  -d '{
    "sender": "{sender}",
    "route": {PASTE THE COMPLETE route OBJECT FROM STEP 1},
    "deadline": {CURRENT_UNIX_TIMESTAMP + 1200},
    "source": "ai-agent-skills"
  }'
```

### Step 4: Format the Zap Out Output

Present the results:

```
## KyberSwap Zap Out Transaction

**Withdraw position #{positionId} from {dex} {token0}/{token1} pool** on {Chain}

| Detail | Value |
|---|---|
| Position ID | #{positionId} |
| Pool | {dex} {token0}/{token1} ({feeTier}) |
| Expected output | {amountOut1} {token1} (~${usdValue1}), {amountOut2} {token2} (~${usdValue2}) |
| Slippage tolerance | {slippage/100}% |
| Gas estimate | ~${gasUsd} |

### Transaction Details

| Field | Value |
|---|---|
| To (ZapRouter) | `0x0e97c887b61ccd952a53578b04763e7134429e05` |
| Value | `0` |
| Data | `{encodedCalldata}` |
| Sender | `{sender}` |

> **WARNING:** Review the transaction details carefully before submitting on-chain. This plugin does NOT submit transactions — it only builds the calldata. You are responsible for verifying the ZapRouter address, amounts, and calldata before signing and broadcasting.
```

### Structured JSON Output (Zap Out)

````
```json
{
  "type": "kyberswap-zap-out",
  "chain": "{chain}",
  "pool": {
    "address": "{poolAddress}",
    "dex": "{dex}",
    "token0": "{token0Symbol}",
    "token1": "{token1Symbol}",
    "feeTier": "{feeTier}"
  },
  "positionId": "{positionId}",
  "tokensOut": [
    {
      "symbol": "{token1Symbol}",
      "address": "{token1Address}",
      "decimals": {token1Decimals},
      "amount": "{amountOut1}",
      "amountWei": "{amountOut1Wei}"
    }
  ],
  "tx": {
    "to": "0x0e97c887b61ccd952a53578b04763e7134429e05",
    "data": "{encodedCalldata}",
    "value": "0",
    "gas": "{gas}",
    "gasUsd": "{gasUsd}"
  },
  "sender": "{sender}",
  "slippageBps": {slippage}
}
```
````

### Step 5: NFT Approval Reminder (Zap Out)

For zap-out operations, the sender must approve the ZapRouter to manage the position NFT. See `${CLAUDE_PLUGIN_ROOT}/references/approval-guide.md` (ERC-721 section). Use:

- **NFT contract:** `{nftManagerAddress}` (the DEX's position manager)
- **Spender (ZapRouter):** `0x0e97c887b61ccd952a53578b04763e7134429e05`
- **Token ID:** `{positionId}`

## Workflow — Migrate

### Step 1: Get the Migrate Route (GET request)

Make the request using **WebFetch**:

```
URL: https://zap-api.kyberswap.com/{chain}/api/v1/migrate/route?dex={dex}&poolTo={poolToAddress}&positionFrom={positionId}&position.tickLower={tickLower}&position.tickUpper={tickUpper}&slippage={slippageBps}&sender={sender}
Prompt: Return the full JSON response body exactly as received. I need the complete route data object.
```

**Parameters:**
- `dex` — the DEX identifier for the destination pool
- `poolTo` — the destination pool contract address
- `positionFrom` — the NFT token ID of the source position
- `position.tickLower` — lower tick for the new position in the destination pool
- `position.tickUpper` — upper tick for the new position in the destination pool
- `slippage` — slippage tolerance in basis points
- `sender` — the address that owns the source position

**Optional parameters:**
- `poolFrom` — source pool address (API can infer from position ID; include if user provides it)

**Full range:** If the user requests "full range", use the minimum and maximum ticks for the destination pool's tick spacing (same values as [Zap In Step 4](#step-4-get-the-zap-in-route-get-request)).

If the route request fails, check the response for error details:

| Scenario | Quick Fix |
|---------|-----------|
| Invalid position ID | Verify the NFT token ID exists and is owned by the sender |
| Position has no liquidity | The position may already be empty. Check on-chain |
| Invalid destination pool | Verify the pool address exists on the specified chain and DEX |
| Invalid tick range | Ticks must be multiples of the destination pool's tick spacing |
| Same pool migration | Source and destination pools are identical — nothing to migrate |
| Chain not supported | ZaaS supports 13 chains only |

**SECURITY: Validate the ZapRouter address before proceeding.**
Extract `data.routerAddress` from the route response and verify it matches `0x0e97c887b61ccd952a53578b04763e7134429e05` (case-insensitive). If it differs, **abort immediately** with the same warning as Zap In Step 4.

### Step 2: Display Migrate Details and Request Confirmation

**CRITICAL: Always show migration details and ask for confirmation before building the transaction.**

Present the migration details:

```
## Migrate Position — Confirmation Required

**Migrate position #{positionId} to {dex} {token0}/{token1} pool** on {Chain}

| Detail | Value |
|---|---|
| Source position | #{positionId} |
| Source pool | {sourcePoolDex} {sourceToken0}/{sourceToken1} ({sourceFeeTier}) |
| Source pool address | `{poolFromAddress}` |
| Destination pool | {dex} {destToken0}/{destToken1} ({destFeeTier}) |
| Destination pool address | `{poolToAddress}` |
| New position range | {tickLower} to {tickUpper} (price: {priceLower} to {priceUpper}) |
| Liquidity to migrate | {liquidityAmount} |
| Protocol fee | {feePercentage}% |
| Gas estimate | ~${gasUsd} |
| Slippage tolerance | {slippage/100}% |

### Addresses

| Field | Value |
|---|---|
| ZapRouter | `0x0e97c887b61ccd952a53578b04763e7134429e05` |
| Sender | `{sender}` |

---

**WARNING — Impermanent Loss Risk:**
Providing liquidity carries impermanent loss risk. The value of your position may decrease relative to simply holding the tokens.

**WARNING — Concentrated Liquidity:**
Concentrated liquidity positions require active management. If the price moves outside your range, your position stops earning fees.

**WARNING — Migration is Irreversible:**
This will close your source position and open a new position in the destination pool. You cannot undo this.

**WARNING — ZapRouter Address:**
The ZaaS router address is different from the Aggregator router. Approve `0x0e97c887b61ccd952a53578b04763e7134429e05` (KSZapRouterPosition), NOT the Aggregator router.

Review the migration details carefully.

**Do you want to proceed with building this migrate transaction?** (yes/no)
```

**Wait for the user to explicitly confirm before proceeding.**

If the user says "no", "cancel", or similar, abort and inform them the migration was cancelled.

### Step 3: Build the Migrate Transaction (POST request)

**Only proceed to this step after the user confirms in Step 2.**

**WebFetch only supports GET requests**, so use `Bash(curl)` for this POST request.

```bash
curl -s --connect-timeout 10 --max-time 30 \
  -X POST "https://zap-api.kyberswap.com/{chain}/api/v1/migrate/route/build" \
  -H "Content-Type: application/json" \
  -H "X-Client-Id: ai-agent-skills" \
  -d '{
    "sender": "{sender}",
    "route": {PASTE THE COMPLETE route OBJECT FROM STEP 1},
    "deadline": {CURRENT_UNIX_TIMESTAMP + 1200},
    "source": "ai-agent-skills"
  }'
```

**Important:** The `route` field must contain the **exact** JSON object returned from Step 1. Do not modify, truncate, or reformat it.

### Step 3b: Handle Build Errors

If the build request fails, check the response for error details:

| Scenario | Quick Fix |
|---------|-----------|
| Route expired | The route data is stale. Fetch a fresh route and retry |
| Price moved | Price changed significantly. Fetch fresh route or increase slippage |
| Insufficient gas | Sender doesn't have enough native token for gas |
| Approval missing | Sender hasn't approved the ZapRouter to manage the source position NFT |

### Step 4: Format the Migrate Output

Present the results:

```
## KyberSwap Migrate Transaction

**Migrate position #{positionId} to {dex} {destToken0}/{destToken1} pool** on {Chain}

| Detail | Value |
|---|---|
| Source position | #{positionId} |
| Source pool | {sourcePoolDex} {sourceToken0}/{sourceToken1} |
| Destination pool | {dex} {destToken0}/{destToken1} ({destFeeTier}) |
| Destination pool address | `{poolToAddress}` |
| New position range | {tickLower} to {tickUpper} |
| Slippage tolerance | {slippage/100}% |
| Gas estimate | ~${gasUsd} |

### Transaction Details

| Field | Value |
|---|---|
| To (ZapRouter) | `0x0e97c887b61ccd952a53578b04763e7134429e05` |
| Value | `0` |
| Data | `{encodedCalldata}` |
| Sender | `{sender}` |

> **WARNING:** Review the transaction details carefully before submitting on-chain. This plugin does NOT submit transactions — it only builds the calldata. You are responsible for verifying the ZapRouter address, amounts, and calldata before signing and broadcasting.

> **WARNING:** Migration is irreversible. Your source position will be closed and a new position will be opened in the destination pool.
```

### Structured JSON Output (Migrate)

````
```json
{
  "type": "kyberswap-zap-migrate",
  "chain": "{chain}",
  "sourcePosition": {
    "positionId": "{positionId}",
    "pool": "{poolFromAddress}",
    "dex": "{sourcePoolDex}"
  },
  "destinationPool": {
    "address": "{poolToAddress}",
    "dex": "{dex}",
    "token0": "{destToken0Symbol}",
    "token1": "{destToken1Symbol}",
    "feeTier": "{destFeeTier}"
  },
  "position": {
    "tickLower": {tickLower},
    "tickUpper": {tickUpper}
  },
  "tx": {
    "to": "0x0e97c887b61ccd952a53578b04763e7134429e05",
    "data": "{encodedCalldata}",
    "value": "0",
    "gas": "{gas}",
    "gasUsd": "{gasUsd}"
  },
  "sender": "{sender}",
  "slippageBps": {slippage}
}
```
````

### Step 5: NFT Approval Reminder (Migrate)

For migrate operations, the sender must approve the ZapRouter to manage the source position NFT. See `${CLAUDE_PLUGIN_ROOT}/references/approval-guide.md` (ERC-721 section). Use:

- **NFT contract:** `{nftManagerAddress}` (the DEX's position manager)
- **Spender (ZapRouter):** `0x0e97c887b61ccd952a53578b04763e7134429e05`
- **Token ID:** `{positionId}`

## Contract Addresses

| Contract | Address | Notes |
|---|---|---|
| KSZapRouterPosition | `0x0e97c887b61ccd952a53578b04763e7134429e05` | Same address on all 13 supported chains |
| KSZapValidatorV2Part1 | `0xa16f32442209c6b978431818aa535bcc9ad2863e` | Validator contract, same on all chains |

## Important Notes

- Always read `${CLAUDE_PLUGIN_ROOT}/references/token-registry.md` before making API calls to resolve token addresses.
- Never guess token addresses, pool addresses, or sender addresses.
- If the user doesn't specify a chain, default to `ethereum`.
- If the user specifies a chain not in the [Supported Chains](#supported-chains-13) table, inform them that ZaaS only supports 13 chains and list the available options.
- If the user doesn't specify slippage, use the smart defaults from the [Slippage Defaults](#slippage-defaults) table.
- Routes expire quickly (~30 seconds). If the build step fails, re-fetch the route from the GET endpoint and retry.
- This skill does NOT submit transactions on-chain. It only builds the calldata.
- **Migrate** operations close the source position entirely and open a new one. This is irreversible.
- The ZapRouter address (`0x0e97c887b61ccd952a53578b04763e7134429e05`) is different from the Aggregator router (`0x6131B5fae19EA4f9D964eAc0408E4408b66337b5`). Approvals must target the correct contract.
- All `curl` commands must include `--connect-timeout 10 --max-time 30` for timeout safety.
- All `curl` commands must include `-H "X-Client-Id: ai-agent-skills"` header.

## Additional Resources

### Reference Files

- **`${CLAUDE_PLUGIN_ROOT}/references/api-reference.md`** — Full Aggregator API specification, error codes, rate limiting
- **`${CLAUDE_PLUGIN_ROOT}/references/token-registry.md`** — Token addresses and decimals by chain

### External Documentation

- **ZaaS Overview:** https://docs.kyberswap.com/kyberswap-solutions/kyberswap-zap-as-a-service
- **ZaaS HTTP API:** https://docs.kyberswap.com/kyberswap-solutions/kyberswap-zap-as-a-service/kyberswap-zap-as-a-service-zaas-api/zaas-http-api
- **Zap Fee Model:** https://docs.kyberswap.com/kyberswap-solutions/kyberswap-zap-as-a-service/zap-fee-model
- **Supported Chains/DEXes:** https://docs.kyberswap.com/kyberswap-solutions/kyberswap-zap-as-a-service/zaps-supported-chains-dexes
- **Deployed Contracts:** https://docs.kyberswap.com/kyberswap-solutions/kyberswap-zap-as-a-service/zaps-deployed-contract-addresses
- **DEX IDs:** https://docs.kyberswap.com/kyberswap-solutions/kyberswap-zap-as-a-service/dex-ids

## Troubleshooting

### Common Issues

| Issue | Resolution |
|---|---|
| "Pool not found" | Verify the pool address and DEX identifier. Pool must exist on the specified chain. |
| "Invalid tick range" | Ticks must be multiples of the pool's tick spacing. Use the full-range ticks listed in Step 4 if unsure. |
| "Insufficient liquidity" | The pool may not support the requested zap amount. Try a smaller amount. |
| "Route expired" | Routes are valid for ~30 seconds. Re-fetch the route and rebuild. |
| "Approval missing" | Approve the ZapRouter (`0x0e97c887b61ccd952a53578b04763e7134429e05`), not the Aggregator router. |
| "Position not found" | Verify the NFT token ID and that the sender owns the position. |
| "Same pool" | Source and destination pool are identical. Migration requires different pools. |
| Rate limited (429) | Default limit is 10 requests per 10 seconds. Wait and retry. |

For error codes not covered above, or for advanced debugging, refer to **`${CLAUDE_PLUGIN_ROOT}/skills/error-handling/SKILL.md`**.
