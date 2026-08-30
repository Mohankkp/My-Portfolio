# What actually happens inside an Internet Exchange Point

An IXP looks simple from the outside — "networks peer here" — but it's one of the most interesting pieces of Internet-edge infrastructure. At its core an IXP is **a shared Layer-2 Ethernet fabric** where autonomous systems (ASes) exchange traffic directly via BGP, bypassing paid transit. The economics drive everything: a 100GE IXP port runs roughly $2–5K/month flat, versus tens of thousands for equivalent transit — so anyone with meaningful traffic peers.

## The shared-VLAN model

Every member plugs a router into the IXP switch, gets an IP on a **shared peering LAN** (e.g. `198.51.100.0/24`), and establishes eBGP sessions to other members to swap prefixes. There is **no per-peer VLAN and no dedicated circuit** — everyone sits in the same broadcast domain. Who you peer with is purely a BGP-config decision:

```
To peer with AS-X:  configure neighbor <X's LAN IP> remote-as <X>
To not peer:        simply don't configure the session
```

The IXP provides exactly three things: a physical port, an IP on the shared LAN, and (optionally) a route server. It stays deliberately neutral — it never routes, never makes peering decisions, never touches your traffic.

## The route server: a route reflector for eBGP

With N members, full bilateral peering is N·(N-1)/2 sessions — hundreds of eBGP sessions per router. The **route server** collapses that: you peer once with the route server (usually two, for redundancy) and it redistributes routes from every participating member.

It behaves like a route reflector, but for **eBGP** peers, and in *transparent* mode it:
- does **not** prepend its own AS to the AS-path,
- does **not** rewrite the next-hop,
- **preserves** BGP communities.

So routes appear to come straight from the originating AS. Route servers are pure control plane — typically BIRD or OpenBGPD on Linux — and never forward a single data packet. Per-member export filtering and RPKI origin validation commonly live here too.

## The hardware is intentionally dumb

IXP core switches are **pure L2** — Arista 7280R3/7800R3, Nokia 7250 IXR, Juniper QFX-class. No routing protocols toward members, cut-through switching for sub-microsecond latency, 100/400GE density, and no Spanning Tree in modern designs. The switch forwards frames and never looks at an IP header. "A dumb pipe — deliberately."

## Scaling from one building to a metro

- **Small IXP:** one or two switches, one VLAN, a flat L2 domain, maybe a LAG for redundancy.
- **Large IXP:** DE-CIX Frankfurt spans 30+ data centers across a city. The hard problem is stretching **one** peering VLAN across many buildings while keeping every member in the same L2 domain.
  - *Old way:* Q-in-Q, long-haul L2 trunks, VPLS — limited by STP scaling, MAC-table explosion, and poor fault isolation.
  - *Modern way:* **EVPN.** DE-CIX migrated its exchanges to EVPN ("Peering LAN 2.0", per RFC 9161) in Dec 2022.

## EVPN inside a large IXP

- **Underlay:** internal switches run an IGP with Segment Routing (IS-IS + SR-MPLS) for internal reachability — completely invisible to members.
- **Overlay:** EVPN (MP-BGP L2VPN EVPN address family) between leaf switches. Each member port is an attachment circuit on an EVPN **ELAN**; MACs are learned at the edge and distributed by BGP instead of flooded.
- **Members still see** a single L2 peering VLAN, unaware of the SR + EVPN fabric underneath.

Why it's a big upgrade for an exchange:
1. **No ARP/NDP flooding** — proxy-ARP answers locally (DE-CIX reported ~25% CPU reduction on member routers post-migration).
2. **Control-plane MAC learning** prevents MAC spoofing.
3. **Multi-homing** via EVPN active-active Ethernet Segments (RFC 7432) — standards-based, no proprietary MC-LAG.
4. **Traffic engineering** through the SR underlay.
5. **Fast, deterministic convergence** — sub-second MAC withdrawal via BGP instead of minutes of MAC aging.
6. **Security** against ARP poisoning and broadcast storms.

## The takeaway

An IXP is BGP peering over a shared Ethernet fabric — the switch is a neutral dumb pipe, the route server scales out the control plane, and members decide adjacency purely in config. Internally, the biggest exchanges now run the same stack as modern DC and SP networks: **Segment Routing for transport, EVPN for services, MP-BGP tying it together**. The platform changed; the principles didn't.

*Enriched from an article by Renato Gentil (Aug 2026) plus standard IXP/EVPN references (RFC 7432, RFC 9161).*
