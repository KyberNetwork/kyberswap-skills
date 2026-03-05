# Supported Chains

Chain support varies by KyberSwap service. Use this reference to check which chains are available for each operation.

## Aggregator (Swap/Quote) — 18 chains

| Chain | Path Slug | Chain ID |
|---|---|---|
| Ethereum | `ethereum` | `1` |
| BNB Smart Chain | `bsc` | `56` |
| Arbitrum | `arbitrum` | `42161` |
| Polygon | `polygon` | `137` |
| Optimism | `optimism` | `10` |
| Base | `base` | `8453` |
| Avalanche | `avalanche` | `43114` |
| Linea | `linea` | `59144` |
| Mantle | `mantle` | `5000` |
| Sonic | `sonic` | `146` |
| Berachain | `berachain` | `80094` |
| Ronin | `ronin` | `2020` |
| Unichain | `unichain` | `130` |
| HyperEVM | `hyperevm` | `999` |
| Plasma | `plasma` | `9745` |
| Etherlink | `etherlink` | `42793` |
| Monad | `monad` | `143` |
| MegaETH | `megaeth` | `4326` |

## Limit Orders — 17 chains

All Aggregator chains **except MegaETH**. If a user requests MegaETH for limit orders, inform them it is not supported and suggest using a swap instead.

## ZaaS (Zap) — 13 chains

Ethereum, BNB Smart Chain, Arbitrum, Polygon, Optimism, Base, Avalanche, Linea, Scroll (`534352`), zkSync (`324`), Sonic, Berachain, Ronin.

**Not supported for zap:** Mantle, Unichain, HyperEVM, Plasma, Etherlink, Monad, MegaETH.

## Quick Lookup

| Chain | Swap | Limit Order | Zap |
|---|---|---|---|
| Ethereum | ✅ | ✅ | ✅ |
| BNB Smart Chain | ✅ | ✅ | ✅ |
| Arbitrum | ✅ | ✅ | ✅ |
| Polygon | ✅ | ✅ | ✅ |
| Optimism | ✅ | ✅ | ✅ |
| Base | ✅ | ✅ | ✅ |
| Avalanche | ✅ | ✅ | ✅ |
| Linea | ✅ | ✅ | ✅ |
| Scroll | ✅ | ✅ | ✅ |
| zkSync | ✅ | ✅ | ✅ |
| Sonic | ✅ | ✅ | ✅ |
| Berachain | ✅ | ✅ | ✅ |
| Ronin | ✅ | ✅ | ✅ |
| Mantle | ✅ | ✅ | ❌ |
| Unichain | ✅ | ✅ | ❌ |
| HyperEVM | ✅ | ✅ | ❌ |
| Plasma | ✅ | ✅ | ❌ |
| Etherlink | ✅ | ✅ | ❌ |
| Monad | ✅ | ✅ | ❌ |
| MegaETH | ✅ | ❌ | ❌ |

To get the live list of supported chains, query:
```
GET https://common-service.kyberswap.com/api/v1/aggregator/supported-chains
```
