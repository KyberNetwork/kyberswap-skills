#!/usr/bin/env bash
# fast-zap.sh — End-to-end KyberSwap zap-in: resolve token → get zap route → build tx
#
# Usage: fast-zap.sh <tokenIn> <amountIn> <poolAddress> <dex> <tickLower> <tickUpper> <chain> <sender> [slippage_bps]
# Output: JSON to stdout, progress to stderr
# Dependencies: curl, jq
# Docs: https://docs.kyberswap.com/kyberswap-solutions/kyberswap-zap-as-a-service/zap-api-specification

set -euo pipefail

# -- Configuration -----------------------------------------------------------

ZAP_API="https://zap-api.kyberswap.com"
TOKEN_API="https://token-api.kyberswap.com/api/v1/public/tokens"
CLIENT_ID="ai-agent-skills"
NATIVE="0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE"
ZAP_ROUTER="0x0e97c887b61ccd952a53578b04763e7134429e05"

# -- Helpers ------------------------------------------------------------------

log() { echo ":: $*" >&2; }

die() {
  local msg="$*"
  jq -nc --arg error "$msg" '{ok: false, error: $error}'
  exit 1
}

# URL-encode a string (requires jq)
urlencode() { printf '%s' "$1" | jq -sRr @uri; }

usage() {
  cat >&2 <<'EOF'
Usage: fast-zap.sh <tokenIn> <amountIn> <poolAddress> <dex> <tickLower> <tickUpper> <chain> <sender> [slippage_bps]

  tokenIn       Input token symbol (e.g. ETH, USDC) or address:decimals (e.g. 0xA0b8...:6)
  amountIn      Human-readable amount to zap (e.g. 1, 0.5, 100)
  poolAddress   Pool contract address (0x...)
  dex           DEX identifier (e.g. uniswapv3, pancakev3)
  tickLower     Lower tick of the position
  tickUpper     Upper tick of the position
  chain         Chain slug (e.g. ethereum, arbitrum, polygon)
  sender        Sender wallet address (0x...)
  slippage_bps  Slippage tolerance in basis points (default: 100)
EOF
  exit 1
}

# Convert human-readable amount to wei (plain integer string, no decimals/sci notation)
to_wei() {
  local amount="$1" decimals="$2"
  local int_part dec_part dec_len pad_len result

  # Validate: must be a non-negative number (digits with optional single dot)
  if ! [[ "$amount" =~ ^[0-9]*\.?[0-9]+$ ]]; then
    die "Invalid amount for to_wei: '$amount'. Must be a non-negative number."
  fi

  if [[ "$amount" == *.* ]]; then
    int_part="${amount%%.*}"
    dec_part="${amount#*.}"
  else
    int_part="$amount"
    dec_part=""
  fi

  [[ -z "$int_part" ]] && int_part="0"
  dec_len=${#dec_part}

  if (( dec_len >= decimals )); then
    # Truncate excess decimal places
    result="${int_part}${dec_part:0:$decimals}"
  else
    # Pad with trailing zeros
    pad_len=$((decimals - dec_len))
    result="${int_part}${dec_part}$(printf '%0*d' "$pad_len" 0)"
  fi

  # Strip leading zeros, keep at least "0"
  result="$(echo "$result" | sed 's/^0*//')"
  echo "${result:-0}"
}

# Convert wei to human-readable amount
from_wei() {
  local wei="$1" decimals="$2"
  local len int_part dec_part

  [[ -z "$wei" || "$wei" == "0" ]] && echo "0" && return

  # Strip leading zeros from input
  wei="$(echo "$wei" | sed 's/^0*//')"
  [[ -z "$wei" ]] && echo "0" && return

  len=${#wei}

  if (( decimals == 0 )); then
    echo "$wei"
  elif (( len <= decimals )); then
    local pad=$((decimals - len))
    if (( pad > 0 )); then
      dec_part="$(printf '%0*d' "$pad" 0)${wei}"
    else
      dec_part="$wei"
    fi
    dec_part="$(echo "$dec_part" | sed 's/0*$//')"
    [[ -z "$dec_part" ]] && echo "0" && return
    echo "0.${dec_part}"
  else
    int_part="${wei:0:$((len - decimals))}"
    dec_part="${wei:$((len - decimals))}"
    dec_part="$(echo "$dec_part" | sed 's/0*$//')"
    if [[ -z "$dec_part" ]]; then
      echo "$int_part"
    else
      echo "${int_part}.${dec_part}"
    fi
  fi
}

# Normalize DEX identifier to the API's DEX_* enum format
# Accepts shorthand (uniswapv3, pancakev3) or canonical (DEX_UNISWAPV3)
normalize_dex() {
  local dex_lower
  dex_lower=$(echo "$1" | tr '[:upper:]' '[:lower:]')
  case "$dex_lower" in
    uniswapv3|uniswap-v3|uniswap_v3)              echo "DEX_UNISWAPV3" ;;
    uniswapv2|uniswap-v2|uniswap_v2)              echo "DEX_UNISWAPV2" ;;
    uniswapv4|uniswap-v4|uniswap_v4)              echo "DEX_UNISWAP_V4" ;;
    pancakeswapv3|pancakev3|pancake-v3)            echo "DEX_PANCAKESWAPV3" ;;
    pancakeswapv2|pancakev2|pancake-v2)            echo "DEX_PANCAKESWAPV2" ;;
    sushiswapv3|sushiv3|sushi-v3)                  echo "DEX_SUSHISWAPV3" ;;
    sushiswapv2|sushiv2|sushi-v2)                  echo "DEX_SUSHISWAPV2" ;;
    camelotv3|camelot-v3)                          echo "DEX_CAMELOTV3" ;;
    dex_*)                                         echo "$(echo "$1" | tr '[:lower:]' '[:upper:]')" ;;
    *)                                             echo "$1" ;;
  esac
}

# Get chain ID from slug (ZaaS-supported chains only: 13 chains)
get_chain_id() {
  case "$1" in
    ethereum)   echo 1 ;;
    bsc)        echo 56 ;;
    arbitrum)   echo 42161 ;;
    polygon)    echo 137 ;;
    optimism)   echo 10 ;;
    avalanche)  echo 43114 ;;
    base)       echo 8453 ;;
    linea)      echo 59144 ;;
    sonic)      echo 146 ;;
    berachain)  echo 80094 ;;
    ronin)      echo 2020 ;;
    scroll)     echo 534352 ;;
    zksync)     echo 324 ;;
    *) return 1 ;;
  esac
}

# Look up token in built-in registry. Outputs: "address decimals"
lookup_token() {
  local chain="$1" sym
  sym=$(echo "$2" | tr '[:lower:]' '[:upper:]')

  case "$chain:$sym" in
    # -- Native tokens --
    ethereum:ETH|arbitrum:ETH|optimism:ETH|base:ETH|linea:ETH)
      echo "$NATIVE 18" ;;
    bsc:BNB)                    echo "$NATIVE 18" ;;
    polygon:POL|polygon:MATIC)  echo "$NATIVE 18" ;;
    avalanche:AVAX)             echo "$NATIVE 18" ;;
    sonic:S)                    echo "$NATIVE 18" ;;
    berachain:BERA)             echo "$NATIVE 18" ;;
    ronin:RON)                  echo "$NATIVE 18" ;;

    # -- Stablecoins: Ethereum --
    ethereum:USDC) echo "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48 6" ;;
    ethereum:USDT) echo "0xdAC17F958D2ee523a2206206994597C13D831ec7 6" ;;

    # -- Stablecoins: BSC --
    bsc:USDC)      echo "0x8AC76a51cc950d9822D68b83fE1Ad97B32Cd580d 18" ;;
    bsc:USDT)      echo "0x55d398326f99059fF775485246999027B3197955 18" ;;

    # -- Stablecoins: Arbitrum --
    arbitrum:USDC) echo "0xaf88d065e77c8cC2239327C5EDb3A432268e5831 6" ;;
    arbitrum:USDT) echo "0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9 6" ;;

    # -- Stablecoins: Polygon --
    polygon:USDC)  echo "0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359 6" ;;
    polygon:USDT)  echo "0xc2132D05D31c914a87C6611C10748AEb04B58e8F 6" ;;

    # -- Stablecoins: Optimism --
    optimism:USDC) echo "0x0b2C639c533813f4Aa9D7837CAf62653d097Ff85 6" ;;
    optimism:USDT) echo "0x94b008aA00579c1307B0EF2c499aD98a8ce58e58 6" ;;

    # -- Stablecoins: Base --
    base:USDC)     echo "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913 6" ;;

    # -- Stablecoins: Avalanche --
    avalanche:USDC) echo "0xB97EF9Ef8734C71904D8002F8b6Bc66Dd9c48a6E 6" ;;
    avalanche:USDT) echo "0x9702230A8Ea53601f5cD2dc00fDBc13d4dF4A8c7 6" ;;

    # -- Stablecoins: Linea --
    linea:USDC)    echo "0x176211869cA2b568f2A7D4EE941E073a821EE1ff 6" ;;
    linea:USDT)    echo "0xA219439258ca9da29E9Cc4cE5596924745e12B93 6" ;;

    # -- Stablecoins: Sonic --
    sonic:USDC.E|sonic:USDC) echo "0x29219dd400f2Bf60E5a23d13Be72B486D4038894 6" ;;

    *) return 1 ;;
  esac
}

# Resolve token via KyberSwap Token API (fallback). Outputs: "address decimals"
resolve_token_api() {
  local chain_id="$1" symbol="$2"
  local resp match

  log "Looking up $symbol via Token API (chain $chain_id)..."

  local encoded_symbol
  encoded_symbol=$(urlencode "$symbol")

  # Try symbol search first (exact match, most reliable)
  resp=$(curl -s --connect-timeout 10 --max-time 30 "${TOKEN_API}?chainIds=${chain_id}&symbol=${encoded_symbol}&isWhitelisted=true" \
    -H "X-Client-Id: ${CLIENT_ID}" 2>/dev/null) || true

  if [[ -n "$resp" ]]; then
    match=$(echo "$resp" | jq -r --arg s "$symbol" \
      '[.data.tokens[] | select(.symbol | ascii_downcase == ($s | ascii_downcase))] | sort_by(-(.marketCap // 0)) | first // empty | "\(.address) \(.decimals)"' 2>/dev/null) || true

    if [[ -n "$match" && "$match" != " " ]]; then
      echo "$match"
      return 0
    fi
  fi

  # Fall back to unfiltered symbol search (for non-whitelisted tokens)
  resp=$(curl -s --connect-timeout 10 --max-time 30 "${TOKEN_API}?chainIds=${chain_id}&symbol=${encoded_symbol}" \
    -H "X-Client-Id: ${CLIENT_ID}" 2>/dev/null) || true

  if [[ -n "$resp" ]]; then
    match=$(echo "$resp" | jq -r --arg s "$symbol" \
      '[.data.tokens[] | select(.symbol | ascii_downcase == ($s | ascii_downcase)) | select(.isVerified == true or (.marketCap // 0) > 0)] | sort_by(-(.marketCap // 0)) | first // empty | "\(.address) \(.decimals)"' 2>/dev/null) || true

    if [[ -n "$match" && "$match" != " " ]]; then
      echo "$match"
      return 0
    fi
  fi

  # Fall back to name search (substring match on token name)
  resp=$(curl -s --connect-timeout 10 --max-time 30 "${TOKEN_API}?chainIds=${chain_id}&name=${encoded_symbol}&isWhitelisted=true" \
    -H "X-Client-Id: ${CLIENT_ID}" 2>/dev/null) || true

  if [[ -n "$resp" ]]; then
    match=$(echo "$resp" | jq -r --arg s "$symbol" \
      '[.data.tokens[] | select(.symbol | ascii_downcase == ($s | ascii_downcase))] | sort_by(-(.marketCap // 0)) | first // empty | "\(.address) \(.decimals)"' 2>/dev/null) || true

    if [[ -n "$match" && "$match" != " " ]]; then
      echo "$match"
      return 0
    fi
  fi

  # Fall back to browsing by market cap
  local page
  for page in 1 2 3; do
    resp=$(curl -s --connect-timeout 10 --max-time 30 "${TOKEN_API}?chainIds=${chain_id}&page=${page}&pageSize=100" \
      -H "X-Client-Id: ${CLIENT_ID}" 2>/dev/null) || continue

    match=$(echo "$resp" | jq -r --arg s "$symbol" \
      '[.data.tokens[] | select(.symbol | ascii_downcase == ($s | ascii_downcase)) | select(.isVerified == true or (.marketCap // 0) > 0)] | sort_by(-(.marketCap // 0)) | first // empty | "\(.address) \(.decimals)"' 2>/dev/null) || continue

    if [[ -n "$match" && "$match" != " " ]]; then
      echo "$match"
      return 0
    fi
  done

  return 1
}

# Resolve token: built-in registry first, then Token API fallback
resolve_token() {
  local chain="$1" symbol="$2" chain_id="$3"
  local result

  if result=$(lookup_token "$chain" "$symbol"); then
    echo "$result"
    return 0
  fi

  if result=$(resolve_token_api "$chain_id" "$symbol"); then
    echo "$result"
    return 0
  fi

  return 1
}

# -- Main ---------------------------------------------------------------------

main() {
  # Check dependencies
  for cmd in curl jq; do
    command -v "$cmd" &>/dev/null || die "Required command not found: ${cmd}. Install it and try again."
  done

  # Parse arguments
  case "${1:-}" in -h|--help) usage ;; esac
  [[ $# -lt 8 ]] && usage

  local token_in_sym="$1"
  local amount="$2"
  local pool_address="$3"
  local dex="$4"
  local tick_lower="$5"
  local tick_upper="$6"
  local chain="$7"
  local sender="$8"
  local slippage="${9:-100}"

  # Normalize DEX identifier (accept shorthand like uniswapv3 -> DEX_UNISWAPV3)
  dex=$(normalize_dex "$dex")
  log "DEX: $dex"

  # Validate token input: either a symbol (e.g. ETH, USDC) or pre-resolved address:decimals (e.g. 0xA0b8...:6)
  if [[ "$token_in_sym" =~ ^0x[a-fA-F0-9]{40}:[0-9]+$ ]]; then
    :  # Pre-resolved address:decimals -- validated by regex
  elif [[ "$token_in_sym" =~ ^[a-zA-Z0-9.]+$ ]]; then
    :  # Symbol -- validated by regex
  else
    die "Invalid token input: $token_in_sym. Must be a symbol (e.g. ETH) or address:decimals (e.g. 0xA0b8...:6)"
  fi

  # Validate amount
  if ! [[ "$amount" =~ ^[0-9]*\.?[0-9]+$ ]]; then
    die "Invalid amount: '$amount'. Must be a non-negative number."
  fi

  # Validate pool address (20-byte address) or pool ID (32-byte, for Uniswap V4)
  [[ "$pool_address" =~ ^0x[a-fA-F0-9]{40}$ ]] || [[ "$pool_address" =~ ^0x[a-fA-F0-9]{64}$ ]] || die "Invalid pool address/ID: $pool_address. Must be 0x + 40 hex chars (address) or 0x + 64 hex chars (V4 pool ID)."

  # Validate dex identifier
  [[ "$dex" =~ ^[a-zA-Z0-9_-]+$ ]] || die "Invalid dex identifier: $dex. Must contain only alphanumeric characters, hyphens, and underscores."

  # Validate tick values (integers, may be negative)
  [[ "$tick_lower" =~ ^-?[0-9]+$ ]] || die "Invalid tickLower: $tick_lower. Must be an integer."
  [[ "$tick_upper" =~ ^-?[0-9]+$ ]] || die "Invalid tickUpper: $tick_upper. Must be an integer."

  # Validate sender address
  [[ "$sender" =~ ^0x[a-fA-F0-9]{40}$ ]] || die "Invalid sender address: $sender"
  # Reject zero address and native token sentinel as sender
  local sender_lower
  sender_lower=$(echo "$sender" | tr '[:upper:]' '[:lower:]')
  if [[ "$sender_lower" == "0x0000000000000000000000000000000000000000" ]]; then
    die "Cannot use zero address as sender. Please provide your actual wallet address."
  fi
  if [[ "$sender_lower" == "0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee" ]]; then
    die "Cannot use the native token sentinel address as sender. Please provide your actual wallet address."
  fi

  # Validate slippage
  if ! [[ "$slippage" =~ ^[0-9]+$ ]] || (( slippage > 2000 )); then
    die "Slippage must be 0-2000 basis points (0-20%). Got: ${slippage}. If you intentionally need higher slippage, this is likely a mistake."
  fi

  local slippage_bps=$slippage
  if (( slippage_bps > 500 )); then
    if command -v bc &>/dev/null; then
      log "WARNING: High slippage of ${slippage_bps} bps ($(echo "scale=1; $slippage_bps / 100" | bc)%). Most zaps use 50-300 bps."
    else
      log "WARNING: High slippage of ${slippage_bps} bps. Most zaps use 50-300 bps."
    fi
  fi

  # Validate chain (ZaaS supports 13 chains)
  local chain_id
  chain_id=$(get_chain_id "$chain") || \
    die "Unsupported chain for ZaaS: ${chain}. Supported: ethereum, bsc, arbitrum, polygon, optimism, avalanche, base, linea, sonic, berachain, ronin, scroll, zksync"

  # -- Step 1: Resolve token ---------------------------------------------------

  local tin_addr tin_dec

  # If tokenIn is pre-resolved address:decimals, split and skip resolution
  if [[ "$token_in_sym" =~ ^0x[a-fA-F0-9]{40}:[0-9]+$ ]]; then
    tin_addr="${token_in_sym%%:*}"
    tin_dec="${token_in_sym##*:}"
    log "Using pre-resolved tokenIn: ${tin_addr} (${tin_dec} decimals)"
  else
    log "Resolving ${token_in_sym} on ${chain}..."
    local tin_info
    tin_info=$(resolve_token "$chain" "$token_in_sym" "$chain_id") || \
      die "Token '${token_in_sym}' not found on ${chain}. Verify the symbol or provide a contract address."
    tin_addr=$(echo "$tin_info" | awk '{print $1}')
    tin_dec=$(echo "$tin_info" | awk '{print $2}')
    [[ "$tin_addr" =~ ^0x[a-fA-F0-9]{40}$ ]] || die "Invalid token address for $token_in_sym: $tin_addr"
    log "  ${token_in_sym} = ${tin_addr} (${tin_dec} decimals)"
  fi

  local tin_is_native="false"
  [[ "$tin_addr" == "$NATIVE" ]] && tin_is_native="true"

  # -- Step 1b: Honeypot / FOT check ------------------------------------------

  check_honeypot() {
    local addr="$1" symbol="$2" is_native="$3"
    [[ "$is_native" == "true" ]] && return 0

    # Validate address format before using in API URL
    [[ "$addr" =~ ^0x[a-fA-F0-9]{40}$ ]] || return 1

    local resp hp fot tax
    resp=$(curl -s --connect-timeout 10 --max-time 30 "${TOKEN_API}/honeypot-fot-info?chainId=${chain_id}&address=${addr}" \
      -H "X-Client-Id: ${CLIENT_ID}" 2>/dev/null) || { log "WARNING: Token safety API unreachable for ${symbol}. Proceeding without honeypot/FOT check."; return 0; }

    hp=$(echo "$resp" | jq -r '.data.isHoneypot // false' 2>/dev/null) || { log "WARNING: Could not parse safety data for ${symbol}."; return 0; }
    fot=$(echo "$resp" | jq -r '.data.isFOT // false' 2>/dev/null) || { log "WARNING: Could not parse FOT data for ${symbol}."; return 0; }
    tax=$(echo "$resp" | jq -r '.data.tax // 0' 2>/dev/null) || return 0

    if [[ "$hp" == "true" ]]; then
      die "HONEYPOT DETECTED: ${symbol} (${addr}) is flagged as a honeypot. You will not be able to sell this token. Zap aborted."
    fi

    if [[ "$fot" == "true" ]]; then
      log "WARNING: ${symbol} has a fee-on-transfer (tax: ${tax}%). The actual received amount will be less than expected."
    fi
  }

  log "Checking token safety..."
  check_honeypot "$tin_addr" "$token_in_sym" "$tin_is_native"

  # -- Step 2: Convert amount to wei ------------------------------------------

  local amount_wei
  amount_wei=$(to_wei "$amount" "$tin_dec")
  log "Amount: ${amount} ${token_in_sym} = ${amount_wei} wei"

  # -- Step 3: GET zap route ---------------------------------------------------

  fetch_zap_route() {
    log "Fetching zap route..."
    local encoded_sender
    encoded_sender=$(urlencode "$sender")

    local url="${ZAP_API}/${chain}/api/v1/in/route?dex=${dex}&pool.id=${pool_address}&position.tickLower=${tick_lower}&position.tickUpper=${tick_upper}&tokensIn=${tin_addr}&amountsIn=${amount_wei}&slippage=${slippage_bps}&sender=${encoded_sender}"

    local resp code
    resp=$(curl -s --connect-timeout 10 --max-time 30 "$url" \
      -H "X-Client-Id: ${CLIENT_ID}" 2>/dev/null) || \
      die "Network error: failed to reach KyberSwap ZaaS route API."

    code=$(echo "$resp" | jq -r '.code // empty' 2>/dev/null)

    # Success: code is "0", or code is absent/empty and .data exists
    if [[ -n "$code" && "$code" != "0" ]]; then
      local msg
      msg=$(echo "$resp" | jq -r '.message // "Unknown error"' 2>/dev/null)
      die "ZaaS route error (${code}): ${msg}"
    fi

    local route_data
    route_data=$(echo "$resp" | jq -c '.data' 2>/dev/null)
    if [[ -z "$route_data" || "$route_data" == "null" ]]; then
      die "ZaaS route API returned no route data."
    fi

    echo "$resp"
  }

  local route_resp
  local route_exit=0
  route_resp=$(fetch_zap_route) || route_exit=$?
  if [[ $route_exit -ne 0 ]]; then
    # die() was called inside $(), re-emit its JSON to our stdout
    echo "$route_resp"
    exit 1
  fi

  # Extract route data — the build API expects only .data.route, not the full .data object
  local route_data router_address pool_details position_details
  local amount_in_usd zap_gas zap_gas_usd

  route_data=$(echo "$route_resp" | jq -c '.data.route // .data')
  router_address=$(echo "$route_resp" | jq -r '.data.routerAddress // empty')

  # Verify router address matches expected ZapRouter
  local expected_router="${EXPECTED_ZAP_ROUTER_OVERRIDE:-$ZAP_ROUTER}"
  if [[ -n "${EXPECTED_ZAP_ROUTER_OVERRIDE:-}" ]]; then
    if ! [[ "$expected_router" =~ ^0x[a-fA-F0-9]{40}$ ]]; then
      die "Invalid EXPECTED_ZAP_ROUTER_OVERRIDE format. Must be a valid Ethereum address (0x + 40 hex chars)."
    fi
    log "WARNING: Using custom ZapRouter override: $expected_router"
  fi
  local router_lower expected_lower
  router_lower=$(echo "$router_address" | tr '[:upper:]' '[:lower:]')
  expected_lower=$(echo "$expected_router" | tr '[:upper:]' '[:lower:]')
  if [[ "$router_lower" != "$expected_lower" ]]; then
    die "Unexpected ZapRouter address from API: $router_address. Expected: $expected_router. This could indicate a compromised API response."
  fi

  amount_in_usd=$(echo "$route_resp" | jq -r '.data.zapDetails.initialAmountUsd // "0"' 2>/dev/null)
  zap_gas=$(echo "$route_resp" | jq -r '.data.gas // "500000"' 2>/dev/null)
  zap_gas_usd=$(echo "$route_resp" | jq -r '.data.gasUsd // "0"' 2>/dev/null)
  pool_details=$(echo "$route_resp" | jq -c '.data.poolDetails // {}' 2>/dev/null)
  position_details=$(echo "$route_resp" | jq -c '.data.positionDetails // {}' 2>/dev/null)

  log "Zap route found for pool ${pool_address} on ${dex}"

  # -- Step 3b: Dust amount check ----------------------------------------------
  # Reject zaps where the value is so small that gas fees dwarf the trade.

  if command -v bc &>/dev/null && [[ "$amount_in_usd" =~ ^[0-9]*\.?[0-9]+$ ]] && [[ "$zap_gas_usd" =~ ^[0-9]*\.?[0-9]+$ ]]; then
    # Check 1: Zap value < $0.10
    if (( $(echo "$amount_in_usd < 0.10" | bc -l 2>/dev/null || echo 0) )); then
      die "Dust amount detected: zap value is ~\$${amount_in_usd} (< \$0.10). Gas fees (~\$${zap_gas_usd}) would far exceed the zap value. Use a larger amount."
    fi

    # Check 2: Gas cost > zap value
    if (( $(echo "$zap_gas_usd > $amount_in_usd" | bc -l 2>/dev/null || echo 0) )); then
      die "Uneconomical zap: gas cost (~\$${zap_gas_usd}) exceeds zap value (~\$${amount_in_usd}). Use a larger amount to make this trade worthwhile."
    fi
  fi

  # -- Step 4: POST zap build --------------------------------------------------

  build_zap_tx() {
    local rd="$1"
    log "Building zap transaction..."

    local deadline
    deadline=$(($(date +%s) + 1200))

    local body
    body=$(jq -nc \
      --argjson route "$rd" \
      --arg sender "$sender" \
      --argjson deadline "$deadline" \
      '{
        route: $route,
        sender: $sender,
        deadline: $deadline,
        source: "ai-agent-skills"
      }')

    local resp
    resp=$(curl -s --connect-timeout 10 --max-time 30 -X POST "${ZAP_API}/${chain}/api/v1/in/route/build" \
      -H "Content-Type: application/json" \
      -H "X-Client-Id: ${CLIENT_ID}" \
      -d "$body" 2>/dev/null) || \
      die "Network error: failed to reach KyberSwap ZaaS build API."

    echo "$resp"
  }

  local build_resp build_code
  local build_exit=0
  build_resp=$(build_zap_tx "$route_data") || build_exit=$?
  if [[ $build_exit -ne 0 ]]; then
    echo "$build_resp"
    exit 1
  fi
  build_code=$(echo "$build_resp" | jq -r '.code // empty' 2>/dev/null)

  # Retry once on stale route
  if [[ -n "$build_code" && "$build_code" != "0" ]]; then
    local build_msg
    build_msg=$(echo "$build_resp" | jq -r '.message // "Unknown error"' 2>/dev/null)

    # If it looks like a stale route, retry
    if echo "$build_msg" | grep -qi "expired\|stale\|outdated\|not found"; then
      log "Route may be stale, re-fetching..."
      route_exit=0
      route_resp=$(fetch_zap_route) || route_exit=$?
      if [[ $route_exit -ne 0 ]]; then
        echo "$route_resp"
        exit 1
      fi
      route_data=$(echo "$route_resp" | jq -c '.data.route // .data')
      router_address=$(echo "$route_resp" | jq -r '.data.routerAddress // empty')
      # Re-validate router address on retry path
      router_lower=$(echo "$router_address" | tr '[:upper:]' '[:lower:]')
      if [[ "$router_lower" != "$expected_lower" ]]; then
        die "Unexpected ZapRouter address from API on retry: $router_address. Expected: $expected_router."
      fi
      amount_in_usd=$(echo "$route_resp" | jq -r '.data.zapDetails.initialAmountUsd // "0"' 2>/dev/null)
      zap_gas=$(echo "$route_resp" | jq -r '.data.gas // "500000"' 2>/dev/null)
      zap_gas_usd=$(echo "$route_resp" | jq -r '.data.gasUsd // "0"' 2>/dev/null)
      pool_details=$(echo "$route_resp" | jq -c '.data.poolDetails // {}' 2>/dev/null)
      position_details=$(echo "$route_resp" | jq -c '.data.positionDetails // {}' 2>/dev/null)

      build_exit=0
      build_resp=$(build_zap_tx "$route_data") || build_exit=$?
      if [[ $build_exit -ne 0 ]]; then
        echo "$build_resp"
        exit 1
      fi
      build_code=$(echo "$build_resp" | jq -r '.code // empty' 2>/dev/null)
    fi
  fi

  if [[ -n "$build_code" && "$build_code" != "0" ]]; then
    local build_msg
    build_msg=$(echo "$build_resp" | jq -r '.message // "Unknown error"' 2>/dev/null)
    die "ZaaS build error (${build_code}): ${build_msg}"
  fi

  # Extract build data
  local tx_data tx_value tx_gas

  tx_data=$(echo "$build_resp" | jq -r '.data.callData // empty')
  tx_value=$(echo "$build_resp" | jq -r '.data.value // .data.transactionValue // "0"')
  tx_gas=$(echo "$build_resp" | jq -r '.data.gas // empty')

  # Fallback: some API versions use .data.data instead of .data.callData
  if [[ -z "$tx_data" || "$tx_data" == "null" ]]; then
    tx_data=$(echo "$build_resp" | jq -r '.data.data // empty')
  fi

  if [[ -z "$tx_data" || "$tx_data" == "null" ]]; then
    die "ZaaS build API returned no transaction calldata."
  fi

  if [[ -z "$tx_gas" || "$tx_gas" == "null" ]]; then
    tx_gas="$zap_gas"
  fi

  log "Zap transaction built successfully"

  # -- Step 5: Output JSON -----------------------------------------------------

  jq -n \
    --argjson ok true \
    --arg chain "$chain" \
    --arg sender "$sender" \
    --argjson slippageBps "$slippage" \
    --arg tokenInSymbol "$token_in_sym" \
    --arg tokenInAddress "$tin_addr" \
    --argjson tokenInDecimals "$tin_dec" \
    --argjson tokenInIsNative "$tin_is_native" \
    --arg amountIn "$amount" \
    --arg amountInWei "$amount_wei" \
    --arg amountInUsd "$amount_in_usd" \
    --arg poolAddress "$pool_address" \
    --arg dex "$dex" \
    --arg tickLower "$tick_lower" \
    --arg tickUpper "$tick_upper" \
    --arg zapRouterAddress "$router_address" \
    --arg zapGas "$zap_gas" \
    --arg zapGasUsd "$zap_gas_usd" \
    --argjson poolDetails "$pool_details" \
    --argjson positionDetails "$position_details" \
    --arg txTo "$router_address" \
    --arg txData "$tx_data" \
    --arg txValue "$tx_value" \
    --arg txGas "$tx_gas" \
    '{
      ok: $ok,
      chain: $chain,
      sender: $sender,
      slippageBps: $slippageBps,
      tokenIn: {
        symbol: $tokenInSymbol,
        address: $tokenInAddress,
        decimals: $tokenInDecimals,
        isNative: $tokenInIsNative
      },
      zap: {
        amountIn: $amountIn,
        amountInWei: $amountInWei,
        amountInUsd: $amountInUsd,
        poolAddress: $poolAddress,
        dex: $dex,
        tickLower: $tickLower,
        tickUpper: $tickUpper,
        zapRouterAddress: $zapRouterAddress,
        gas: $zapGas,
        gasUsd: $zapGasUsd,
        poolDetails: $poolDetails,
        positionDetails: $positionDetails
      },
      tx: {
        to: $txTo,
        data: $txData,
        value: $txValue,
        gas: $txGas
      }
    }'
}

main "$@"
