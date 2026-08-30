# EVPN-VXLAN leaf-spine fabric (Containerlab + FRRouting)

A reproducible 2-spine / 4-leaf Clos fabric running **eBGP in the underlay** and
**BGP-EVPN in the overlay**, with **VXLAN** stitching four hosts into a single L2
segment across an all-L3 fabric. Everything runs in containers on one Linux host —
no hardware required.

```
        spine1        spine2
        /  |  \  \    /  /  |  \
       /   |   \  \  /  /   |   \
   leaf1 leaf2 leaf3 leaf4   (full mesh leaf<->spine)
     |     |     |     |
    h1    h2    h3    h4      (all in 10.10.10.0/24)
```

## Prerequisites

- Linux host with Docker
- [Containerlab](https://containerlab.dev/install/) (`bash -c "$(curl -sL https://get.containerlab.dev)"`)

## Run it

```bash
sudo containerlab deploy -t topology.clab.yml
```

## Validate

```bash
# Underlay: eBGP sessions to both spines should be Established
docker exec clab-evpn-vxlan-fabric-leaf1 vtysh -c "show bgp summary"

# Overlay: EVPN Type-2 (MAC/IP) and Type-3 (IMET) routes learned from other leaves
docker exec clab-evpn-vxlan-fabric-leaf1 vtysh -c "show bgp l2vpn evpn"

# Data plane: h1 should reach every other host over VXLAN
docker exec clab-evpn-vxlan-fabric-h1 ping -c3 10.10.10.4
```

Or run the scripted checks:

```bash
./validate.sh
```

## Failure tests (the interesting part)

| Test | Command | Expected |
|---|---|---|
| Spine failure | `sudo containerlab stop ... spine1` (or link down) | Sessions to spine1 drop; traffic reconverges on spine2; ping keeps working at reduced capacity |
| Leaf failure | stop `leaf3` | h3 unreachable; h1↔h2↔h4 unaffected — blast radius contained to one leaf |
| BGP withdrawal | shut the h4 access port | h4's Type-2 route withdrawn fabric-wide; h1 ARP for h4 fails cleanly |
| Convergence timing | `ping -i 0.2` during a spine drop | count lost packets to measure reconvergence |

See the companion write-ups: [spine failure & convergence](../../writeups/spine-failure-convergence.md),
[EVPN-VXLAN packet journey](../../writeups/evpn-vxlan-packet-journey.md).

## Teardown

```bash
sudo containerlab destroy -t topology.clab.yml
```

> Startup configs live in `configs/`. This is a learning lab — timers and
> addressing are chosen for clarity, not production hardening.
