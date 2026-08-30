# Troubleshooting a BGP session that won't establish

A BGP session should reach `Established`. When it doesn't, the fix is almost never "restart BGP" — it's walking the stack from the bottom up and finding the exact layer that breaks. Here is the order I work in, because each layer depends on the one below it.

## The path to Established

```
Physical / link up
      |
Layer 3 reachability (can I even reach the peer IP?)
      |
TCP :179 handshake
      |
BGP OPEN (AS number, hold time, router-id)
      |
Capability negotiation (AFI/SAFI, 4-byte ASN, add-path)
      |
Route exchange
      |
Policy (import/export filters)
```

The state machine — `Idle → Connect → Active → OpenSent → OpenConfirm → Established` — is a map of that same path. *Where* a session is stuck tells you *which* layer to inspect.

## Reading the state

| Stuck in | Most likely cause |
|---|---|
| `Idle` | Session administratively down, or no route to peer. Check `show ip route <peer>`. |
| `Active` / `Connect` | TCP to :179 never completes — ACL, firewall, wrong peer IP, or the peer isn't listening. |
| `OpenSent` | OPEN sent, no valid OPEN back — AS mismatch, router-id conflict, or version issue. |
| `OpenConfirm` | Hold-time / keepalive mismatch, or one side resets. |
| `Established` but no routes | Not a session problem — see the policy section. |

## The checks, in order

**1. Layer 3 reachability.** `ping` the peer's BGP source address (respecting the update-source interface). For eBGP multihop, confirm the TTL and that a route to the peer exists. A surprising number of "BGP down" tickets are just a missing static route to the loopback.

**2. TCP :179.** If reachability is fine but the session sits in `Active`, prove the transport: `telnet <peer> 179` or a targeted capture. If SYNs leave and nothing returns, it's an ACL or control-plane policer, not BGP.

**3. The OPEN message.** Mismatched **remote AS**, a **duplicate router-id**, or an **update-source** that doesn't match the peer's `neighbor` statement all kill the OPEN exchange. A packet capture of the OPEN shows the advertised AS and hold time directly — faster than reading two configs side by side.

**4. Capabilities.** If both sides speak but the address family never comes up, the AFI/SAFI isn't negotiated on both ends (e.g. one side has `l2vpn evpn` activated, the other doesn't). 4-byte ASN and add-path mismatches show up here too.

**5. Policy.** Session `Established` with zero prefixes almost always means an import policy is dropping everything, no network/redistribute is originating routes, or a `max-prefix` limit tripped and shut the session down.

## The principle

Don't guess at the top of the stack. The session state names the layer; validate that layer with a capture or a reachability test before touching config. Most "mysterious" BGP problems are an ACL, a source-interface mismatch, or a policy that quietly drops everything — none of which are fixed by bouncing the neighbor.
