# ADR 0015: Separate ambitious design from demonstrated release capability

Date: 2026-11-12. Status: Proposed. Extends ADR 0010.

## Context
The owner wants exceptional quality and ambitious capabilities. Documentation and automated checks can reduce mistakes, but native media, physical devices, group enjoyment and operations require distinct evidence.

## Decision
Use the full experience blueprint and implementation backlog for ambition; use R0–R4 evidence gates for shipping claims. Record what is proposed, implemented, automated-checked, device-checked and group-validated. Unknown capabilities become experiments with a concrete next test, rather than blanket impossibility assumptions or undocumented promises.

Require two-thumb mobile interaction, visible microphone state, meaningful participation and a supported renderer. Preserve independent device, voice, performance and human-session evaluation. Build a recoverable room/rollout policy; H1 room crashes interrupt/restart rather than pretending seamless recovery exists.

## Consequences
Strong ideas remain visible in later horizons while foundation tests focus implementation. Feature/code completion alone does not authorise claims of physical-device quality or broad superiority. A failed experiment should produce a diagnosis/alternative test before the owner makes a scope decision.

## Gate
Ready/done definitions, scenario acceptance and release rehearsals in docs/blueprint/verification-and-release.md. No provider spend, broader deployment or public release is performed by this documentation decision.
