# RoCEv2 / AI-cluster network testbed (design + methodology)

A testbed design for reproducing and root-causing the network problems that cap
AI/ML training performance on a 100G/400G fabric: RoCEv2 packet drops, ECMP path
imbalance, and MTU mismatches. Based on lab testbed work simulating AI/ML cluster
traffic on Arista EOS.

> **Status: design + methodology, not a one-command lab.** True RoCEv2 needs RDMA
> NICs (or a hardware traffic generator like IXIA) and lossless-Ethernet features
> that don't exist in plain containers, so this documents the setup, method, and
> what to measure rather than shipping a container topology. The
> [EVPN-VXLAN lab](../containerlab-evpn-vxlan/README.md) is the runnable one.

## Topology

```
   Host/GPU ── Leaf ── Spine ── Leaf ── Host/GPU
                 |                 |
              traffic gen        capture
             (IXIA / perftest)  (tcpdump / Wireshark)
```

- 100G/400G leaf-spine, ECMP across spines.
- One priority class dedicated to RoCEv2 with PFC + ECN enabled.
- Traffic generator produces synthetic **all-reduce** and **incast** patterns.

## What to measure

| Signal | Tool | What it tells you |
|---|---|---|
| RoCEv2 drops | switch drop counters, Wireshark | Is the RDMA class actually lossless? |
| ECMP distribution | per-interface counters, 5-tuple analysis | Elephant-flow collision / hash polarization |
| PFC pause / CNP | per-queue counters | Congestion hitting the last-resort PAUSE vs. ECN |
| MTU behavior | ping sweep + capture | Silent large-packet loss small pings never show |
| Latency / JCT | perftest, app timers | Tail latency that caps job-completion time |

## Method

1. Baseline the fabric with a single flow at line rate — confirm no loss, correct MTU end to end.
2. Add many flows; inspect ECMP spread. Look for members carrying disproportionate load (elephant-flow collision).
3. Drive incast (many senders → one receiver) to exercise PFC/ECN; confirm ECN does the work and PFC is rarely triggered.
4. Introduce an MTU mismatch on one hop; show small pings pass while RoCE bulk traffic fails — then fix and re-verify.
5. Capture at ingress/egress and correlate drops to the responsible mechanism.

## Companion reading

- [Designing networks for AI/GPU workloads](../../writeups/ai-gpu-network-design.md) — RoCEv2, PFC/ECN, DCQCN, incast, line-rate.
- [How ECMP actually distributes traffic in a Clos network](../../writeups/ecmp-clos.md).
