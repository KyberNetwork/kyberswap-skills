# KyberSwap Skills

Skills for interacting with the [KyberSwap Aggregator API](https://docs.kyberswap.com/kyberswap-solutions/kyberswap-aggregator). Get swap quotes and build transaction calldata across 18 EVM chains.

## Structure

This is a Claude Code plugin. Skills live in the `skills/` directory; shared API docs and token data live in `references/`.

```
kyberswap-skills/
├── .claude-plugin/
│   └── plugin.json     # Plugin manifest
├── skills/
│   ├── quote/          # Get a swap quote
│   │   └── SKILL.md
│   ├── swap-build/     # Build swap calldata (with confirmation)
│   │   └── SKILL.md
│   ├── swap-execute/   # Execute swap via Foundry cast (with confirmation)
│   │   └── SKILL.md
│   └── swap-execute-fast/  # Build + execute in one step (no confirmation)
│       ├── SKILL.md
│       └── scripts/
│           ├── fast-swap.sh      # Token resolution + route building
│           └── execute-swap.sh   # Calls fast-swap.sh then broadcasts
├── references/         # Shared docs
│   ├── api-reference.md
│   └── token-registry.md
├── tests/              # Test suite
│   ├── test-fast-swap.sh
│   └── agent-test-cases.md
└── README.md
```

## Skills

### quote

Get the best swap route and price for a token pair.

```
/quote 1 ETH to USDC on ethereum
/quote 100 USDC to WBTC on arbitrum
/quote 0.5 WBTC to DAI on polygon
```

Returns: expected output amount, USD values, exchange rate, gas estimate, and the route path (which DEXes are used).

### swap-build

Build a full swap transaction (get route + encoded calldata). Requires a sender address. Shows quote details (exchange rate, minimum output, gas) and asks for confirmation before building.

```
/swap-build 100 USDC to ETH on arbitrum from 0xYourAddress
/swap-build 1 ETH to USDC on ethereum from 0xYourAddress slippage 100
```

Returns: encoded calldata, router address, transaction value, gas estimate, and minimum output after slippage. Does **not** submit the transaction on-chain.

### swap-execute

Execute a previously built swap transaction on-chain using Foundry's `cast send`. Takes the output from `swap-build` and broadcasts it.

```
/swap-execute
```

Requires Foundry (`cast`) installed. Supports multiple wallet methods: environment variable, Ledger, Trezor, or keystore. Shows confirmation before executing (transactions are irreversible).

### swap-execute-fast

Build AND execute a swap in one step — no confirmation prompts.

```
/swap-execute-fast 1 ETH to USDC on base from 0xYourAddress
/swap-execute-fast 100 USDC to ETH on arbitrum from 0xYourAddress keystore mykey
/swap-execute-fast 0.5 WBTC to DAI on polygon from 0xYourAddress ledger
```

Requires `cast`, `curl`, and `jq`. **EXTREMELY DANGEROUS**: Builds and executes immediately without any confirmation. Only use when you fully trust the parameters and understand the risks.

## Installation

Install as a Claude Code plugin:

```bash
# From the Claude Code CLI
/install-plugin https://github.com/kyberswap/kyberswap-skills

# Or test locally
claude --plugin-dir /path/to/kyberswap-skills
```

## Supported Chains

Ethereum, BNB Smart Chain, Arbitrum, Polygon, Optimism, Base, Avalanche, Linea, Mantle, Sonic, Berachain, Ronin, Unichain, HyperEVM, Plasma, Etherlink, Monad, MegaETH.

## How It Works

```
Safe path:
  /quote ──► /swap-build ──► /swap-execute ──► on-chain tx
                (confirm)       (confirm)

Fast path (dangerous):
  /swap-execute-fast ──► on-chain tx (no confirmation)
```

1. **Claude Code plugin** — Installed as a plugin with auto-discovered skills in the `skills/` directory.
2. **Markdown-driven skills** — `quote`, `swap-build`, and `swap-execute` are pure markdown instructions. The agent reads them and executes the workflow directly.
3. **Script-driven skill** — `swap-execute-fast` uses shell scripts (`curl` + `jq` + `cast`) to build and execute in one step.
4. **Token resolution** — Native tokens and major stablecoins are in `references/token-registry.md`. For all other tokens, the agent (or script) queries the KyberSwap Token API (`token-api.kyberswap.com`).
5. **Safety by design** — `swap-build` requires confirmation before building. `swap-execute` requires confirmation before broadcasting. Only `swap-execute-fast` runs without confirmation (for automation use cases).

## Testing

```bash
# Automated tests for fast-swap.sh (unit + live API calls)
bash tests/test-fast-swap.sh

# Unit tests only (offline)
bash tests/test-fast-swap.sh unit
```

See `tests/agent-test-cases.md` for manual test prompts to validate AI agent behavior across all four skills.

## Contributing

1. Fork and create a feature branch
2. Add or update skills with a `SKILL.md`
3. Optionally add reference docs in `references/`
4. Run `bash tests/test-fast-swap.sh` to verify
5. Open a pull request
