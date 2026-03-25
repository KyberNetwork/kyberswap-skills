#!/usr/bin/env bash
# test-execute-swap.sh — Unit tests for execute-swap.sh helper functions
#
# Focuses on uint256_to_dec which converts cast output to plain decimals
# without overflowing bash signed 64-bit integers.
#
# Usage:
#   bash tests/test-execute-swap.sh
#
# Exit code: 0 if all pass, 1 if any fail

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
EXECUTE_SWAP="$REPO_ROOT/skills/swap-execute-fast/scripts/execute-swap.sh"

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

# Source uint256_to_dec from execute-swap.sh
source_functions() {
  local tmpfile
  tmpfile=$(mktemp)
  trap "rm -f '$tmpfile'" RETURN
  sed -n '/^uint256_to_dec()/,/^}/p' "$EXECUTE_SWAP" > "$tmpfile"
  source "$tmpfile"
}

# ── Unit Tests: uint256_to_dec — pure decimal input ─────────────────────────

test_uint256_to_dec_decimal() {
  section "uint256_to_dec: pure decimal passthrough"

  source_functions

  local cases=(
    # "input expected"
    "0 0"
    "1 1"
    "42 42"
    "1000000000000000000 1000000000000000000"
    "103724461543741151205 103724461543741151205"
    "115792089237316195423570985008687907853269984665640564039457584007913129639935 115792089237316195423570985008687907853269984665640564039457584007913129639935"
  )

  for c in "${cases[@]}"; do
    local input expected
    read -r input expected <<< "$c"
    local got
    got=$(uint256_to_dec "$input")
    local rc=$?
    if [[ $rc -eq 0 && "$got" == "$expected" ]]; then
      pass "uint256_to_dec('$input') = '$expected'"
    else
      fail "uint256_to_dec('$input') expected='$expected' got='$got' rc=$rc"
    fi
  done
}

# ── Unit Tests: uint256_to_dec — hex input (requires cast) ──────────────────

test_uint256_to_dec_hex() {
  section "uint256_to_dec: hex conversion via cast"

  if ! command -v cast &>/dev/null; then
    skip "cast not available — skipping hex tests"
    return
  fi

  source_functions

  local cases=(
    # "hex_input expected_decimal"
    "0x0 0"
    "0x1 1"
    "0xff 255"
    "0xDE0B6B3A7640000 1000000000000000000"
    "0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF 115792089237316195423570985008687907853269984665640564039457584007913129639935"
  )

  for c in "${cases[@]}"; do
    local input expected
    read -r input expected <<< "$c"
    local got
    got=$(uint256_to_dec "$input")
    local rc=$?
    if [[ $rc -eq 0 && "$got" == "$expected" ]]; then
      pass "uint256_to_dec('$input') = '$expected'"
    else
      fail "uint256_to_dec('$input') expected='$expected' got='$got' rc=$rc"
    fi
  done

  # Test mixed-case 0X prefix
  local got
  got=$(uint256_to_dec "0XFF")
  if [[ "$got" == "255" ]]; then
    pass "uint256_to_dec('0XFF') handles uppercase 0X prefix"
  else
    fail "uint256_to_dec('0XFF') expected='255' got='$got'"
  fi
}

# ── Unit Tests: uint256_to_dec — fallback truncation ────────────────────────

test_uint256_to_dec_fallback() {
  section "uint256_to_dec: fallback (strips trailing non-numeric)"

  source_functions

  # cast sometimes returns "12345\n" or "12345 " — the fallback handles this
  local cases=(
    # "input expected"
    "123abc 123"
    "999999999999999999999 trailing 999999999999999999999"
  )

  for c in "${cases[@]}"; do
    local input expected
    # Use first and last word only
    input="${c%% *}"
    expected="${c##* }"
    local got
    got=$(uint256_to_dec "$input")
    local rc=$?
    if [[ $rc -eq 0 && "$got" == "$expected" ]]; then
      pass "uint256_to_dec('$input') fallback = '$expected'"
    else
      fail "uint256_to_dec('$input') expected='$expected' got='$got' rc=$rc"
    fi
  done
}

# ── Unit Tests: uint256_to_dec — rejection cases ───────────────────────────

test_uint256_to_dec_reject() {
  section "uint256_to_dec: rejection (return 1)"

  source_functions

  local reject_cases=(
    ""
    "abc"
    "not_a_number"
    "-1"
    "-123"
  )

  for input in "${reject_cases[@]}"; do
    local got rc=0
    got=$(uint256_to_dec "$input" 2>/dev/null) || rc=$?
    if [[ $rc -ne 0 ]]; then
      pass "uint256_to_dec('$input') correctly rejected (rc=$rc)"
    else
      fail "uint256_to_dec('$input') should have been rejected but got='$got' rc=$rc"
    fi
  done
}

# ── Unit Tests: uint256_to_dec — callsite pattern ──────────────────────────

test_uint256_to_dec_callsite_pattern() {
  section "uint256_to_dec: callsite pattern \$(uint256_to_dec X || echo 0)"

  source_functions

  # This is how execute-swap.sh actually uses the function:
  #   balance_dec=$(uint256_to_dec "$balance_hex" || echo "0")
  # Verify the pattern produces sane results for all input types

  local cases=(
    # "input expected_via_pattern"
    "12345 12345"
    "0 0"
  )

  for c in "${cases[@]}"; do
    local input expected
    read -r input expected <<< "$c"
    local got
    got=$(uint256_to_dec "$input" || echo "0")
    if [[ "$got" == "$expected" ]]; then
      pass "callsite pattern('$input') = '$expected'"
    else
      fail "callsite pattern('$input') expected='$expected' got='$got'"
    fi
  done

  # Empty input should fallback to "0"
  local got
  got=$(uint256_to_dec "" || echo "0")
  if [[ "$got" == "0" ]]; then
    pass "callsite pattern('') = '0' (fallback)"
  else
    fail "callsite pattern('') expected='0' got='$got'"
  fi

  # Pure garbage should fallback to "0"
  got=$(uint256_to_dec "totally_invalid" || echo "0")
  if [[ "$got" == "0" ]]; then
    pass "callsite pattern('totally_invalid') = '0' (fallback)"
  else
    fail "callsite pattern('totally_invalid') expected='0' got='$got'"
  fi
}

# ── Runner ───────────────────────────────────────────────────────────────────

main() {
  echo "=== execute-swap.sh test suite ==="
  echo "Script: $EXECUTE_SWAP"
  echo

  test_uint256_to_dec_decimal
  test_uint256_to_dec_hex
  test_uint256_to_dec_fallback
  test_uint256_to_dec_reject
  test_uint256_to_dec_callsite_pattern

  echo
  echo "========================================="
  echo "Results: $PASS passed, $FAIL failed, $SKIP skipped"
  echo "========================================="

  [[ $FAIL -eq 0 ]] && exit 0 || exit 1
}

main "$@"
