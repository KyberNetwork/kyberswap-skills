# Address Validation

Validate wallet addresses (maker/sender) before any operation. These checks apply to all skills that accept a wallet address.

## Rules

1. **Required** — If the address is not provided, ask the user for it. Do not guess or use a placeholder.

2. **Must not be the zero address** — `0x0000000000000000000000000000000000000000` is an invalid address. Any operation will fail.

3. **Must not be the native token sentinel** — `0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE` is a placeholder for native tokens, not a real account.

4. **Format check** — Must match `^0x[a-fA-F0-9]{40}$` (0x prefix + 40 hex characters).

5. **Warn if known contract** — If the address matches a known contract (token address, router, DSLOProtocol), warn the user that this is unusual and ask for confirmation.
