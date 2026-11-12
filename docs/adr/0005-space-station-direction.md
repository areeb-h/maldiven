# ADR 0005: Make the space-station social game the active direction

Date: 2026-11-12. Status: Accepted for product direction; detailed rules remain proposed.

## Context
The owner requested a more interesting space-based social game for friends, with voice, weapons and richer interaction, and then requested repository plans and a roadmap. The current implementation is the island resource prototype.

## Decision
Retain the Maldiven repository and Godot baseline. Use Drift Station as a provisional working title. Preserve the island source baseline on archive/island-v0.2.0 and its plan under docs/archive/. Make docs/plan.md the active station planning entry point. Do not rename package IDs, delete assets or implement station gameplay in this documentation change.

Target one map, six players and one infiltrator before validating eight players. Plan cooperation, proximity voice/radio, transferable equipment, rival extraction and recoverable conflict. See the game specification for proposed rules and the roadmap for gates.

## Alternatives
Continue island survival: does not match the new direction. Start a second repository: increases duplication before the new loop is proven. Build many ships/modes immediately: increases production cost before social mechanics are validated.

## Consequences
Movement, touch, camera and Android build tools may transfer; tropical art does not become station content automatically. Previous APKs remain island builds. No claim is made that the new design outperforms another game.

## Validation
Documentation links and scope consistency; owner review; P1 technical spike before content expansion.
