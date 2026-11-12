# ADR 0008: One modular station, topology before art expansion

Date: 2026-11-12. Status: Proposed. Supersedes ADR 0002's island world-authoring direction for active development.

## Context
A social map must create readable meetings, separation, alternate routes and evidence opportunities. Large environments, many decks and visual complexity increase mobile and production risk before the loop is known to work.

## Decision
One deck, eight named sectors and two connected routes, using the adjacency table in docs/game-design/drift-station.md as the source of truth. Start with an approximate 70 by 50 metre blockout; tune measured travel/encounter times. Use a reusable metric kit of floor/wall/corner/door/window/console/cargo parts exported as GLB, plus simple collision proxies and a consistent palette.

Provide at least two practical approaches to objectives, bounded manual hatch recovery and sector names/pictograms beyond colour. Doors change the room graph; test approved states for reachability. Keep player visibility/camera comfort distinct from audio membership rules.

Retain the rendering diagnostics from ADR 0004. Choose the supported Mobile/Compatibility presentation based on actual Android tests. Avoid high-end effects or a new terrain dependency for an indoor station. The existing island assets remain archived/reusable assets, not a station art solution.

## Alternatives and consequences
Procedural/multi-deck stations offer variety but complicate navigation, acoustics and testing. A handcrafted modular map makes iteration cheaper but needs replay variation through player decisions/object states. It does not guarantee a particular draw-call or battery budget.

## Gate
P3 cooperative rehearsal validates topology before polishing. P6 finishes one representative social/service area and profiles it before expanding. Verify camera collision, doors, sightlines, accessibility and alternative routes on phones.
