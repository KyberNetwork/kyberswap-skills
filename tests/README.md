# Tests

Test suite for verifying the KyberSwap Agent Skills work correctly.

## Structure

```
tests/
├── README.md              # This file
├── test-fast-swap.sh      # Automated tests for fast-swap.sh
└── agent-test-cases.md    # Manual test prompts for AI agent validation
```

## Automated Tests: fast-swap.sh

Tests the shell script directly with real API calls.

```bash
# Run all tests (unit + live API calls)
bash tests/test-fast-swap.sh

# Unit tests only (offline, no network needed)
bash tests/test-fast-swap.sh unit

# Live API tests only
bash tests/test-fast-swap.sh live
```

**What it tests:**
- `to_wei` / `from_wei` math correctness (12+ cases each)
- Roundtrip conversion accuracy
- Native → ERC-20 swap (ETH→USDC on Ethereum)
- ERC-20 → Native swap (USDC→ETH)
- L2 chain swap (Arbitrum)
- Token API fallback (LINK — not in built-in registry)
- Stablecoin pair (USDC→USDT)
- Multi-chain: Polygon (POL→USDC), BSC (BNB→USDT)
- Error: missing arguments, unsupported chain, unknown token

**Requirements:** `curl`, `jq`, internet access (for live tests)

## Agent Test Cases

20 test prompts to manually verify AI agent behavior with all three skills.

See `agent-test-cases.md` for the full list. Each test has:
- Input prompt to give the agent
- Expected step-by-step behavior
- Validation checklist

**How to use:**
1. Load the skills in your AI agent (quote, swap, fast-swap)
2. Run each prompt from `agent-test-cases.md`
3. Check the agent's output against the validation criteria
4. Score: count how many pass out of 20

**Coverage:**
- Quote skill: basic, token API fallback, L2, default chain, stablecoins
- Swap skill: sender required, full flow, ERC-20 approval, slippage defaults
- Fast-swap skill: basic, ERC-20 input, stablecoin slippage, token API fallback, different recipient
- Error handling: unsupported chain, route not found, native aliases, multi-chain resolution, large amounts
