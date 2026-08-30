#!/usr/bin/env bash
# Validation checks for the EVPN-VXLAN fabric lab.
# Mirrors the kind of automated post-deployment validation described in the
# portfolio case study: assert control-plane and data-plane state, exit non-zero
# on the first failure so it can gate a pipeline.

set -euo pipefail

PREFIX="clab-evpn-vxlan-fabric"
FAIL=0

pass() { printf "  [PASS] %s\n" "$1"; }
fail() { printf "  [FAIL] %s\n" "$1"; FAIL=1; }

echo "== Underlay: BGP sessions Established on every leaf =="
for leaf in leaf1 leaf2 leaf3 leaf4; do
  established=$(docker exec "${PREFIX}-${leaf}" vtysh -c "show bgp summary json" 2>/dev/null \
    | grep -o '"state":"Established"' | wc -l || true)
  if [ "${established}" -ge 2 ]; then
    pass "${leaf}: ${established} sessions Established"
  else
    fail "${leaf}: only ${established} sessions Established (expected >= 2)"
  fi
done

echo "== Overlay: EVPN routes present on leaf1 =="
if docker exec "${PREFIX}-leaf1" vtysh -c "show bgp l2vpn evpn" 2>/dev/null | grep -q "Route Distinguisher"; then
  pass "leaf1 has EVPN routes"
else
  fail "leaf1 has no EVPN routes"
fi

echo "== Data plane: h1 reaches all other hosts over VXLAN =="
for ip in 10.10.10.2 10.10.10.3 10.10.10.4; do
  if docker exec "${PREFIX}-h1" ping -c2 -W2 "${ip}" >/dev/null 2>&1; then
    pass "h1 -> ${ip}"
  else
    fail "h1 -> ${ip} unreachable"
  fi
done

echo
if [ "${FAIL}" -eq 0 ]; then
  echo "ALL CHECKS PASSED"
else
  echo "VALIDATION FAILED"
fi
exit "${FAIL}"
