# What happens when a spine switch fails?

The point of a Clos fabric is that losing a spine should degrade capacity, not connectivity. Whether that promise holds comes down to how fast every leaf notices and reroutes. Here's the sequence, and where the milliseconds actually go.

## The failure sequence

```
Spine2 fails
      |
Link-down detection on every attached leaf
      |
BGP session to Spine2 torn down
      |
Routes via Spine2 withdrawn from RIB/FIB
      |
ECMP group recomputed (N spines -> N-1)
      |
Traffic reconverges onto remaining spines
```

Connectivity survives because each leaf still has N-1 equal-cost paths. Capacity drops by 1/N — with 4 spines, a spine loss is a 25% capacity hit, which is exactly why capacity planning assumes N-1 (or N-2).

## Where the time goes

Convergence time is dominated by **detection**, not by BGP itself.

- **Physical link down** (fiber cut, port down): detected in milliseconds via loss-of-signal. Fast.
- **Soft failure** (spine alive but not forwarding — a "gray failure"): the link stays *up*, so there's nothing to detect at L1. This is the dangerous case.

To detect soft failures quickly, run **BFD** (Bidirectional Forwarding Detection) alongside BGP. BFD sends lightweight hellos on a sub-second timer; when they stop, it tears the BGP session down immediately instead of waiting for the BGP hold timer (default 90s / 180s). BFD turns a multi-second black hole into a sub-second reroute.

## Recomputing ECMP

Once routes via the dead spine are withdrawn, the leaf's ECMP group shrinks from N to N-1 members. Well-designed hardware does a **fast reroute** — reprogramming the group without rehashing every flow onto new paths — so surviving flows stay put and only the flows that were on the dead spine move. Naive implementations rehash everything, causing a brief reordering storm.

## Blast radius and design implications

- **Failure domain** is one spine = 1/N of fabric capacity. More spines = smaller blast radius per failure, at the cost of more ports.
- **Provision for N-1.** If the fabric runs above (N-1)/N utilization, a single spine loss causes congestion, not just reduced headroom.
- **Graceful restart / graceful shutdown** for *planned* maintenance: drain a spine by advertising worse metrics first, let traffic move off, *then* take it down — zero-loss maintenance instead of a hard withdrawal.

## The takeaway

A Clos fabric tolerates spine loss by design, but the promise is only as good as your failure detection. Hard failures are easy; gray failures need BFD. And the whole thing only stays lossless if you planned capacity for N-1 — redundancy you can't actually absorb traffic onto isn't redundancy.
