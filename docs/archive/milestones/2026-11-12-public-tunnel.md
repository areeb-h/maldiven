# PC hosting across different networks

Date: 2026-11-12. Launcher-only follow-up to Friends Lab 0.3.0.

The owner can host on a PC but the phone is not on that LAN. `tools/run_friends_server.py --public-address HOST:PORT` now separates the advertised endpoint from the local bind address/port. The game binds 127.0.0.1 and a separately configured free UDP forwarding agent relays remote connections. The public hostname resolves to IPv4 once for compatibility with the existing APK. No Godot scripts, phone protocol, DTLS checks or Android package changed. The old phone menu's same-Wi-Fi wording applies only to direct LAN mode.

See the [exact Windows/Playit instructions](../pc-server-and-phone.md#phone-on-mobile-data-or-another-wi-fi) and [ADR 0023](../adr/0023-public-udp-tunnel-invites.md). Both the tunnel agent and Godot server must stay running. No account/tunnel was provisioned automatically and no paid service was selected.

[Scoped evidence](evidence/public-tunnel-2026-11-12.json) records four endpoint/invite unit tests and 21 actual Godot Friends Lab integration checks passing on Linux with the pinned engine. The public-advertisement case proves the invite uses an external address while the real server binds loopback and still accepts certificate-checked local admission. It does not send traffic to its example public IP or prove a live Playit route. Earlier APK/87-check evidence remains historical for its recorded input fingerprint; it was not relabelled as a new complete test run.

Next physical check: start the free UDP agent on the owner's Windows PC, map it to 127.0.0.1:24567, run the launcher with the assigned public endpoint, and connect the phone from mobile data/another Wi-Fi using a fresh invite. Check movement/PTT and report actual latency and audio behaviour. Windows execution, third-party relay operation and phone audio remain unverified here.
