# Kernel VXLAN / bridge setup (data plane)

The `.cfg` files configure FRR — the **control plane** (underlay eBGP + BGP-EVPN).
The VXLAN **data plane** is a Linux-kernel construct that must exist on each leaf
before `advertise-all-vni` has anything to advertise. On each leaf, VNI 10010 maps
to a bridge whose access port is the host-facing link (`eth3`).

Per-leaf setup (run inside each leaf container, e.g. via `docker exec` or a
containerlab `exec`), with `VTEP` = that leaf's loopback (10.0.0.1 … 10.0.0.4):

```bash
# L2 bridge for the tenant segment
ip link add name br10 type bridge
ip link set br10 up

# VXLAN interface for VNI 10010, sourced from the loopback (the VTEP IP)
ip link add vni10010 type vxlan id 10010 dstport 4789 \
    local <VTEP> nolearning
ip link set vni10010 master br10
ip link set vni10010 up

# Attach the host-facing access port to the bridge
ip link set eth3 master br10
```

`nolearning` is important: MAC learning comes from EVPN Type-2 routes, not from
data-plane flooding. Once the bridge + VXLAN interface exist, FRR discovers VNI
10010 and begins originating Type-2 (MAC/IP) and Type-3 (IMET) routes for it.

## Status

This lab is a **scaffold**: the topology, FRR configs, and validation script are
a realistic starting point but have not been brought up and verified on a Docker
host in this repo. Deploy it, confirm sessions reach `Established` and hosts ping
over VXLAN, then capture the output (or a short asciinema) as the portfolio proof.
Addressing and timers favor clarity over production hardening.
