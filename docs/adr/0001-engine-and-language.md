# ADR 0001: Godot and typed GDScript

Date: 2026-11-12. Status: Proposed.

## Context
Maldiven is an Android-first, offline 3D roaming game with a compact handcrafted island. The user selected Godot. Fast iteration, reproducibility and a small dependency surface matter.

## Decision
Use Godot 4.7.2 stable Standard with matching export templates and typed GDScript. Use built-in Jolt, CharacterBody3D, SpringArm3D, AnimationPlayer and AnimationTree. Start with engine-native touch UI and InputMap. Evaluate physics interpolation with camera input latency in mind. Keep optional plugins out until justified.

## Consequences
One engine owns runtime, physics, UI and animation. Engine version upgrades require import, runtime and Android regression checks. C# and native extensions remain future options rather than initial requirements. The available local Godot 4.6.3 is not evidence of 4.7.2 validation.

## Sources
- https://godotengine.org/article/maintenance-release-godot-4-7-2/
- https://docs.godotengine.org/en/4.7/tutorials/physics/using_jolt_physics.html
- https://docs.godotengine.org/en/4.7/classes/class_springarm3d.html
