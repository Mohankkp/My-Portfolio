# Designing networks for AI/GPU workloads

*An architecture study — how AI training traffic reshapes fabric design, and why classic data-center assumptions stop holding.*

AI training networks look like data-center fabrics but behave nothing like them. A web/data-center fabric carries millions of small, independent, bursty flows. An AI training fabric carries a **small number of enormous, synchronized, long-lived flows** driven by collective operations (all-reduce, all-to-all). Almost every design decision follows from that difference.

## Why the traffic is different

During distributed training, GPUs exchange gradients every step via collectives. That produces traffic that is:
- **High bandwidth per flow** — 100s of Gb/s between GPU pairs, sustained.
- **Synchronized** — all GPUs transmit at once, then compute, then transmit again. Bursty in lockstep.
- **Tail-latency sensitive** — a step finishes only when the *slowest* GPU finishes. One congested link stalls the entire job.
- **Few flows** — dozens of large flows, not millions of small ones.

## Consequence 1: ECMP hashing breaks down

Classic ECMP hashes a flow to one path (see [ECMP in a Clos network](ecmp-clos.md)). With millions of flows that averages out; with a handful of elephant flows it collapses — two 400G flows can collide on one link while a parallel link is idle. AI fabrics therefore lean on:
- **Per-packet / packet spraying** across all paths, with endpoints (NICs) that reorder at the destination.
- **Flowlet** load balancing.
- **Adaptive routing** that reacts to congestion in hardware rather than hashing blindly.

## Consequence 2: the network must be lossless

TCP tolerates loss; collective libraries running over RDMA do not — historically a single drop triggered a **go-back-N** retransmission that re-sends everything after the lost packet, stalling the step badly. So AI fabrics run **RoCEv2** (RDMA over Converged Ethernet — the InfiniBand transport riding inside UDP, destination port **4791**, over routable IP) and engineer for losslessness with two cooperating mechanisms:

**PFC (Priority Flow Control, 802.1Qbb)** — per-priority PAUSE. When a switch's ingress buffer for the RDMA class fills, it sends a PAUSE *upstream* to stop that class only, so bulk traffic never forces a drop of RDMA. Two hazards to design around:
- **Head-of-line blocking** — PAUSE stops a whole priority on a link, not just the one flow that caused congestion.
- **PFC deadlock** — cyclic buffer dependencies (often via a CLOS with unexpected traffic loops) where switches PAUSE each other in a ring and traffic wedges permanently. Deadlock avoidance (or watchdogs that break it) is a real design constraint.

**ECN + DCQCN** — the *proactive* half. Switches mark packets with ECN as queues build; the receiver reflects that back via **CNP** (Congestion Notification Packets); the sender's NIC then ramps its rate down (and slowly back up). DCQCN is the widely used control loop that ties ECN marking to sender rate so congestion is smoothed **before** buffers hit the PFC threshold. Well-tuned, ECN does the everyday work and PFC is the last-resort safety net — you want to lean on ECN and rarely trigger PFC.

The design goal shifts from "absorb loss gracefully" to "never drop the RDMA class, and rarely even PAUSE it."

## Consequence 3: low oversubscription, rail-optimized topology

Web fabrics are often oversubscribed (e.g. 3:1 at the leaf) because not all hosts talk at once. AI fabrics assume everything talks at once, so they aim for **1:1, non-blocking** designs — often a **rail-optimized** layout where each GPU's NIC connects to a dedicated rail of the fabric, keeping same-rank collective traffic on short, predictable paths.

```
            Spine / Core
            /    |     \
        Leaf   Leaf   Leaf      (non-blocking, 1:1)
         |      |      |
       GPU rail GPU rail GPU rail
        (each GPU NIC -> its own rail)
```

## Consequence 4: line-rate is the baseline, not the peak

In a web fabric, average utilization is modest and bursts are absorbed by buffers. In a training fabric the collective phase drives links to **line rate** — 100% of 400G — sustained, on many links at once. That reframes the switch's job:
- **Buffering** is about surviving microbursts at line rate without dropping the RDMA class, not about long-term queueing. Deep buffers help absorb incast (many GPUs → one) during all-reduce.
- **Cut-through** forwarding minimizes per-hop latency, which matters because collective completion is latency- *and* bandwidth-bound.
- **Incast** is the signature failure: an all-reduce/all-gather step has many senders targeting one receiver simultaneously, overflowing one egress queue. ECN/DCQCN and careful buffer allocation exist largely to survive incast.

## Consequence 5: telemetry and topology awareness

Because the slowest link caps the whole job, you need **fine-grained telemetry** — per-queue depth, ECN mark counts, PFC pause/CNP counters, and per-flow path — to find the one hot link fast. In-band telemetry (INT) that stamps per-hop latency onto packets is increasingly used for exactly this. And the training scheduler benefits from **topology awareness**: place ranks that communicate heavily close together so collectives stay within a rail or a leaf, cutting both hop count and the chance of cross-fabric congestion.

## Design summary

| Dimension | Classic DC fabric | AI/GPU fabric |
|---|---|---|
| Flows | Millions, small | Few, huge |
| Load balancing | Flow-hash ECMP | Packet spray / adaptive |
| Loss tolerance | Lossy OK (TCP) | Lossless (RoCE + PFC/ECN) |
| Oversubscription | 3:1 common | ~1:1 non-blocking |
| Optimize for | Average throughput | Tail latency / job completion |

## The takeaway

An AI network isn't a faster data-center network — it's a different problem. The unit of success is **job completion time**, which is set by the slowest GPU, which is set by the most congested link. Everything — lossless transport, adaptive load balancing, non-blocking topology, deep telemetry — exists to protect that tail. This is a study, not production experience, but it's exactly the direction large-scale infrastructure is heading.
