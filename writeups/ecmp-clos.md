# How ECMP actually distributes traffic in a Clos network

A leaf-spine (Clos) fabric only scales if traffic spreads evenly across every spine. That spreading is ECMP — Equal-Cost Multi-Path. The subtlety is that ECMP does **not** load-balance bytes; it load-balances **flows**, by hashing. Understanding the hash is understanding why fabrics sometimes look lopsided even when nothing is broken.

## The topology

```
        Spine1   Spine2   Spine3   Spine4
          | \  /  |  \  /  |  \  /  |
          |  \/   |   \/   |   \/   |
          |  /\   |   /\   |   /\   |
        Leaf1    Leaf2    Leaf3    Leaf4
          |        |        |        |
        Hosts    Hosts    Hosts    Hosts
```

Every leaf has an equal-cost path to every other leaf through *each* spine. With 4 spines, a leaf-to-leaf flow has 4 candidate next hops.

## How a next hop is chosen

For each packet, the switch computes a hash over a **flow tuple** — typically the 5-tuple (src IP, dst IP, protocol, src port, dst port) — then maps the hash to one of the N next hops:

```
next_hop = hash(5-tuple) mod N
```

Because the tuple is constant for the life of a flow, **every packet of one flow takes the same path**. That's deliberate: it prevents packet reordering within a TCP flow, which would wreck throughput.

## Why "balanced" is statistical, not exact

ECMP balances *flows*, not *bandwidth*. Consequences that trip people up:

- **Elephant flows.** One 40G flow hashes to a single spine and stays there. Three elephants can land on the same spine and congest it while another spine sits idle. ECMP did exactly what it was told — it just can't split a single flow.
- **Low flow count.** A handful of flows may hash unevenly by pure chance. Balance improves as flow count rises (law of large numbers).
- **Polarization.** If every switch hashes with the same seed/algorithm, the *same* flows get pushed the same direction at every tier, so downstream links starve. The fix is per-device hash seeds so each tier decorrelates.

## Diagnosing "one spine is hot"

1. Confirm all ECMP members are actually programmed (`show ip route` / hardware ECMP group) — a member missing from hardware silently halves capacity.
2. Look at per-flow, not aggregate, counters — an elephant flow is a per-flow problem.
3. Check hash inputs: if L4 ports aren't in the hash (e.g. encapsulated/fragmented traffic), many flows collapse to the same tuple and pin to one path.
4. Verify per-node seeds to rule out polarization.

## Levers

- Add **L4 ports** to the hash so many conversations between the same IP pair still spread.
- **Dynamic / flowlet load balancing** breaks a flow into bursts ("flowlets") separated by gaps large enough that reordering is a non-issue, then rebalances flowlets — much better for elephants.
- **Per-packet spraying** exists (and is used in some AI fabrics) but requires the endpoints to tolerate reordering.

## The takeaway

ECMP is hashing, not metering. It's excellent with many small flows and blind to a single large one. When a Clos fabric looks imbalanced, the question is almost never "is ECMP broken?" — it's "what are the flows, and what's in the hash?"
