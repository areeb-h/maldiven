# ADR 0020: Isolate the initial authenticated admission experiment

Date: 2026-11-12. Status: Accepted for the local NET-001 experiment; production transport/account decisions remain open. Implements a bounded part of ADR 0006.

## Context

The first online prerequisite is a real server/client connection that cannot select arbitrary identities or join an incompatible room. A production account service, encrypted internet route and native voice provider have not yet been selected/proven. The existing island baseline must remain independently testable.

## Decision

Use a standalone Godot 4.7.2 project, IPv4 loopback binding, SceneMultiplayer authentication and a finite server-owned opaque-ticket ledger. Crypto-generated random bytes supply tickets/epochs; no custom cryptographic algorithm or signed-token format is introduced. Local credential files are private and never logged/committed. Version/content/rules/room/epoch checks precede admission, with reserved identities and bounded timeout/cleanup. Disable object decoding and client relaying. Keep the experiment out of island exports.

The separate lab compatibility envelope does not implement the proposed gameplay-command schema. Its local issuer models an admission boundary without claiming persistent account authentication. A reused ticket stays consumed; a new local ticket can admit the same synthetic identity after disconnect, without implying match recovery.

## Alternatives and consequences

- Unrestricted self-named clients simplify a toy connection but do not test the identity boundary.
- A public account/hosting service adds provider, spending and encrypted-route decisions before the local gate is established.
- Integrating directly into island movement mixes gameplay/input state with the first lifecycle test. An isolated project lets the established baseline check for export regressions.

The local ledger is not the production credential architecture. It deliberately binds only to loopback. Move to a protected control/admission service and prove encrypted transport before any hosted internet scope. Real-phone voice and match reconnect/hidden-state authority remain separate gates.

## Validation

[Milestone evidence](../milestones/2026-11-12-network-admission.md) records 32 actual multi-process network checks and five island baseline checks for the same inputs. Unknown/expired/replayed credentials, incompatible versions, simultaneous identity claims, malformed packets, unfinished authentication and restart/shutdown are included. This is not an internet security audit or gameplay/voice validation.
