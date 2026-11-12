# ADR 0004: Diagnose horizontal Android rendering corruption

Date: 2026-11-12. Status: Proposed, pending physical-device validation.

## Context
The first phone test showed two horizontal bands of corrupted 3D pixels. Similar corruption is documented in a confirmed upstream Godot issue: https://github.com/godotengine/godot/issues/115217 . Reported workarounds include MSAA and the Compatibility renderer. The exact cause on the user's device remains unconfirmed.

## Decision
Retain Mobile/Vulkan for the primary scene, enable 2x MSAA and provide a separate Compatibility build command/package for A/B testing. Use opaque, low-complexity material geometry while developing the first resource set. Keep the asset review distinct from claiming a renderer fix.

## Consequences
MSAA uses additional GPU bandwidth/memory and requires profiling. The Compatibility build can vary in lighting/tonemapping. The screenshot cannot prove a GPU/driver diagnosis. Acceptance requires the affected device to reproduce the original issue and then show whether it persists in the new Mobile and Compatibility variants.
