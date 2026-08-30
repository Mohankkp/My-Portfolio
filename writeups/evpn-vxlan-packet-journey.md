# EVPN-VXLAN: from packet ingress to remote VTEP

EVPN-VXLAN gives you a Layer-2 service over a Layer-3 leaf-spine fabric. EVPN (a BGP address family) is the **control plane** — it distributes MAC and IP reachability. VXLAN is the **data plane** — it encapsulates the tenant frame in UDP so the fabric only ever routes IP. Keeping those two roles separate is the key to understanding the whole system.

## The players

- **VTEP** — VXLAN Tunnel Endpoint, the leaf switch that encaps/decaps. Identified by its VTEP IP (usually a loopback).
- **VNI** — VXLAN Network Identifier, the 24-bit segment ID (~16M segments vs. 4094 VLANs). An **L2VNI** carries a bridge domain; an **L3VNI** carries routed (VRF) traffic.
- **RD / RT** — every EVPN instance carries a **Route Distinguisher** (makes overlapping tenant MAC/IP unique in BGP) and **Route Targets** (import/export policy that controls which VRFs/bridge domains a route lands in). RD keeps routes distinct; RT decides who imports them.

## The EVPN route types

EVPN is defined in RFC 7432; the ones you actually watch on a fabric:

| Type | Name | Carries |
|---|---|---|
| **1** | Ethernet Auto-Discovery | Multi-homing: per-ES and per-EVI, enables fast withdrawal + aliasing |
| **2** | MAC/IP Advertisement | A host's MAC (and optionally IP) → VTEP, VNI, and MAC-mobility sequence |
| **3** | Inclusive Multicast (IMET) | The BUM flood list — who to replicate broadcast/unknown/multicast to |
| **4** | Ethernet Segment | ES discovery + Designated Forwarder election for multi-homed links |
| **5** | IP Prefix | Routed prefixes (L3VNI) — inter-subnet and external routing |

Type-2 and Type-3 do the day-to-day L2 work; Type-1/Type-4 exist for multi-homing; Type-5 is how the fabric routes between subnets and to the outside.

## Control plane first

When a host comes up and the leaf learns its MAC (and IP via ARP snooping), the leaf originates an **EVPN Type-2 route** into MP-BGP: "MAC `M`, IP `H`, reachable via VTEP `L1`, in VNI `V`." Route reflectors on the spines flood it to every other leaf. Now every VTEP has a MAC-to-VTEP mapping *before any data traffic flows* — that's the win over flood-and-learn: reachability is learned by routing protocol, not by flooding.

## Data plane: the packet's journey

```
Host A (Leaf L1)  ---->  Spine  ---->  Leaf L2  ---->  Host B

1. Frame arrives at L1 from Host A, dst MAC = Host B
2. L1 looks up dst MAC in its EVPN table  -> VTEP = L2, VNI = V
3. L1 encapsulates:
      [ outer IP: src L1, dst L2 ]
      [ outer UDP: dport 4789    ]
      [ VXLAN header: VNI = V    ]
      [ original L2 frame        ]
4. Fabric routes the outer packet L1 -> Spine -> L2 (plain IP/ECMP)
5. L2 receives on UDP 4789, matches VNI V, decapsulates
6. L2 forwards the inner frame to Host B
```

The spine never sees the tenant MAC — it only routes the outer IP header. That's what lets the fabric scale with pure L3 while presenting L2 adjacency to hosts.

## BUM traffic

Broadcast, unknown-unicast, and multicast can't be unicast-encapsulated. Two options:
- **Ingress replication** (head-end replication): the source VTEP makes N copies, one per remote VTEP in the VNI's Type-3 flood list. Simple, no multicast in the underlay — the common choice.
- **Underlay multicast**: each VNI maps to a multicast group; the fabric replicates. Scales better for very wide flooding but needs PIM in the underlay.

## Why ARP suppression matters

Because every VTEP already has the MAC/IP bindings from Type-2 routes, a leaf can answer ARP requests **locally** instead of flooding them across the fabric. On a large fabric this removes a huge amount of broadcast — a concrete example of the control plane eliminating data-plane work.

## Inter-subnet routing: symmetric vs. asymmetric IRB

To route *between* subnets, VTEPs use IRB (Integrated Routing and Bridging), usually with a **distributed anycast gateway** — every leaf shares the same gateway IP+MAC per subnet, so a host's default gateway is always its own local leaf (no hair-pinning to a central router).

- **Asymmetric IRB:** the ingress leaf routes *and* bridges into the destination VNI, then the egress leaf only bridges. Simple, but every leaf must be configured with every VNI it might talk to (route-in, bridge-out mismatch → "asymmetric").
- **Symmetric IRB:** ingress routes into a shared **L3VNI** (a transit VRF), the packet crosses the fabric in that L3VNI, and the egress leaf routes out to the local subnet. Both directions do route→route (symmetric). It scales far better — leaves only need the VNIs of locally attached subnets plus the common L3VNI — and is the standard choice on large fabrics.

## MAC mobility (when a host moves)

When a VM migrates from leaf A to leaf B, both could momentarily advertise the same MAC. The Type-2 route carries a **MAC Mobility extended community with a sequence number**; the higher sequence wins, so the fabric converges on the new location and the stale binding is withdrawn. A host that flaps between leaves repeatedly trips **MAC-move damping**, which flags a likely loop or duplicate rather than chasing it forever.

## The mental model

EVPN is "BGP for MAC addresses." VXLAN is "a UDP envelope so the fabric only routes IP." Learn the Type-2 / Type-3 / Type-5 routes and the encapsulation format, and almost every fabric behavior — silent hosts, MAC moves, BUM handling, symmetric vs. asymmetric IRB — follows from them.
