# Token & NFT Approval Guide

Before interacting with KyberSwap contracts, users must approve the relevant contract to spend their tokens.

## ERC-20 Token Approval (Swaps, Limit Orders, Zap In)

Before a swap, limit order fill, or zap-in can execute, approve the contract to spend your input token:

- **Token contract:** the ERC-20 token address
- **Spender:** the contract that needs approval (see table below)
- **Amount:** exact amount (recommended) or `type(uint256).max` (unlimited)

| Operation | Spender Contract | Address |
|---|---|---|
| Swap | KyberSwap Aggregator Router | `0x6131B5fae19EA4f9D964eAc0408E4408b66337b5` |
| Limit Order | DSLOProtocol | `0xcab2FA2eeab7065B45CBcF6E3936dDE2506b4f6C` |
| Zap In | KSZapRouterPosition | `0x0e97c887b61ccd952a53578b04763e7134429e05` |

> **Security warning:** Unlimited approvals (`type(uint256).max`) are convenient but risky. If the contract is ever compromised, an attacker could drain all approved tokens. For large holdings, prefer **exact-amount approvals**. Only use unlimited approvals with wallets holding limited funds.

> **IMPORTANT:** Each operation uses a different contract. Do not confuse the Aggregator Router with the ZapRouter or DSLOProtocol. Approving the wrong contract will not work.

## ERC-721 NFT Approval (Zap Out, Migrate)

Before zap-out or migrate operations, approve the ZapRouter to manage the position NFT:

- **NFT contract:** the DEX's position manager (varies by DEX)
- **Spender:** KSZapRouterPosition `0x0e97c887b61ccd952a53578b04763e7134429e05`
- **Token ID:** the specific position NFT token ID

**Options:**
- `approve(0x0e97c887b61ccd952a53578b04763e7134429e05, {tokenId})` — approve single NFT (safer)
- `setApprovalForAll(0x0e97c887b61ccd952a53578b04763e7134429e05, true)` — approve all NFTs on this DEX (convenient but riskier)

> **Security warning:** `setApprovalForAll` grants access to ALL your position NFTs on this DEX. Prefer single-token `approve` for better security.

Use your wallet or a tool like `cast` to send the approval transaction.
