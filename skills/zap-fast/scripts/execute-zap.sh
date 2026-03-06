#!/usr/bin/env bash
#
# execute-zap.sh - Build and execute a KyberSwap zap-in transaction in one step
#
# WARNING: This script must be executed, not sourced. Do NOT run: source execute-zap.sh
#          Sourcing would leak ETH_PRIVATE_KEY into the parent shell environment.
#
# Usage:
#   ./execute-zap.sh <tokenIn> <amountIn> <poolAddress> <dex> <tickLower> <tickUpper> <chain> <sender> [slippage_bps] [wallet_method] [keystore_name]
#
# Arguments:
#   tokenIn        Input token symbol (e.g. ETH, USDC) or address:decimals
#   amountIn       Human-readable amount (e.g. 1, 0.5, 100)
#   poolAddress    Pool contract address (0x...)
#   dex            DEX identifier (e.g. uniswapv3, pancakev3)
#   tickLower      Lower tick of the position
#   tickUpper      Upper tick of the position
#   chain          Chain slug (e.g. ethereum, arbitrum, base)
#   sender         Sender wallet address
#   slippage_bps   Slippage in basis points (default: 100)
#   wallet_method  keystore | env | ledger | trezor (default: keystore)
#   keystore_name  Keystore account name (default: mykey)
#
# Environment:
#   PRIVATE_KEY             Required if wallet_method=env
#   KEYSTORE_PASSWORD_FILE  Override default ~/.foundry/.password
#   RPC_URL_OVERRIDE        Override chain RPC URL
#   FAST_ZAP_MAX_USD        Override $1000 USD threshold (default: 1000)
#
# Example:
#   ./execute-zap.sh ETH 1 0xPoolAddr uniswapv3 -887220 887220 arbitrum 0xYourAddress 100 keystore mykey
#
set -euo pipefail

# Ensure ETH_PRIVATE_KEY is always cleared on exit (normal, error, or signal)
trap 'unset ETH_PRIVATE_KEY PRIVATE_KEY 2>/dev/null' EXIT INT TERM

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FAST_ZAP_SCRIPT="${SCRIPT_DIR}/fast-zap.sh"
PASSWORD_FILE="${KEYSTORE_PASSWORD_FILE:-$HOME/.foundry/.password}"
ZAP_ROUTER="0x0e97c887b61ccd952a53578b04763e7134429e05"

# Get RPC URL for chain
get_rpc_url() {
  local chain="$1"
  case "$chain" in
    ethereum)   echo "https://ethereum-rpc.publicnode.com" ;;
    arbitrum)   echo "https://arb1.arbitrum.io/rpc" ;;
    polygon)    echo "https://polygon-rpc.com" ;;
    optimism)   echo "https://mainnet.optimism.io" ;;
    base)       echo "https://mainnet.base.org" ;;
    bsc)        echo "https://bsc-dataseed.binance.org" ;;
    avalanche)  echo "https://api.avax.network/ext/bc/C/rpc" ;;
    linea)      echo "https://rpc.linea.build" ;;
    sonic)      echo "https://rpc.soniclabs.com" ;;
    berachain)  echo "https://rpc.berachain.com" ;;
    ronin)      echo "https://api.roninchain.com/rpc" ;;
    scroll)     echo "https://rpc.scroll.io" ;;
    zksync)     echo "https://mainnet.era.zksync.io" ;;
    *)          echo "" ;;
  esac
}

# Get fallback RPC URL for chain (used when primary RPC fails)
get_fallback_rpc_url() {
  local chain="$1"
  case "$chain" in
    ethereum)   echo "https://eth.llamarpc.com" ;;
    arbitrum)   echo "https://rpc.ankr.com/arbitrum" ;;
    polygon)    echo "https://rpc.ankr.com/polygon" ;;
    optimism)   echo "https://rpc.ankr.com/optimism" ;;
    base)       echo "https://rpc.ankr.com/base" ;;
    bsc)        echo "https://bsc-dataseed1.defibit.io" ;;
    avalanche)  echo "https://rpc.ankr.com/avalanche" ;;
    *)          echo "" ;;
  esac
}

# Get block explorer URL for chain
get_explorer_url() {
  local chain="$1"
  case "$chain" in
    ethereum)   echo "https://etherscan.io" ;;
    arbitrum)   echo "https://arbiscan.io" ;;
    polygon)    echo "https://polygonscan.com" ;;
    optimism)   echo "https://optimistic.etherscan.io" ;;
    base)       echo "https://basescan.org" ;;
    bsc)        echo "https://bscscan.com" ;;
    avalanche)  echo "https://snowtrace.io" ;;
    linea)      echo "https://lineascan.build" ;;
    sonic)      echo "https://sonicscan.io" ;;
    berachain)  echo "https://berascan.com" ;;
    ronin)      echo "https://app.roninchain.com" ;;
    scroll)     echo "https://scrollscan.com" ;;
    zksync)     echo "https://era.zksync.network" ;;
    *)          echo "https://etherscan.io" ;;
  esac
}

# Get expected chain ID for chain slug (chain ID verification)
get_expected_chain_id() {
  local chain="$1"
  case "$chain" in
    ethereum)   echo "1" ;;
    arbitrum)   echo "42161" ;;
    polygon)    echo "137" ;;
    optimism)   echo "10" ;;
    base)       echo "8453" ;;
    bsc)        echo "56" ;;
    avalanche)  echo "43114" ;;
    linea)      echo "59144" ;;
    sonic)      echo "146" ;;
    berachain)  echo "80094" ;;
    ronin)      echo "2020" ;;
    scroll)     echo "534352" ;;
    zksync)     echo "324" ;;
    *)          echo "" ;;
  esac
}

# -----------------------------------------------------------------------------
# Helpers
# -----------------------------------------------------------------------------

log() { echo "[execute-zap] $*" >&2; }
error() { echo "[execute-zap] ERROR: $*" >&2; }

json_output() {
  local ok="$1"
  shift
  if [[ "$ok" == "true" ]]; then
    echo "$@"
  else
    jq -n --arg error "$1" '{"ok": false, "error": $error}'
  fi
}

usage() {
  cat >&2 <<EOF
Usage: $0 <tokenIn> <amountIn> <poolAddress> <dex> <tickLower> <tickUpper> <chain> <sender> [slippage_bps] [wallet_method] [keystore_name]

Arguments:
  tokenIn        Input token symbol (e.g. ETH, USDC) or address:decimals
  amountIn       Human-readable amount (e.g. 1, 0.5, 100)
  poolAddress    Pool contract address (0x...)
  dex            DEX identifier (e.g. uniswapv3, pancakev3)
  tickLower      Lower tick of the position
  tickUpper      Upper tick of the position
  chain          Chain slug (e.g. ethereum, arbitrum, base)
  sender         Sender wallet address
  slippage_bps   Slippage in basis points (default: 100)
  wallet_method  keystore | env | ledger | trezor (default: keystore)
  keystore_name  Keystore account name (default: mykey)

Examples:
  $0 ETH 1 0xPoolAddr uniswapv3 -887220 887220 arbitrum 0xYourAddress
  $0 USDC 100 0xPoolAddr pancakev3 -100 100 base 0xYourAddress 50 keystore mykey
  $0 ETH 0.5 0xPoolAddr uniswapv3 -1000 1000 polygon 0xSender 100 env
  $0 ETH 1 0xPoolAddr uniswapv3 -887220 887220 base 0xYourAddress 100 ledger
EOF
  exit 1
}

# -----------------------------------------------------------------------------
# Validation
# -----------------------------------------------------------------------------

check_dependencies() {
  if ! command -v cast &>/dev/null; then
    json_output false "Zap failed (pre-flight): cast not found. Install Foundry: download a verified release from github.com/foundry-rs/foundry/releases and verify the checksum before running. No transaction was submitted."
    exit 1
  fi
  if ! command -v jq &>/dev/null; then
    json_output false "Zap failed (pre-flight): jq not found. Install: brew install jq (mac) or apt install jq (linux). No transaction was submitted."
    exit 1
  fi
  if ! command -v curl &>/dev/null; then
    json_output false "Zap failed (pre-flight): curl not found. Install: brew install curl (mac) or apt install curl (linux). No transaction was submitted."
    exit 1
  fi
  if [[ ! -f "$FAST_ZAP_SCRIPT" ]]; then
    json_output false "Zap failed (pre-flight): fast-zap.sh not found at: $FAST_ZAP_SCRIPT. No transaction was submitted."
    exit 1
  fi
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------

main() {
  check_dependencies

  # Parse arguments
  local token_in="${1:-}"
  local amount="${2:-}"
  local pool_address="${3:-}"
  local dex="${4:-}"
  local tick_lower="${5:-}"
  local tick_upper="${6:-}"
  local chain="${7:-}"
  local sender="${8:-}"
  local slippage_bps="${9:-100}"
  local wallet_method="${10:-keystore}"
  local keystore_name="${11:-mykey}"

  # Validate required arguments
  if [[ -z "$token_in" || -z "$amount" || -z "$pool_address" || -z "$dex" || -z "$tick_lower" || -z "$tick_upper" || -z "$chain" || -z "$sender" ]]; then
    usage
  fi

  # Input format validation to prevent injection attacks
  if ! [[ "$amount" =~ ^[0-9]*\.?[0-9]+$ ]]; then
    json_output false "Zap failed (pre-flight): Invalid amount format '$amount'. Must be a positive number (e.g. 1, 0.5, 100). No transaction was submitted."
    exit 1
  fi
  if ! [[ "$token_in" =~ ^[a-zA-Z0-9.]+$ ]] && ! [[ "$token_in" =~ ^0x[a-fA-F0-9]{40}:[0-9]+$ ]]; then
    json_output false "Zap failed (pre-flight): Invalid tokenIn '$token_in'. Must be a symbol (e.g. ETH) or address:decimals (e.g. 0xA0b8...:6). No transaction was submitted."
    exit 1
  fi
  if ! [[ "$pool_address" =~ ^0x[a-fA-F0-9]{40}$ ]] && ! [[ "$pool_address" =~ ^0x[a-fA-F0-9]{64}$ ]]; then
    json_output false "Zap failed (pre-flight): Invalid pool address/ID '$pool_address'. Must be 0x + 40 hex chars (address) or 0x + 64 hex chars (V4 pool ID). No transaction was submitted."
    exit 1
  fi
  if ! [[ "$dex" =~ ^[a-zA-Z0-9_-]+$ ]]; then
    json_output false "Zap failed (pre-flight): Invalid dex identifier '$dex'. Must contain only alphanumeric characters, hyphens, and underscores. No transaction was submitted."
    exit 1
  fi
  if ! [[ "$tick_lower" =~ ^-?[0-9]+$ ]]; then
    json_output false "Zap failed (pre-flight): Invalid tickLower '$tick_lower'. Must be an integer. No transaction was submitted."
    exit 1
  fi
  if ! [[ "$tick_upper" =~ ^-?[0-9]+$ ]]; then
    json_output false "Zap failed (pre-flight): Invalid tickUpper '$tick_upper'. Must be an integer. No transaction was submitted."
    exit 1
  fi
  if ! [[ "$chain" =~ ^[a-z0-9-]+$ ]]; then
    json_output false "Zap failed (pre-flight): Invalid chain slug '$chain'. Must contain only lowercase letters, digits, and hyphens. No transaction was submitted."
    exit 1
  fi

  # Validate sender address format
  if ! [[ "$sender" =~ ^0x[a-fA-F0-9]{40}$ ]]; then
    json_output false "Zap failed (pre-flight): Invalid sender address '$sender'. Must be a valid Ethereum address (0x + 40 hex chars). No transaction was submitted."
    exit 1
  fi

  # Validate slippage_bps and keystore_name
  if [[ -n "$slippage_bps" ]] && ! [[ "$slippage_bps" =~ ^[0-9]+$ ]]; then
    json_output false "Zap failed (pre-flight): Invalid slippage '$slippage_bps'. Must be a non-negative integer (basis points). No transaction was submitted."
    exit 1
  fi
  if [[ -n "$keystore_name" ]] && ! [[ "$keystore_name" =~ ^[a-zA-Z0-9_.-]+$ ]]; then
    json_output false "Zap failed (pre-flight): Invalid keystore name '$keystore_name'. Must contain only letters, digits, underscores, dots, and hyphens. No transaction was submitted."
    exit 1
  fi

  log "Building zap: $amount $token_in into pool $pool_address ($dex) on $chain"
  log "Sender: $sender"
  log "Ticks: [$tick_lower, $tick_upper]"
  log "Slippage: ${slippage_bps} bps"

  # ---------------------------------------------------------------------------
  # Step 1: Build the zap using fast-zap.sh
  # ---------------------------------------------------------------------------

  log "Calling fast-zap.sh to build transaction..."

  local build_output
  local build_exit_code=0

  # Capture stdout (JSON) separately from stderr (debug messages)
  # stderr flows through to user, stdout is captured for parsing
  build_output=$(bash "$FAST_ZAP_SCRIPT" "$token_in" "$amount" "$pool_address" "$dex" "$tick_lower" "$tick_upper" "$chain" "$sender" "$slippage_bps") || build_exit_code=$?

  # Validate JSON is parseable
  if ! echo "$build_output" | jq -e . >/dev/null 2>&1; then
    # Try to extract JSON from potentially mixed output (fallback)
    local extracted_json
    extracted_json=$(echo "$build_output" | grep -o '{.*}' | tail -1 2>/dev/null || true)
    if [[ -n "$extracted_json" ]] && echo "$extracted_json" | jq -e . >/dev/null 2>&1; then
      build_output="$extracted_json"
    else
      json_output false "Zap failed (pre-flight): Invalid JSON output from fast-zap.sh. No transaction was submitted."
      exit 1
    fi
  fi

  # Check if build succeeded
  local build_ok
  build_ok=$(echo "$build_output" | jq -r '.ok // "false"' 2>/dev/null || echo "false")

  if [[ "$build_ok" != "true" ]]; then
    local build_error
    build_error=$(echo "$build_output" | jq -r '.error // empty' 2>/dev/null || echo "$build_output")
    json_output false "Zap failed (pre-flight): Build failed -- $build_error. No transaction was submitted."
    exit 1
  fi

  log "Zap built successfully"

  # Enforce USD threshold for fast zap safety
  local max_usd="${FAST_ZAP_MAX_USD:-1000}"
  if ! [[ "$max_usd" =~ ^[0-9]+$ ]]; then max_usd=1000; fi
  local amount_in_usd
  amount_in_usd=$(echo "$build_output" | jq -r '.zap.amountInUsd // "0"' 2>/dev/null || echo "0")
  # Sanitize: must be a valid number (integer or decimal)
  if ! [[ "$amount_in_usd" =~ ^[0-9]*\.?[0-9]+$ ]]; then
    amount_in_usd="0"
  fi
  if [[ "$amount_in_usd" == "0" ]]; then
    json_output false "Zap failed (pre-flight): Could not verify USD value of zap (API returned null/zero for amountInUsd). Fast execution aborted for safety — use /zap with manual review instead. No transaction was submitted."
    exit 1
  fi
  if command -v bc &>/dev/null; then
    if (( $(echo "$amount_in_usd > $max_usd" | bc -l 2>/dev/null || echo 0) )); then
      json_output false "Zap failed (pre-flight): Zap value \$${amount_in_usd} USD exceeds fast-zap safety threshold of \$${max_usd} USD. For large zaps, use /zap with manual review. No transaction was submitted."
      exit 1
    fi
    log "USD value check: \$${amount_in_usd} within \$${max_usd} threshold"
  fi

  # ---------------------------------------------------------------------------
  # Step 2: Extract transaction data
  # ---------------------------------------------------------------------------

  local to data value gas gas_original
  to=$(echo "$build_output" | jq -r '.tx.to // empty')
  data=$(echo "$build_output" | jq -r '.tx.data // empty')
  value=$(echo "$build_output" | jq -r '.tx.value // "0"')
  gas=$(echo "$build_output" | jq -r '.tx.gas // "500000"')

  # Sanitize value: must be numeric to prevent bc injection
  [[ "$value" =~ ^[0-9]+$ ]] || value="0"

  # For native token zaps, if the build API returned value=0 or null,
  # fall back to amountInWei — the router needs the native token sent as msg.value
  local token_in_is_native_check
  token_in_is_native_check=$(echo "$build_output" | jq -r '.tokenIn.isNative // false')
  if [[ "$token_in_is_native_check" == "true" && "$value" == "0" ]]; then
    local fallback_value
    fallback_value=$(echo "$build_output" | jq -r '.zap.amountInWei // empty')
    if [[ "$fallback_value" =~ ^[0-9]+$ && "$fallback_value" != "0" ]]; then
      log "Build API returned value=0 for native token zap, using amountInWei=$fallback_value"
      value="$fallback_value"
    fi
  fi

  # Sanitize gas: must be numeric to prevent bc injection
  [[ "$gas" =~ ^[0-9]+$ ]] || gas="500000"

  # Apply 20% buffer to gas limit for safety margin
  if [[ "$gas" =~ ^[0-9]+$ ]]; then
    gas_original="$gas"
    gas=$(( gas + gas / 2 ))
    log "Gas limit: ${gas_original} -> ${gas} (+50% buffer)"
  fi

  if [[ -z "$to" || -z "$data" ]]; then
    json_output false "Zap failed (pre-flight): Invalid build output -- missing tx.to or tx.data. No transaction was submitted."
    exit 1
  fi

  # Verify router address matches expected ZapRouter
  local expected_router="${EXPECTED_ZAP_ROUTER_OVERRIDE:-$ZAP_ROUTER}"
  if [[ -n "${EXPECTED_ZAP_ROUTER_OVERRIDE:-}" ]]; then
    if ! [[ "$expected_router" =~ ^0x[a-fA-F0-9]{40}$ ]]; then
      json_output false "Zap failed (pre-flight): Invalid EXPECTED_ZAP_ROUTER_OVERRIDE format. Must be a valid Ethereum address (0x + 40 hex chars). No transaction was submitted."
      exit 1
    fi
    log "WARNING: Using custom ZapRouter override: $expected_router"
  fi
  local to_lower
  to_lower=$(echo "$to" | tr '[:upper:]' '[:lower:]')
  local expected_lower
  expected_lower=$(echo "$expected_router" | tr '[:upper:]' '[:lower:]')
  if [[ "$to_lower" != "$expected_lower" ]]; then
    json_output false "Zap failed (pre-flight): Unexpected router address '$to'. Expected ZapRouter: $expected_router. This could indicate a compromised API response. No transaction was submitted."
    exit 1
  fi

  # Get zap info for output
  local amount_in token_in_symbol zap_pool_address zap_dex
  amount_in=$(echo "$build_output" | jq -r '.zap.amountIn // "?"')
  token_in_symbol=$(echo "$build_output" | jq -r '.tokenIn.symbol // "?"')
  zap_pool_address=$(echo "$build_output" | jq -r '.zap.poolAddress // "?"')
  zap_dex=$(echo "$build_output" | jq -r '.zap.dex // "?"')

  # Get token info for approval check
  local token_in_address token_in_is_native amount_in_wei router_address
  token_in_address=$(echo "$build_output" | jq -r '.tokenIn.address // empty')
  token_in_is_native=$(echo "$build_output" | jq -r '.tokenIn.isNative // false')
  amount_in_wei=$(echo "$build_output" | jq -r '.zap.amountInWei // empty')
  # Sanitize amount_in_wei: must be numeric for bc comparisons
  [[ "$amount_in_wei" =~ ^[0-9]+$ ]] || amount_in_wei=""
  router_address="$to"

  # Resolve RPC URL (needed for all on-chain pre-flight checks)
  local rpc_url="${RPC_URL_OVERRIDE:-$(get_rpc_url "$chain")}"
  if [[ -z "$rpc_url" ]]; then
    json_output false "Zap failed (pre-flight): Unknown chain '$chain'. Set RPC_URL_OVERRIDE env var. No transaction was submitted."
    exit 1
  fi

  # ---------------------------------------------------------------------------
  # Step 3: Pre-flight balance checks
  #   Order matters: native balance -> token balance -> allowance
  #   No point approving if you don't have the tokens or gas.
  # ---------------------------------------------------------------------------

  # 3a) Native balance: covers gas + tx.value
  log "Checking gas price and native balance..."

  local gas_price_wei
  gas_price_wei=$(cast gas-price --rpc-url "$rpc_url" 2>/dev/null || echo "0")
  gas_price_wei="${gas_price_wei%%[^0-9]*}"
  gas_price_wei="${gas_price_wei:-0}"

  # Retry with fallback RPC if primary fails for gas price
  if [[ "$gas_price_wei" == "0" ]]; then
    local fallback_rpc
    fallback_rpc=$(get_fallback_rpc_url "$chain")
    if [[ -n "$fallback_rpc" && "$fallback_rpc" != "$rpc_url" ]]; then
      log "Primary RPC failed for gas price, trying fallback..."
      gas_price_wei=$(cast gas-price --rpc-url "$fallback_rpc" 2>/dev/null || echo "0")
      gas_price_wei="${gas_price_wei%%[^0-9]*}"
      gas_price_wei="${gas_price_wei:-0}"
      # Switch to fallback for remaining calls if it works
      if [[ "$gas_price_wei" != "0" ]]; then
        rpc_url="$fallback_rpc"
        log "Switched to fallback RPC: $rpc_url"
      fi
    fi
  fi

  if [[ "$gas_price_wei" =~ ^[0-9]+$ ]] && (( gas_price_wei > 0 )); then
    local gas_price_gwei
    gas_price_gwei=$(echo "scale=2; $gas_price_wei / 1000000000" | bc -l 2>/dev/null || echo "?")
    log "Gas price: ${gas_price_gwei} gwei"

    local gas_cost_wei total_native_needed
    gas_cost_wei=$(echo "$gas * $gas_price_wei" | bc 2>/dev/null || echo "0")
    total_native_needed=$(echo "$value + $gas_cost_wei" | bc 2>/dev/null || echo "0")

    local native_balance
    native_balance=$(cast balance --rpc-url "$rpc_url" "$sender" 2>/dev/null || echo "0")
    native_balance="${native_balance%%[^0-9]*}"
    native_balance="${native_balance:-0}"

    if [[ "$native_balance" =~ ^[0-9]+$ ]] && [[ "$total_native_needed" =~ ^[0-9]+$ ]] && command -v bc &>/dev/null; then
      if (( $(echo "$native_balance < $total_native_needed" | bc -l) )); then
        json_output false "Zap failed (pre-flight): Insufficient native token balance. Have: ${native_balance} wei, Need: ~${total_native_needed} wei (value: ${value} + gas: ~${gas_cost_wei}). No transaction was submitted."
        exit 1
      fi
    fi
    log "Native balance OK: ${native_balance} wei (need ~${total_native_needed})"
  else
    log "Could not fetch gas price -- skipping native balance pre-check"
  fi

  # 3b) ERC-20 token balance + allowance (only for non-native input)
  if [[ "$token_in_is_native" != "true" && -n "$token_in_address" && -n "$amount_in_wei" ]]; then

    # Check balance FIRST -- no point approving if you don't have the tokens
    log "Checking $token_in_symbol balance..."
    local balance_hex balance_dec
    balance_hex=$(cast call \
      --rpc-url "$rpc_url" \
      "$token_in_address" \
      "balanceOf(address)(uint256)" \
      "$sender" 2>/dev/null || echo "0")

    if [[ "$balance_hex" == 0x* ]]; then
      balance_dec=$(printf "%d" "$balance_hex" 2>/dev/null || echo "0")
    else
      balance_dec="${balance_hex%%[^0-9]*}"
      balance_dec="${balance_dec:-0}"
    fi

    if [[ "$balance_dec" =~ ^[0-9]+$ ]] && [[ "$amount_in_wei" =~ ^[0-9]+$ ]] && command -v bc &>/dev/null; then
      if (( $(echo "$balance_dec < $amount_in_wei" | bc -l) )); then
        json_output false "Zap failed (pre-flight): Insufficient $token_in_symbol balance. Have: $balance_dec wei, Need: $amount_in_wei wei. Top up your $token_in_symbol before zapping. No transaction was submitted."
        exit 1
      fi
    fi
    log "$token_in_symbol balance OK"

    # Check allowance AFTER balance is confirmed
    # NOTE: Approve the ZapRouter, NOT the Aggregator router
    log "Checking ERC-20 allowance for $token_in_symbol (spender: ZapRouter $router_address)..."
    local allowance_hex allowance_dec
    allowance_hex=$(cast call \
      --rpc-url "$rpc_url" \
      "$token_in_address" \
      "allowance(address,address)(uint256)" \
      "$sender" \
      "$router_address" 2>/dev/null || echo "0")

    if [[ "$allowance_hex" == 0x* ]]; then
      allowance_dec=$(printf "%d" "$allowance_hex" 2>/dev/null || echo "0")
    else
      allowance_dec="${allowance_hex%%[^0-9]*}"
      allowance_dec="${allowance_dec:-0}"
    fi

    log "Current allowance: $allowance_dec"
    log "Required amount: $amount_in_wei"

    if command -v bc &>/dev/null; then
      if [[ "$allowance_dec" =~ ^[0-9]+$ ]] && [[ "$amount_in_wei" =~ ^[0-9]+$ ]] && (( $(echo "$allowance_dec < $amount_in_wei" | bc -l) )); then
        json_output false "Zap failed (pre-flight): Insufficient allowance for $token_in_symbol to ZapRouter. Current: $allowance_dec, Required: $amount_in_wei. No transaction was submitted. Run: cast send --rpc-url $rpc_url [WALLET_FLAGS] $token_in_address 'approve(address,uint256)' $router_address $amount_in_wei"
        exit 1
      fi
    else
      if [[ ${#allowance_dec} -lt ${#amount_in_wei} ]] || \
         [[ ${#allowance_dec} -eq ${#amount_in_wei} && "$allowance_dec" < "$amount_in_wei" ]]; then
        json_output false "Zap failed (pre-flight): Insufficient allowance for $token_in_symbol to ZapRouter. Current: $allowance_dec, Required: $amount_in_wei. No transaction was submitted. Approve the ZapRouter first."
        exit 1
      fi
    fi

    log "Allowance OK"
  fi

  # ---------------------------------------------------------------------------
  # Step 4: Configure wallet
  # ---------------------------------------------------------------------------

  local wallet_flags=()
  case "$wallet_method" in
    keystore)
      if [[ ! -f "$PASSWORD_FILE" ]]; then
        json_output false "Zap failed (pre-flight): Password file not found: $PASSWORD_FILE. Create it or set KEYSTORE_PASSWORD_FILE. No transaction was submitted."
        exit 1
      fi
      # Check password file permissions
      local pw_perms
      if [[ "$(uname)" == "Darwin" ]]; then
        pw_perms=$(stat -f '%Lp' "$PASSWORD_FILE" 2>/dev/null || echo "unknown")
      else
        pw_perms=$(stat -c '%a' "$PASSWORD_FILE" 2>/dev/null || echo "unknown")
      fi
      if [[ "$pw_perms" != "600" && "$pw_perms" != "unknown" ]]; then
        json_output false "Zap failed (pre-flight): Password file $PASSWORD_FILE has insecure permissions ($pw_perms). Required: 600. Fix with: chmod 600 $PASSWORD_FILE. No transaction was submitted."
        exit 1
      fi
      # Validate keystore exists
      local keystore_dir="${HOME}/.foundry/keystores"
      if [[ ! -f "${keystore_dir}/${keystore_name}" ]]; then
        json_output false "Zap failed (pre-flight): Keystore '${keystore_name}' not found in ${keystore_dir}. List keystores with: cast wallet list. No transaction was submitted."
        exit 1
      fi
      wallet_flags=(--account "$keystore_name" --password-file "$PASSWORD_FILE")
      log "Using keystore: $keystore_name"
      ;;
    env)
      if [[ -z "${PRIVATE_KEY:-}" ]]; then
        json_output false "Zap failed (pre-flight): PRIVATE_KEY environment variable not set. No transaction was submitted."
        exit 1
      fi
      export ETH_PRIVATE_KEY="$PRIVATE_KEY"
      wallet_flags=()
      log "Using private key from env (via ETH_PRIVATE_KEY)"
      log "WARNING: env method is less secure than keystore. Private key is in process environment."
      ;;
    ledger)
      wallet_flags=(--ledger)
      log "Using Ledger (confirm on device)"
      ;;
    trezor)
      wallet_flags=(--trezor)
      log "Using Trezor (confirm on device)"
      ;;
    *)
      json_output false "Zap failed (pre-flight): Unknown wallet method '$wallet_method'. Use: keystore, env, ledger, trezor. No transaction was submitted."
      exit 1
      ;;
  esac

  # ---------------------------------------------------------------------------
  # Step 5: Execute transaction
  # ---------------------------------------------------------------------------

  local explorer
  explorer=$(get_explorer_url "$chain")

  log "Chain: $chain"
  log "ZapRouter: $to"
  log "Value: $value wei"
  log "Gas limit: $gas"
  log "RPC: $rpc_url"

  # Verify chain ID before broadcasting to prevent sending on wrong network
  local expected_chain_id actual_chain_id
  expected_chain_id=$(get_expected_chain_id "$chain")
  if [[ -n "$expected_chain_id" ]]; then
    actual_chain_id=$(cast chain-id --rpc-url "$rpc_url" 2>/dev/null || echo "")
    actual_chain_id="${actual_chain_id%%[^0-9]*}"
    if [[ -z "$actual_chain_id" ]]; then
      json_output false "Zap failed (pre-flight): Could not verify chain ID from RPC $rpc_url. The RPC may be down. No transaction was submitted."
      exit 1
    fi
    if [[ "$actual_chain_id" != "$expected_chain_id" ]]; then
      json_output false "Zap failed (pre-flight): Chain ID mismatch! RPC returned chain ID $actual_chain_id but expected $expected_chain_id for '$chain'. This could indicate a misconfigured or malicious RPC. No transaction was submitted."
      exit 1
    fi
    log "Chain ID verified: $actual_chain_id"
  else
    log "WARNING: No expected chain ID configured for '$chain' -- skipping chain ID verification"
  fi

  log "Executing transaction..."

  local tx_output
  local tx_hash
  local exit_code=0

  tx_output=$(FOUNDRY_DISABLE_NIGHTLY_WARNING=1 cast send \
    --rpc-url "$rpc_url" \
    "${wallet_flags[@]}" \
    --gas-limit "$gas" \
    --value "$value" \
    --timeout 120 \
    --json \
    "$to" \
    "$data" 2>&1) || exit_code=$?

  # Retry with fallback RPC on rate limit (429) or connection errors
  if [[ $exit_code -ne 0 ]] && echo "$tx_output" | grep -qiE '429|rate.limit|too many|connection refused'; then
    local fallback_rpc
    fallback_rpc=$(get_fallback_rpc_url "$chain")
    if [[ -n "$fallback_rpc" && "$fallback_rpc" != "$rpc_url" ]]; then
      log "Primary RPC failed (rate limited), retrying with fallback: $fallback_rpc"
      sleep 2
      exit_code=0
      tx_output=$(FOUNDRY_DISABLE_NIGHTLY_WARNING=1 cast send \
        --rpc-url "$fallback_rpc" \
        "${wallet_flags[@]}" \
        --gas-limit "$gas" \
        --value "$value" \
        --timeout 120 \
        --json \
        "$to" \
        "$data" 2>&1) || exit_code=$?
    fi
  fi

  if [[ $exit_code -ne 0 ]]; then
    # Sanitize output to prevent private key leakage in error messages
    local safe_output
    safe_output=$(echo "$tx_output" | sed -E \
      -e 's/--private-key [^ ]*/--private-key [REDACTED]/g' \
      -e 's/"private[Kk]ey"[[:space:]]*:[[:space:]]*"[^"]*"/"privateKey": "[REDACTED]"/g' \
      -e 's/ETH_PRIVATE_KEY=[^ ]*/ETH_PRIVATE_KEY=[REDACTED]/g' \
      -e 's/PRIVATE_KEY=[^ ]*/PRIVATE_KEY=[REDACTED]/g' \
      -e 's/0x[a-fA-F0-9]{64}/[REDACTED_HEX]/g')
    json_output false "Transaction was broadcast but failed on-chain: $safe_output"
    exit 1
  fi

  # ---------------------------------------------------------------------------
  # Step 6: Parse result and output
  # ---------------------------------------------------------------------------

  tx_hash=$(echo "$tx_output" | jq -r '.transactionHash // empty')

  if [[ -z "$tx_hash" ]]; then
    # Try parsing as plain hash (older cast versions)
    tx_hash=$(echo "$tx_output" | grep -oE '0x[a-fA-F0-9]{64}' | head -1 || true)
  fi

  if [[ -z "$tx_hash" ]]; then
    # Apply same redaction as the error path above to prevent key leakage
    local safe_tx_output
    safe_tx_output=$(echo "$tx_output" | sed -E \
      -e 's/--private-key [^ ]*/--private-key [REDACTED]/g' \
      -e 's/"private[Kk]ey"[[:space:]]*:[[:space:]]*"[^"]*"/"privateKey": "[REDACTED]"/g' \
      -e 's/ETH_PRIVATE_KEY=[^ ]*/ETH_PRIVATE_KEY=[REDACTED]/g' \
      -e 's/PRIVATE_KEY=[^ ]*/PRIVATE_KEY=[REDACTED]/g' \
      -e 's/0x[a-fA-F0-9]{64}/[REDACTED_HEX]/g')
    json_output false "Transaction was broadcast but could not parse transaction hash from output: $safe_tx_output"
    exit 1
  fi

  local block_number gas_used status
  block_number=$(echo "$tx_output" | jq -r '.blockNumber // "pending"')
  gas_used=$(echo "$tx_output" | jq -r '.gasUsed // "unknown"')
  status=$(echo "$tx_output" | jq -r '.status // "1"')

  log "Transaction submitted!"
  log "Hash: $tx_hash"
  log "Explorer: $explorer/tx/$tx_hash"

  # Output JSON result
  jq -n \
    --arg chain "$chain" \
    --arg txHash "$tx_hash" \
    --arg blockNumber "$block_number" \
    --arg gasUsed "$gas_used" \
    --arg status "$status" \
    --arg explorer "$explorer/tx/$tx_hash" \
    --arg sender "$sender" \
    --arg router "$to" \
    --arg value "$value" \
    --arg tokenInSymbol "$token_in_symbol" \
    --arg tokenInAmount "$amount_in" \
    --arg poolAddress "$zap_pool_address" \
    --arg dex "$zap_dex" \
    --arg tickLower "$tick_lower" \
    --arg tickUpper "$tick_upper" \
    --arg slippageBps "$slippage_bps" \
    --arg walletMethod "$wallet_method" \
    '{
      "ok": true,
      "chain": $chain,
      "txHash": $txHash,
      "blockNumber": $blockNumber,
      "gasUsed": $gasUsed,
      "status": $status,
      "explorerUrl": $explorer,
      "zap": {
        "tokenIn": {"symbol": $tokenInSymbol, "amount": $tokenInAmount},
        "poolAddress": $poolAddress,
        "dex": $dex,
        "tickLower": $tickLower,
        "tickUpper": $tickUpper,
        "slippageBps": $slippageBps
      },
      "tx": {
        "sender": $sender,
        "router": $router,
        "value": $value
      },
      "walletMethod": $walletMethod
    }'
}

main "$@"
