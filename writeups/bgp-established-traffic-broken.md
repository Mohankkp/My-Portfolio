# BGP is Established, but traffic is still broken

This is the failure that separates people who read `show bgp summary` from people who understand the data plane. The session is `Established`, prefixes are exchanged, and traffic still black-holes. The control plane and the data plane disagree — and BGP only tells you about the control plane.

## Work the layers the packet actually traverses

**1. Is the route in the FIB, not just the RIB?**
BGP installs into the RIB (control plane). Forwarding happens from the FIB (data plane, in hardware). They can diverge:
- A better route from another protocol won (lower admin distance).
- The route's **next hop is unresolved** — the classic iBGP trap: the prefix is valid but the BGP next-hop isn't reachable, so it never makes it to the FIB. Fix with `next-hop-self` or make the next-hop routable.
- Hardware table (TCAM) is full and the route silently didn't program.

Check: `show ip route <prefix>` **and** the hardware FIB, not just `show bgp`.

**2. Is it accepted but not best?**
The prefix is received but a policy or attribute makes another path win, and that other path is broken or points elsewhere. Look at `show bgp <prefix>` and read *why* the chosen path was chosen (local-pref, AS-path, MED, origin).

**3. Return path.**
Forwarding is per-direction. Your side has the route; does the *other* side have a route back? Asymmetric or missing return routing looks identical to a forward black hole from the sender. Test both directions.

**4. Next-hop reachability, recursively.**
BGP next hops resolve recursively through the IGP. If the IGP path to the next hop is down or points at a dead link, BGP still shows `Established` and the prefix still shows "valid" — but packets go nowhere.

**5. The plumbing under the route.**
- **MTU mismatch:** session is fine (small packets), but large packets drop. Very common with tunnels/VXLAN overhead. Small pings succeed, real traffic fails.
- **ACL / firewall** in the forwarding path dropping data even though :179 is permitted.
- **uRPF** dropping traffic whose source doesn't match the return route (ties back to asymmetry).

## A fast triage order

```
BGP Established?           yes
Route in RIB?              -> if no: policy / better route / max-prefix
Next hop resolvable?       -> if no: next-hop-self / IGP path
Route in hardware FIB?     -> if no: TCAM full / programming failure
Traffic one-way only?      -> return path / asymmetry / uRPF
Small ping ok, big fails?  -> MTU
```

## The takeaway

`Established` means "the two routers are talking," not "packets get there." When traffic breaks with a healthy session, stop looking at BGP and follow the packet: RIB → next-hop resolution → FIB → return path → MTU. The disagreement between what BGP advertises and what the hardware forwards is where these problems always live.
