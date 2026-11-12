# Maldiven development plan

Status: proposed implementation plan; approved for repository commit. Date: 2026-11-12.

## Goal
An offline Android game where the player enjoys roaming a beautiful, compact tropical island. The first release focuses on movement, camera comfort, scenery and atmosphere.

## Initial scope
- Landscape third-person view; walk, run, jump and camera orbit.
- Simultaneous multi-touch joystick, camera drag and jump.
- Beach, village, palm grove, lookout, cove and jetty.
- Two connected exploration loops with shortcuts and visible landmarks.
- Fixed afternoon lighting, lightweight water, ambient sound and footsteps.
- Pause, sensitivity, audio, graphics settings and saved position.
- Safe spawn recovery and a clear deep-water boundary.

Combat, quests, crafting, multiplayer, swimming, complex interiors and settlement mechanics are deferred.

## Map proposal
Approximately 350 by 250 metres, adjusted after greybox testing. Coastal loop: arrival beach, village, jetty, cove, beach. Inland loop: village, palm grove, lookout, village. Walkable routes must connect without invisible barriers. The lighthouse is a navigation landmark initially.

## Milestones and exit criteria
1. Toolchain: pin engine and export templates; confirm import, startup and minimal Android export. Record actual installed versions.
2. Movement greybox: slopes, steps, walls and camera obstructions; responsive movement and simultaneous touch controls; pause/resume recovery.
3. Island greybox: complete both loops, validate travel times and shoreline boundaries, eliminate stuck locations.
4. Visual slice: polish beach-to-village route with representative vegetation, water, lighting, character animation and sound. Evaluate on the physical phone before extending art production.
5. Full roaming island: expand using validated modular assets and measured budgets; add settings and robust local saves.
6. APK delivery: verify installation, cold start, background/resume, saved-position recovery and sustained play. Deliver a signed test APK and source commit reference.

## Validation
Target stable 30 FPS first (33.3 ms); evaluate 60 FPS separately. Measure frame-time spikes, RAM, load time, package size and thermal behaviour after 10–15 minutes on the actual Android device. Desktop and headless checks do not establish mobile performance or visual quality. Derive mesh, material and draw-call budgets from the representative slice.

## Repository and build workflow
Text scenes, scripts and documentation in Git; large source art in Git LFS when introduced. Ignore .godot caches, builds, keystores and credentials. Record source and redistribution license for every external asset. Planned CI: pinned-engine import/parse/start checks, then Android export once the SDK and templates are configured. No CI, game scaffold or APK exists yet.

## Risks
Concept art exceeds demonstrated runtime quality; foliage/water overdraw; camera clipping; uneven touch behaviour; device-specific drivers; unverified asset/plugin licenses. Resolve these in the small visual slice before expanding the map.

## Next action
Install/verify the pinned engine and create the minimal movement project after committing these planning documents.
