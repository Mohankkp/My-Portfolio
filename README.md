# Mohan Kumar — Network Development Engineer

Portfolio + engineering work. **Live site:** https://mohankkp.github.io/My-Portfolio/

Building reliable, scalable, and automated network infrastructure at cloud scale —
data center networking (BGP, EVPN-VXLAN, MPLS), cloud connectivity (AWS Direct
Connect), and network automation (Python, AWS).

## Repository layout

```
.
├── index.html                     # the portfolio site (GitHub Pages)
├── writeups/                      # technical deep dives
│   ├── bgp-session-troubleshooting.md
│   ├── evpn-vxlan-packet-journey.md
│   ├── ecmp-clos.md
│   ├── spine-failure-convergence.md
│   ├── bgp-established-traffic-broken.md
│   └── ai-gpu-network-design.md
└── labs/
    └── containerlab-evpn-vxlan/   # runnable EVPN-VXLAN fabric on FRRouting
        ├── topology.clab.yml
        ├── configs/
        ├── validate.sh
        └── README.md
```

## Technical deep dives

- [Troubleshooting a BGP session that won't establish](writeups/bgp-session-troubleshooting.md)
- [EVPN-VXLAN: from packet ingress to remote VTEP](writeups/evpn-vxlan-packet-journey.md)
- [How ECMP actually distributes traffic in a Clos network](writeups/ecmp-clos.md)
- [What happens when a spine switch fails?](writeups/spine-failure-convergence.md)
- [BGP is Established, but traffic is still broken](writeups/bgp-established-traffic-broken.md)
- [Designing networks for AI/GPU workloads](writeups/ai-gpu-network-design.md)
- [What actually happens inside an Internet Exchange Point](writeups/internet-exchange-point.md)

## Labs

- [EVPN-VXLAN leaf-spine fabric (Containerlab + FRRouting)](labs/containerlab-evpn-vxlan/README.md) —
  2 spines, 4 leaves, eBGP underlay + BGP-EVPN overlay, VXLAN data plane, with
  validation and failure tests.
