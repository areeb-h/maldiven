# ADR 0023: Public UDP tunnel addresses in PC-generated invites

Date: 2026-11-12. Status: Accepted for the Friends Lab launcher. External route validation pending.

## Context

The owner can host on a Windows PC, has a $0 hosting budget, and the Android phone uses a different network. The default launcher places the PC's private LAN address into invitations. The shipped 0.3.0 APK already accepts public IP literals and verifies the game server's certificate independently of the destination IP.

## Decision

Add `--public-address HOST:PORT` to the PC launcher. This mode binds Godot to loopback, resolves the supplied endpoint to a global IPv4 once, and puts the public IPv4/port into the existing invite format. The local listening port and advertised public port remain independent. Public-address mode is mutually exclusive with LAN binding and plain desktop-only mode.

The user configures a separate UDP forwarding agent on the same PC. Playit.gg currently lists free custom UDP tunnels with no credit card requirement. The guide uses one UDP allocation mapped to 127.0.0.1:24567, with no optional Proxy Protocol. The launcher does not provision the account/tunnel, require payment, or claim to validate its external reachability. Existing DTLS, ticket lifetime, admission authority and voice framing remain unchanged. The existing APK is retained; no WebSocket migration or cloud VM is required.

## Consequences and validation

Both PC processes must stay running. The relay adds a network dependency and latency; free service limits are outside this project's control. Recreate invitations after endpoint/DNS allocation changes. Reject malformed/non-public endpoints rather than silently falling back to LAN. Never put relay account credentials or game invitation tickets into console output.

Python tests cover hostname-to-IPv4 conversion, endpoint validation, DNS failure and invite compatibility. The actual Godot integration checks public advertisements with an unchanged loopback server and certificate-checked local admission. That test deliberately does not connect to the example public IP or establish a Playit tunnel. Physical PC-to-phone routing and voice quality remain owner tests.

## Sources

- https://playit.gg/login
- https://playit.gg/support/
- [PC setup guide](../pc-server-and-phone.md#phone-on-mobile-data-or-another-wi-fi)
