# Mobile experience, station art and audio production

Version 0.2. Proposed standards. Budgets are measured at the representative slice; no polygon count alone guarantees a frame rate.

## Input and comfort
The default game must be playable with two thumbs. Do not require movement, camera drag, jump, aim and held PTT at the same moment. Provide selectable PTT hold/toggle, optional proximity voice activation only with explicit microphone state, and pings for non-speaking participation. Start station traversal with ordinary walking, short auto-step and contextual vaulting; retain jump only if the map needs it.

A finger belongs to the control that captured it until release/cancellation. Entering a menu, losing focus or disconnecting clears motion, aim, interaction and transmit intent. UI touches cannot fire weapons or rotate the camera through the panel. Test four corner touches, drag across button boundaries, repeated touch cancellation, rotation/resize and notch-safe layouts.

Multiplayer pause is a local menu, not a paused authoritative room. Show that the round continues. Menu/background behaviour must explicitly choose microphone/transmit policy; backgrounding cannot leave a stuck PTT channel. The current island's get_tree().paused behaviour is not suitable as-is for multiplayer.

## Core screens and states
| Screen/state | Information | Actions |
| --- | --- | --- |
| Home | Join/create, supported version, settings | Enter a room code or create a private room |
| Joining | Room/version/connection progress | Cancel, retry, return |
| Hangar/lobby | Party, readiness, chosen preset, mic state | Voice check, kit practice, ready, leave |
| Briefing | Shared goal plus separately shown private role | Acknowledge, review controls |
| Round | Context action, tool/charges, public objective, transmit/damage state | Move, look, act, ping, communicate |
| Downed/recovering | Cause, remaining recovery, rescue availability | Ask for help/ping, understand bounded wait |
| Reconnecting | Connection state and grace countdown | Retry or leave; no fake active controls |
| Debrief | Outcome, factual timeline and optional role reveal | Discuss, rematch, change preset or leave |

Keep ordinary HUD quiet. Surface an action only when usable or explain why it is blocked. Never use desktop keyboard instructions as the mobile tutorial. Confirm irreversible lobby changes; avoid modal interruptions for routine play.

## Accessibility baseline
Sensitivity/inversion, low camera shake/head-bob preset, readable font scale, high-contrast prompts, colour-independent sector cues, separate speech/effects/music volumes and contextual pings. Important alarms have visual equivalents. A muted player can see objectives and contribute through tools/pings. Do not label that fallback as equivalent until mixed-speaking tests support it.

## Station visual identity
Stylised industrial space architecture: warm commons against cool service areas, functional silhouettes, restrained emissives and strong exterior views. Shared manufacturing language across equipment, doors and suits. The environment should look designed for people, with benches, handrails, storage and recognisable gathering points.

Sector colour is secondary to a name, icon, doorway shape and landmark. Emergency state alters lighting without erasing navigation. Window views provide orientation and spectacle; a painted star field is sufficient until dynamic external scenes have a gameplay purpose.

## Asset kit and production order
1. Metric reference: player silhouette, doorway, corridor intersection and carryable cell.
2. Greybox kit: straight/corner/T-junction floor/wall, bulkhead, two door variants and one window.
3. Social slice: commons plus adjoining corridor, a console, bench, storage and observation window.
4. Interaction kit: core cradle, cell/socket, cutter, medical case, radio and extraction controls.
5. Character pass: readable suit/helmet, locomotion, carry, operate, down/revive and emotes.
6. Hazard pass: warning lighting, restrained sparks, smoke/visibility limits and alarm feedback.
7. Expand sectors using validated modules, then add themed variations.

Each asset entry records ID/version, editable source, GLB, metre-scale bounds, front/up convention, material slots, triangle/vertex count, collision intent, LOD/shadow settings, provenance and reference screenshot. Simplified collision proxies are separate from decorative detail. Avoid detailed meshes that silently produce expensive per-triangle dynamic collision.

## Technical art acceptance
Verify normals, winding, scale/pivots, material appearance in the supported renderer, collision clearance, camera obstruction and shadow stability. Check transparent/overdraw-heavy effects on phones before multiplying them. Limit unique material permutations and establish measured instancing/visibility rules. A Blender render checks geometry/composition; an in-engine device capture checks the shipped result.

The available island generator was tested with Blender 4.3.2. Record the actual station tool version in its manifest and validate exports before adopting a newer art tool baseline. Keep source generation reproducible; do not describe generated resource files as a finished visual pipeline until import/device checks pass.

## Audio hierarchy
Speech first, actionable local cues second, ambience third. Test intelligibility while doors, alarms and weapons overlap. Use short sound identities for equipment, door refusal, power change, downing and extraction. Duck ambience under speech where supported and tested; do not hide meaningful cues completely.

A helmet/radio effect is optional presentation. It must not reduce accessibility or impersonate another player. No default microphone recording or voice-cloning feature. Native SDK echo/route behaviour is a feasibility gate, not something solved by adding sound effects.

## Performance budgets
At P1/P3 record supported device, OS, renderer, resolution scale, player count and thermal state. Measure CPU/GPU frame time, p95/p99 spikes, RAM growth, draw calls, visible geometry/materials, audio load, bandwidth and package/startup size. Assign asset/effect budgets from that measurement and retest the same camera route.

Baseline target remains sustained 30 FPS with a possible 60 FPS preset on tested devices. Profiles should prioritise shadow distance, effect density, visible clutter and resolution scale before sacrificing legibility or voice. The Android horizontal-band workaround remains pending validation on the affected phone.
