#!/usr/bin/env bash
# test-fast-swap.sh — Automated tests for the fast-swap shell script
#
# Tests are split into two groups:
#   1. Unit tests   — test to_wei/from_wei math, no network needed
#   2. Live tests   — hit KyberSwap APIs with real requests
#
# Usage:
#   bash tests/test-fast-swap.sh              # run all tests
#   bash tests/test-fast-swap.sh unit         # unit tests only (offline)
#   bash tests/test-fast-swap.sh live         # live API tests only
#
# Exit code: 0 if all pass, 1 if any fail

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
FAST_SWAP="$REPO_ROOT/skills/swap-execute-fast/scripts/fast-swap.sh"

# Test sender — a well-known address (vitalik.eth); script only builds calldata, never signs
TEST_SENDER="0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045"

PASS=0
FAIL=0
SKIP=0

# ── Helpers ──────────────────────────────────────────────────────────────────

green()  { printf '\033[32m%s\033[0m' "$*"; }
red()    { printf '\033[31m%s\033[0m' "$*"; }
yellow() { printf '\033[33m%s\033[0m' "$*"; }

pass() { ((PASS++)); echo "  $(green PASS)  $1"; }
fail() { ((FAIL++)); echo "  $(red FAIL)  $1"; [[ -n "${2:-}" ]] && echo "        $2"; }
skip() { ((SKIP++)); echo "  $(yellow SKIP)  $1"; }

section() { echo; echo "── $1 ──"; }

# Source the script functions for unit tests (without running main)
# Extracts functions to a temp file and sources it (avoids eval on untrusted input)
source_functions() {
  local tmpfile
  tmpfile=$(mktemp)
  trap "rm -f '$tmpfile'" RETURN
  sed -n '/^to_wei()/,/^}/p' "$FAST_SWAP" > "$tmpfile"
  sed -n '/^from_wei()/,/^}/p' "$FAST_SWAP" >> "$tmpfile"
  sed -n '/^is_positive_uint()/,/^}/p' "$FAST_SWAP" >> "$tmpfile"
  source "$tmpfile"
}

# ── Unit Tests: to_wei ──────────────────────────────────────────────────────

test_to_wei() {
  section "to_wei conversion"

  source_functions

  local cases=(
    # "input decimals expected"
    "1 18 1000000000000000000"
    "0.5 18 500000000000000000"
    "100 6 100000000"
    "0.5 8 50000000"
    "1.5 6 1500000"
    "0 18 0"
    "0.001 18 1000000000000000"
    "1000 18 1000000000000000000000"
    "0.000001 6 1"
    "123.456789 6 123456789"
    "1 0 1"
    "999 0 999"
  )

  for c in "${cases[@]}"; do
    local input decimals expected
    read -r input decimals expected <<< "$c"
    local got
    got=$(to_wei "$input" "$decimals")
    if [[ "$got" == "$expected" ]]; then
      pass "to_wei($input, $decimals) = $expected"
    else
      fail "to_wei($input, $decimals) expected=$expected got=$got"
    fi
  done
}

# ── Unit Tests: from_wei ────────────────────────────────────────────────────

test_from_wei() {
  section "from_wei conversion"

  source_functions

  local cases=(
    # "wei decimals expected"
    "1000000000000000000 18 1"
    "500000000000000000 18 0.5"
    "100000000 6 100"
    "50000000 8 0.5"
    "1500000 6 1.5"
    "0 18 0"
    "1000000000000000 18 0.001"
    "1 6 0.000001"
    "123456789 6 123.456789"
    "1 18 0.000000000000000001"
    "999 0 999"
  )

  for c in "${cases[@]}"; do
    local wei decimals expected
    read -r wei decimals expected <<< "$c"
    local got
    got=$(from_wei "$wei" "$decimals")
    if [[ "$got" == "$expected" ]]; then
      pass "from_wei($wei, $decimals) = $expected"
    else
      fail "from_wei($wei, $decimals) expected=$expected got=$got"
    fi
  done
}

# ── Unit Tests: roundtrip ──────────────────────────────────────────────────

test_roundtrip() {
  section "to_wei/from_wei roundtrip"

  source_functions

  local cases=(
    "1 18"
    "0.5 18"
    "100 6"
    "0.5 8"
    "1.5 6"
    "1000 18"
    "0.000001 6"
  )

  for c in "${cases[@]}"; do
    local input decimals
    read -r input decimals <<< "$c"
    local wei back
    wei=$(to_wei "$input" "$decimals")
    back=$(from_wei "$wei" "$decimals")
    if [[ "$back" == "$input" ]]; then
      pass "roundtrip($input, $decimals) = $input"
    else
      fail "roundtrip($input, $decimals) to_wei=$wei from_wei=$back"
    fi
  done
}

# ── Unit Tests: is_positive_uint ────────────────────────────────────────────

test_is_positive_uint() {
  section "is_positive_uint validation"

  source_functions

  local positive_cases=(
    "1"
    "42"
    "103724461543741151205"
    "115792089237316195423570985008687907853269984665640564039457584007913129639935"
  )

  local zero_or_invalid_cases=(
    "0"
    "0000"
    ""
    "abc"
    "12.3"
    "-1"
  )

  local value
  for value in "${positive_cases[@]}"; do
    if is_positive_uint "$value"; then
      pass "is_positive_uint($value) = true"
    else
      fail "is_positive_uint($value) expected=true"
    fi
  done

  for value in "${zero_or_invalid_cases[@]}"; do
    if is_positive_uint "$value"; then
      fail "is_positive_uint($value) expected=false"
    else
      pass "is_positive_uint($value) = false"
    fi
  done
}

# ── Live Tests ──────────────────────────────────────────────────────────────

# Run fast-swap and capture stdout (JSON) and exit code
run_swap() {
  local stdout
  stdout=$(bash "$FAST_SWAP" "$@" 2>/dev/null)
  local rc=$?
  echo "$stdout"
  return $rc
}

# Validate JSON output structure
validate_success_json() {
  local json="$1" label="$2"
  local checks=(
    '.ok == true'
    '.chain != null'
    '.sender != null'
    '.tokenIn.symbol != null'
    '.tokenIn.address != null'
    '.tokenIn.decimals != null'
    '.tokenOut.symbol != null'
    '.tokenOut.address != null'
    '.tokenOut.decimals != null'
    '.quote.amountIn != null'
    '.quote.amountInWei != null'
    '.quote.amountOut != null'
    '.quote.routerAddress != null'
    '.tx.to != null'
    '.tx.data != null'
    '.tx.value != null'
    '.tx.gas != null'
  )

  local all_ok=true
  for check in "${checks[@]}"; do
    local result
    result=$(echo "$json" | jq -r "$check" 2>/dev/null)
    if [[ "$result" != "true" ]]; then
      fail "$label — check failed: $check"
      all_ok=false
    fi
  done

  if [[ "$all_ok" == "true" ]]; then
    pass "$label — JSON structure valid"
  fi
}

test_live_native_to_erc20() {
  section "Live: Native → ERC-20 (ETH→USDC on ethereum)"

  local json
  json=$(run_swap 0.001 ETH USDC ethereum "$TEST_SENDER" "$TEST_SENDER" 50)
  local rc=$?

  if [[ $rc -ne 0 ]]; then
    fail "ETH→USDC exit code=$rc"
    return
  fi

  local ok
  ok=$(echo "$json" | jq -r '.ok' 2>/dev/null)
  if [[ "$ok" != "true" ]]; then
    local err
    err=$(echo "$json" | jq -r '.error // "unknown"' 2>/dev/null)
    fail "ETH→USDC ok=false error=$err"
    return
  fi

  validate_success_json "$json" "ETH→USDC"

  # Check specific values
  local chain tin_sym tout_sym tin_addr tin_native
  chain=$(echo "$json" | jq -r '.chain')
  tin_sym=$(echo "$json" | jq -r '.tokenIn.symbol')
  tout_sym=$(echo "$json" | jq -r '.tokenOut.symbol')
  tin_addr=$(echo "$json" | jq -r '.tokenIn.address')
  tin_native=$(echo "$json" | jq -r '.tokenIn.isNative')

  [[ "$chain" == "ethereum" ]] && pass "ETH→USDC chain=ethereum" || fail "ETH→USDC chain=$chain"
  [[ "$tin_sym" == "ETH" ]] && pass "ETH→USDC tokenIn=ETH" || fail "ETH→USDC tokenIn=$tin_sym"
  [[ "$tout_sym" == "USDC" ]] && pass "ETH→USDC tokenOut=USDC" || fail "ETH→USDC tokenOut=$tout_sym"
  [[ "$tin_native" == "true" ]] && pass "ETH→USDC isNative=true" || fail "ETH→USDC isNative=$tin_native"

  # tx.value should be non-zero for native input
  local tx_value
  tx_value=$(echo "$json" | jq -r '.tx.value')
  [[ "$tx_value" != "0" && -n "$tx_value" ]] && pass "ETH→USDC tx.value is non-zero" || fail "ETH→USDC tx.value=$tx_value"

  # tx.data should start with 0x
  local tx_data
  tx_data=$(echo "$json" | jq -r '.tx.data')
  [[ "$tx_data" == 0x* ]] && pass "ETH→USDC tx.data starts with 0x" || fail "ETH→USDC tx.data prefix"
}

test_live_erc20_to_native() {
  section "Live: ERC-20 → Native (USDC→ETH on ethereum)"

  local json
  json=$(run_swap 1 USDC ETH ethereum "$TEST_SENDER" "$TEST_SENDER" 50)
  local rc=$?

  if [[ $rc -ne 0 ]]; then
    fail "USDC→ETH exit code=$rc"
    return
  fi

  local ok
  ok=$(echo "$json" | jq -r '.ok' 2>/dev/null)
  if [[ "$ok" != "true" ]]; then
    local err
    err=$(echo "$json" | jq -r '.error // "unknown"' 2>/dev/null)
    fail "USDC→ETH ok=false error=$err"
    return
  fi

  validate_success_json "$json" "USDC→ETH"

  local tout_native tx_value
  tout_native=$(echo "$json" | jq -r '.tokenOut.isNative')
  tx_value=$(echo "$json" | jq -r '.tx.value')

  [[ "$tout_native" == "true" ]] && pass "USDC→ETH tokenOut.isNative=true" || fail "USDC→ETH isNative=$tout_native"
  # tx.value should be 0 for ERC-20 input
  [[ "$tx_value" == "0" ]] && pass "USDC→ETH tx.value=0 (ERC-20 input)" || fail "USDC→ETH tx.value=$tx_value"
}

test_live_l2_chain() {
  section "Live: L2 chain (ETH→USDC on arbitrum)"

  local json
  json=$(run_swap 0.001 ETH USDC arbitrum "$TEST_SENDER" "$TEST_SENDER" 50)
  local rc=$?

  if [[ $rc -ne 0 ]]; then
    fail "ARB ETH→USDC exit code=$rc"
    return
  fi

  local ok
  ok=$(echo "$json" | jq -r '.ok' 2>/dev/null)
  if [[ "$ok" != "true" ]]; then
    local err
    err=$(echo "$json" | jq -r '.error // "unknown"' 2>/dev/null)
    fail "ARB ETH→USDC ok=false error=$err"
    return
  fi

  validate_success_json "$json" "ARB ETH→USDC"

  local chain
  chain=$(echo "$json" | jq -r '.chain')
  [[ "$chain" == "arbitrum" ]] && pass "ARB ETH→USDC chain=arbitrum" || fail "ARB chain=$chain"
}

test_live_token_api_fallback() {
  section "Live: Token API fallback (LINK→USDC on ethereum)"

  # Use LINK instead of WBTC — WBTC is missing from Token API and needs
  # to be added to the built-in registry. LINK exercises the same fallback path.
  local json
  json=$(run_swap 1 LINK USDC ethereum "$TEST_SENDER" "$TEST_SENDER" 100)
  local rc=$?

  if [[ $rc -ne 0 ]]; then
    fail "LINK→USDC exit code=$rc"
    return
  fi

  local ok
  ok=$(echo "$json" | jq -r '.ok' 2>/dev/null)
  if [[ "$ok" != "true" ]]; then
    local err
    err=$(echo "$json" | jq -r '.error // "unknown"' 2>/dev/null)
    fail "LINK→USDC ok=false error=$err"
    return
  fi

  validate_success_json "$json" "LINK→USDC"

  # LINK should be resolved via Token API with 18 decimals
  local link_dec
  link_dec=$(echo "$json" | jq -r '.tokenIn.decimals')
  [[ "$link_dec" == "18" ]] && pass "LINK→USDC LINK decimals=18" || fail "LINK→USDC decimals=$link_dec (expected 18)"

  # Verify it was resolved (not native)
  local link_native
  link_native=$(echo "$json" | jq -r '.tokenIn.isNative')
  [[ "$link_native" == "false" ]] && pass "LINK→USDC LINK isNative=false" || fail "LINK→USDC isNative=$link_native"
}

test_live_stablecoin_pair() {
  section "Live: Stablecoin pair (USDC→USDT on ethereum)"

  # Use 10 USDC — very small amounts (1 USDC) can trigger API error 4222
  local json
  json=$(run_swap 10 USDC USDT ethereum "$TEST_SENDER" "$TEST_SENDER" 5)
  local rc=$?

  if [[ $rc -ne 0 ]]; then
    fail "USDC→USDT exit code=$rc"
    return
  fi

  local ok
  ok=$(echo "$json" | jq -r '.ok' 2>/dev/null)
  if [[ "$ok" != "true" ]]; then
    local err
    err=$(echo "$json" | jq -r '.error // "unknown"' 2>/dev/null)
    fail "USDC→USDT ok=false error=$err"
    return
  fi

  validate_success_json "$json" "USDC→USDT"

  # Both should have 6 decimals
  local in_dec out_dec
  in_dec=$(echo "$json" | jq -r '.tokenIn.decimals')
  out_dec=$(echo "$json" | jq -r '.tokenOut.decimals')
  [[ "$in_dec" == "6" ]] && pass "USDC→USDT USDC decimals=6" || fail "USDC→USDT USDC dec=$in_dec"
  [[ "$out_dec" == "6" ]] && pass "USDC→USDT USDT decimals=6" || fail "USDC→USDT USDT dec=$out_dec"
}

# ── Error Tests ─────────────────────────────────────────────────────────────

test_error_missing_args() {
  section "Error: missing arguments"

  local rc=0
  bash "$FAST_SWAP" >/dev/null 2>&1 || rc=$?

  # Should exit non-zero (usage)
  [[ $rc -ne 0 ]] && pass "Missing args → non-zero exit ($rc)" || fail "Missing args → exit=$rc"
}

test_error_unsupported_chain() {
  section "Error: unsupported chain"

  local json
  json=$(run_swap 1 ETH USDC fakechain "$TEST_SENDER" 2>/dev/null) || true

  local ok err
  ok=$(echo "$json" | jq -r '.ok' 2>/dev/null)
  err=$(echo "$json" | jq -r '.error // ""' 2>/dev/null)

  [[ "$ok" == "false" ]] && pass "Unsupported chain → ok=false" || fail "Unsupported chain → ok=$ok"
  [[ "$err" == *"Unsupported chain"* ]] && pass "Unsupported chain → error message" || fail "Unsupported chain → error=$err"
}

test_error_unknown_token() {
  section "Error: unknown token"

  local json rc=0
  # Use a token that definitely doesn't exist
  json=$(bash "$FAST_SWAP" 1 ZZZZNOTREAL ETH ethereum "$TEST_SENDER" 2>/dev/null) || rc=$?

  if [[ -z "$json" ]]; then
    # Script might exit without JSON on some failures
    [[ $rc -ne 0 ]] && pass "Unknown token → non-zero exit ($rc)" || fail "Unknown token → no output and exit=0"
    return
  fi

  local ok err
  ok=$(echo "$json" | jq -r '.ok' 2>/dev/null)
  err=$(echo "$json" | jq -r '.error // ""' 2>/dev/null)

  [[ "$ok" == "false" ]] && pass "Unknown token → ok=false" || fail "Unknown token → ok=$ok"
  [[ "$err" == *"not found"* ]] && pass "Unknown token → error message" || fail "Unknown token → error=$err"
}

# ── Chain-Specific Token Resolution ─────────────────────────────────────────

test_live_polygon() {
  section "Live: Polygon (POL→USDC)"

  local json
  json=$(run_swap 1 POL USDC polygon "$TEST_SENDER" "$TEST_SENDER" 50)
  local rc=$?

  if [[ $rc -ne 0 ]]; then
    fail "POL→USDC exit code=$rc"
    return
  fi

  local ok
  ok=$(echo "$json" | jq -r '.ok' 2>/dev/null)
  if [[ "$ok" != "true" ]]; then
    local err
    err=$(echo "$json" | jq -r '.error // "unknown"' 2>/dev/null)
    fail "POL→USDC ok=false error=$err"
    return
  fi

  validate_success_json "$json" "POL→USDC"

  local tin_native chain
  tin_native=$(echo "$json" | jq -r '.tokenIn.isNative')
  chain=$(echo "$json" | jq -r '.chain')
  [[ "$tin_native" == "true" ]] && pass "POL→USDC isNative=true" || fail "POL→USDC isNative=$tin_native"
  [[ "$chain" == "polygon" ]] && pass "POL→USDC chain=polygon" || fail "POL→USDC chain=$chain"
}

test_live_bsc() {
  section "Live: BSC (BNB→USDT)"

  local json
  json=$(run_swap 0.01 BNB USDT bsc "$TEST_SENDER" "$TEST_SENDER" 50)
  local rc=$?

  if [[ $rc -ne 0 ]]; then
    fail "BNB→USDT exit code=$rc"
    return
  fi

  local ok
  ok=$(echo "$json" | jq -r '.ok' 2>/dev/null)
  if [[ "$ok" != "true" ]]; then
    local err
    err=$(echo "$json" | jq -r '.error // "unknown"' 2>/dev/null)
    fail "BNB→USDT ok=false error=$err"
    return
  fi

  validate_success_json "$json" "BNB→USDT"

  local chain tout_dec
  chain=$(echo "$json" | jq -r '.chain')
  tout_dec=$(echo "$json" | jq -r '.tokenOut.decimals')
  [[ "$chain" == "bsc" ]] && pass "BNB→USDT chain=bsc" || fail "BNB→USDT chain=$chain"
  [[ "$tout_dec" == "18" ]] && pass "BNB→USDT BSC USDT decimals=18" || fail "BNB→USDT USDT dec=$tout_dec"
}

# ── Runner ───────────────────────────────────────────────────────────────────

run_unit_tests() {
  test_to_wei
  test_from_wei
  test_roundtrip
  test_is_positive_uint
}

run_live_tests() {
  test_live_native_to_erc20
  test_live_erc20_to_native
  test_live_l2_chain
  test_live_token_api_fallback
  test_live_stablecoin_pair
  test_live_polygon
  test_live_bsc
  test_error_missing_args
  test_error_unsupported_chain
  test_error_unknown_token
}

main() {
  echo "=== fast-swap.sh test suite ==="
  echo "Script: $FAST_SWAP"
  echo

  local mode="${1:-all}"

  case "$mode" in
    unit)
      run_unit_tests
      ;;
    live)
      # Check dependencies first
      for cmd in curl jq; do
        if ! command -v "$cmd" &>/dev/null; then
          echo "ERROR: $cmd is required for live tests"
          exit 1
        fi
      done
      run_live_tests
      ;;
    all)
      run_unit_tests
      for cmd in curl jq; do
        if ! command -v "$cmd" &>/dev/null; then
          echo "WARNING: $cmd not found, skipping live tests"
          SKIP=$((SKIP + 10))
          echo
          echo "========================================="
          echo "Results: $PASS passed, $FAIL failed, $SKIP skipped"
          echo "========================================="
          exit 0
        fi
      done
      run_live_tests
      ;;
    *)
      echo "Usage: $0 [unit|live|all]"
      exit 1
      ;;
  esac

  echo
  echo "========================================="
  echo "Results: $PASS passed, $FAIL failed, $SKIP skipped"
  echo "========================================="

  [[ $FAIL -eq 0 ]] && exit 0 || exit 1
}

main "$@"
