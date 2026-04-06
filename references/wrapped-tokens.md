# Wrapped Token Addresses

Limit orders require ERC-20 tokens. The native token sentinel (`0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE`) is NOT valid for limit order `makerAsset` or `takerAsset`. When a user specifies a native token alias, resolve to the wrapped ERC-20 equivalent below.

| User says | Chain(s) | Wrapped ERC-20 | Address |
|---|---|---|---|
| "ETH" | Ethereum | WETH | `0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2` |
| "ETH" | Arbitrum | WETH | `0x82aF49447D8a07e3bd95BD0d56f35241523fBab1` |
| "ETH" | Optimism | WETH | `0x4200000000000000000000000000000000000006` |
| "ETH" | Base | WETH | `0x4200000000000000000000000000000000000006` |
| "ETH" | Linea | WETH | `0xe5D7C2a44FfDDf6b295A15c148167daaAf5Cf34f` |
| "ETH" | Unichain | WETH | look up in token registry |
| "MATIC" / "POL" | Polygon | WPOL | `0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270` |
| "BNB" | BSC | WBNB | `0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c` |
| "AVAX" | Avalanche | WAVAX | `0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7` |
| "MNT" | Mantle | WMNT | look up in token registry |
| "S" | Sonic | WS | look up in token registry |
| "BERA" | Berachain | WBERA | look up in token registry |
| "RON" | Ronin | WRON | look up in token registry |
| "XTZ" | Etherlink | WXTZ | look up in token registry |
| "MON" | Monad | WMON | look up in token registry |

When auto-converting, display a note: *"Native {TOKEN} converted to W{TOKEN} for limit orders — the Limit Order API requires ERC-20 tokens, not native token addresses."*

For tokens marked "look up in token registry", check `token-registry.md` or the KyberSwap Token API for the current wrapped token address.
