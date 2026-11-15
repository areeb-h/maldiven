# Drift Station: look and feel

Updated 2026-11-15. A research-backed target for UI, game feel and rendering on Godot 4.7.2 with the Mobile renderer. It complements `design.md` (rules) and the art pass in `scripts/art/`. Numbers are starting values. Tune them on a real mid-range Android phone, not in the editor.

## 1. North star

- **Readable stylised realism.** Chunky sci-fi industrial forms, PBR surfaces kept simple, with lighting doing the heavy lifting. A player must be able to read a crewmate, a cell or the core in under 200 ms, even in a blackout.
- **Three cinematic lighting states**, each instantly recognisable from a thumbnail: *Emergency* (red-orange swell, haze, beacons), *Restored* (cool white, clean, glowing trim), *Blackout* (near-black, floor guide strips, flashlight cones).
- **The station tells you what happened.** Light waves, alarms, sockets lighting up and signage carry the news, and the HUD confirms it.
- **Crisp, minimal HUD.** Glass panels, one accent colour, big contextual thumb buttons, centre of screen kept clear. Nothing on screen that the player can't act on.
- **Physical, funny, tactile.** Every shove, pickup and socket insert has a sound, a little motion, a light change and (on phones) a buzz. Friends should laugh at the physics before they argue about the traitor.
- **Smooth before pretty.** A locked 60 fps on a mid-range 2022 phone beats any effect. Every effect below has a budget.

## 2. What the best games do

| Game | Technique | Why it works | How we apply it |
|---|---|---|---|
| Call of Duty Mobile | Custom HUD: drag, resize and set the opacity of every control; swap sides ([Activision](https://blog.activision.com/call-of-duty/2019-10/Getting-a-Grip-on-the-Call-of-Duty-Mobile-Controls)) | Hands and phones differ, so one layout never fits all | Ship three presets (Default, Left-handed, Compact), plus HUD scale and opacity sliders. Full drag editor later |
| Fortnite Mobile | Auto Fire and Easy Interact; "prioritise contextual actions over explicit inputs" ([Epic guide](https://www.fortnite.com/news/getting-started---fortnite-for-mobile), [UEFN mobile design](https://dev.epicgames.com/documentation/fortnite/designing-for-mobile-in-fortnite)) | Fewer buttons means fewer mis-taps and a lower skill floor | One large USE button whose verb and icon change (PICK UP / INSERT / LOAD / ARM / PULL OUT). Also allow tapping the outlined object in the world |
| PUBG Mobile | Auto-pickup and an auto-sprint icon that appears at full stick ([PocketGamer](https://www.pocketgamer.com/playerunknowns-battlegrounds/pubg-for-mobile-cheats-and-tips-essential-tips-to-master-touch-screen-controls)) | Removes busywork inputs and shows the state they produce | Run when the stick is past 0.8 (exists). Add a visible run chevron on the stick ring, plus a run lock when dragged past 1.15× radius |
| Valorant | Clarity-first shading: a custom diffuse ramp, painted highlights, and agent outline and fresnel kept on by default ([Riot tech blog](https://technology.riotgames.com/node/110), [fresnel option](https://dotesports.com/valorant/news/how-to-hide-agent-outlines-in-valorant)) | Characters separate from the environment at any brightness | A fresnel rim emission on crew suits, plus a value gap: walls mid-dark, suits brighter and saturated |
| Overwatch | Silhouette-first heroes; skins must not change the silhouette ([GDC art direction](https://gamedeveloper.com/art/video-defining-and-evolving-the-art-direction-of-i-overwatch-i-), [Blizzard](https://overwatch.blizzard.com/en-gb/news/23537427)) | Shape reads before colour and texture | Carried items change the silhouette (a cell on the back, the core held up and glowing). No cosmetic may hide them |
| Dead Space | Diegetic UI: health on the spine, a holographic locator ([GDC talk](https://gamedeveloper.com/design/video-designing-i-dead-space-i-s-immersive-user-interface)) | Eyes stay in the world, and the over-the-shoulder camera always sees the back | Reactor sockets show 0–3 lit rings, vault and pod screens show state, and the carried cell's light strip is the carrier's "UI" |
| Alien: Isolation | A "haunted house in space": lights and sound react to events and sell the dread ([GDC](https://gdcvault.com/play/1021852/Building-Fear-in-Alien), [lighting tech](https://www.dsogaming.com/news/alien-isolations-engine-supports-up-to-a-million-particles-via-computer-shaders/)) | The environment's state *is* the tension | Emergency swell (exists), rotating beacons, steam vents, flicker before a blackout, and a light wave on restore |
| Returnal | Critical info in the centre, minor info at the edges; low health layered across visuals, audio, haptics and VO; lean menus ([PlayStation Blog](https://blog.playstation.com/?p=348960), [GDC 2022](https://www.gamedeveloper.com/marketing/a-third-person-action-roguelike-bullet-hell-arcade-thriller-the-making-of-returnal)) | Redundant channels land even when the eyes are busy | Pod armed = centre countdown, red vignette, siren, heartbeat haptic and room beacons, all at once |
| Hades | Telegraphs and impact frames; FX and UI built by the same artist for consistency ([80.lv](https://80.lv/articles/a-behind-the-scenes-look-at-the-effects-in-hades)) | Clear cause and effect makes even chaos feel fair | A shove has a 90 ms wind-up flash, hit-stop on contact, and a victim stagger with a ring |
| Lethal Company | Proximity voice that cuts out at distance and on death; a degraded walkie ([Prima](https://primagames.com/featured/how-did-lethal-company-become-so-popular)) | Audio distance creates stories and paranoia | When voice ships: muffle through walls, add radio crackle during blackout, and the dead go silent |
| R.E.P.O. | Physics-heavy carrying of fragile and heavy loot ([Outsider Gaming](https://outsidergaming.com/repo-co-op-horror-game-like-lethal-company/)) | Clumsy physics makes for funny, retellable moments | The core sways when carried, a shove knocks a carried item loose in a visible arc, and items bounce with a sound |
| Project Winter | Proximity voice; events pull players together instead of forced meetings ([MassivelyOP](https://massivelyop.com/2021/03/22/fight-or-kite-project-winter-plays-like-among-us-mixed-with-survival-mechanics-for-a-unique-experience/)) | Natural gathering moments without a vote UI | Blackouts and countdowns are gathering events. Signal them across the whole station with light and sound |
| Destiny | Cursor "stickiness": the cursor slows over targets and the target stands out ([Game Developer](https://gamedeveloper.com/design/what-to-steal-from-destiny-s-ui)) | Forgives imprecise input | USE target selection is sticky: keep the current target until another is 25 % closer or more centred, and outline it |
| Genshin Impact / PlatinumGames | Metaphor-led menus; full-screen transitions slightly longer in than out ([PocketGamer.biz](https://www.pocketgamer.biz/the-magic-that-makes-mobile-ui-look-good-and-feel-great), [PlatinumGames](https://www.platinumgames.com/official-blog/article/13949)) | Polish reads as "expensive"; fast exits respect the player | Panels enter in 280 ms and exit in 180 ms. The station hologram is the menu metaphor |

## 3. HUD and touch-control rules

**Scale reference.** The project runs at 1280×720 logical with `canvas_items` / `expand`. In landscape on a 6.1–6.7" phone, the 720 logical px span about 65–70 mm, so **1 logical px ≈ 0.09–0.10 mm**. Android's 48 dp minimum ([Android a11y](https://developer.android.com/guide/topics/ui/accessibility/apps)) is about 7.6 mm, or **≈ 80 logical px**.

| Rule | Value |
|---|---|
| Minimum touch target (hit area) | 88 px diameter (≈ 8.5 mm). Visual size may be smaller; pad the hit radius by +12 px (exists) |
| Primary action (USE) | Visual 140–150 px diameter, hit radius 82 px |
| Secondary (SHOVE, BLACKOUT) | Visual 100–104 px, hit radius 64 px |
| Tertiary (JUMP, pause) | Visual 88–96 px. Pause 80×56 visual, 96×72 hit |
| Gap between targets | ≥ 16 px edge to edge (Google asks for ≥ 8 dp ≈ 13 px; [Scanner](https://support.google.com/accessibility/android/answer/7101858)) |
| Right-thumb comfort arc | 290–430 px radius from the bottom-right corner (27.5–41.3 mm comfort radius, [arXiv study](https://arxiv.org/pdf/2110.08753)). Most-used action at the resting point ≈ (W−200, H−150) |
| Placement (from bottom-right) | USE (200,150) · SHOVE (110,270) · JUMP (90,80) · BLACKOUT (330,320). This keeps BLACKOUT away from USE so it can't be fired by accident |
| Floating stick | Spawns where the left thumb lands, inside x 32 px → 42 % of W and y > 35 % of H. Travel radius 72 px, dead zone 0.12, run ≥ 0.8. Leave the stick in the last place used (not a fixed corner) for 1.5 s after release |
| Edge exclusion | No touch zone starts within 24 px of the left or right edge, because Android's back gesture lives there |
| Safe area | Read `DisplayServer.get_display_safe_area()` and `get_display_cutouts()` on start and on resize, then convert to logical px. Margins = max(inset, 24 px) at the sides, 16 px top, 20 px bottom |
| Opacity | Idle control fill 0.35–0.45 α, ring 0.55 α. Enabled or contextual: fill 0.55, ring 1.0. Pressed: fill +0.25 lightness, scale 0.94. Disabled: 0.25 α. HUD glass panels 0.55–0.65 α. Never fade controls automatically |
| Cooldown display | A clockwise ring sweep from 12 o'clock (exists). Show integer seconds in the button while > 1.5 s remain. On ready: ring flash, scale 1.0 → 1.12 → 1.0 over 150 ms, and a 10 ms haptic |
| Dangerous verbs | BLACKOUT is **hold to fire, 300 ms** (the ring fills). One accidental tap would expose the infiltrator |
| Feedback timing | Visual response on touch-down within the same frame (≤ 16 ms). Sound ≤ 50 ms. Show networked outcomes optimistically (swing, animation) immediately, and confirm the impact when the host says so (≤ 120 ms feels instant) |
| Look sensitivity | Default 1.2 (exists). Expose 0.5–3.0, plus a separate vertical multiplier and an invert-Y toggle |

**Information hierarchy** (the Returnal rule: critical in the centre, the rest at the edges):

| Tier | What | Where | Behaviour |
|---|---|---|---|
| P0 interrupt | Pod or shuttle countdown, pod-armed alarm | Centre, upper third (y ≈ 0.3 H) so it never sits under a thumb | 84 px digits, pulses once per second, red vignette + siren + haptic. Never more than one at a time |
| P1 always on | Objective + progress ("POWER 2/3") | Top-left glass panel | Updates with a 200 ms count-up tween and an amber flash on change |
| P1 always on | Round timer | Top-centre pill | Turns DANGER below 60 s (exists). Below 30 s, a 1 Hz scale pulse of 1.0 → 1.06 |
| P1 private | Role | Top-left chip, **icon only by default**. Press and hold to show the word | Friends play in the same room, so a big red "INFILTRATOR" chip is visible over a shoulder |
| P2 transient | Alerts ("CELL INSERTED · REACTOR", "LIGHTS OUT") | Below the timer | 3.0 s hold, 250 ms fade. Queue of at most 2, ordered by priority (pod > abort > power > blackout > info) |
| P3 contextual | USE verb | On the button and as a small world-space chip above the target | Changes with a 120 ms cross-fade, never a jump-cut |
| P4 help | Hints | Bottom-centre, 0.55 α | Gone after the first touch (exists) |

Keep the screen's central 50 % × 50 % free of permanent UI.

## 4. Menu and flow UX

**Motion tokens.** These approximate Material 3 emphasised easing ([M3 tokens via Flutter](https://api.flutter.dev/flutter/material/Easing-class.html)). Put them in one `UiMotion` helper next to `UiStyle`.

| Token | Duration | Godot Tween |
|---|---|---|
| press | 70 ms down, 120 ms up | `TRANS_QUAD, EASE_OUT`, scale 0.94 |
| enter (panel or card) | 280 ms, offset +24 px, α 0 → 1 | `TRANS_QUINT, EASE_OUT` |
| exit | 180 ms, −12 px, α → 0 | `TRANS_CUBIC, EASE_IN` |
| pop (stamp, badge) | 220 ms, scale 1.25 → 1.0 | `TRANS_BACK, EASE_OUT` |
| screen change | 380 ms cross-fade, with the outgoing screen starting 60 ms earlier | `TRANS_SINE, EASE_IN_OUT` |
| stagger | 40 ms per item, capped at 6 items (240 ms total) | `tween.set_parallel()` + `tween_interval` |
| number count-up | 300 ms | `TRANS_EXPO, EASE_OUT` |

**Flow.**

1. **Home.** The live 3D orbit backdrop (exists) slowly cycles the three lighting states every 12 s, so the menu shows off the game. Title, then two big primary CTAs (HOST, JOIN), with secondary actions below. The name persists (exists). Also persist the last host or code and offer "Rejoin". Buttons stagger in 40 ms apart after the title lands.
2. **Lobby.** Player rows slide in from the left as they join (enter token), each with a suit swatch **and** an emblem shape (see §7), a name and a ping dot. A leaving player's row collapses over 180 ms. The host's START button stays disabled with a reason ("Need 2+ players"), never hidden. The invite code has a copy button and a 600 ms "Copied" toast. Sounds: join = soft rising blip, leave = falling blip.
3. **Role reveal** (6 s briefing):
   - 0–0.4 s: the HUD dims to 0.6 and a low boom plays.
   - 0.4–1.0 s: the caption "YOUR ROLE" appears.
   - 1.0–1.3 s: the card flips (scale.x 0 → 1, `TRANS_BACK`) with a role-colour wash and icon.
   - 1.3–4.5 s: the objective lines stagger in 120 ms apart.
   - 4.5–6.0 s: a 3-2-1 count, then the card flies to the role-chip position (400 ms, `TRANS_QUINT EASE_IN_OUT`). This teaches where the role lives.
   - **The sound and haptic must be identical for both roles**, because phones in one room are audible. Offer "hold to reveal" for players who want to hide their screen.
4. **Round.** On start, the HUD elements enter from their own edges (top panels slide down 16 px, buttons rise 24 px), staggered 0/60/120 ms. Pause opens a sheet in 220 ms with a blurred dim (use a static `ColorRect` dim; skip a blur shader on Mobile).
5. **Results.** First the world camera holds and orbits the decisive moment (the shuttle or pod launch) for 1.2 s while the music stings (`win_crew` / `win_infiltrator` exist). Then the card enters, and the title stamps in with the pop token. "The infiltrator was …" reveals their suit and emblem with a 300 ms delay. The timeline rows stagger in 60 ms apart. **Buttons appear only after 1.5 s** to prevent accidental skips.
6. **Rematch.** The host sees PLAY AGAIN as the primary button. Others see "Waiting for host…" with a pulsing dot, plus LEAVE. Return to the same lobby with the same order and settings.

**Loading and hitches.** Never show a blank frame. Show a progress line plus the station hologram while `station_builder` runs. Enable `shader_baker/enabled=true` in the Android export preset (4.5+) so first-use shader compiles don't stutter on the first blackout or alarm. Also pre-warm the effects (spawn each particle and material once, off-screen, during the briefing).

**Error states.** Plain sentences with one action: "Lost connection to Sam's game. Retrying in 3… [Leave]". Auto-retry 3 times with backoff before returning Home. The message slot already exists in `_show_home(message)`.

**Persistence.** Store `user://settings.cfg` (ConfigFile): name, last address, look sensitivity, HUD scale (80–130 %), control opacity, layout preset, shake (0–100 %), haptics on/off, colour preset, quality tier.

## 5. Juice and feedback catalogue

Never touch `Engine.time_scale`, because the game is networked. All slow-mo and hit-stop below are local and visual-only. Every effect respects the shake and haptics settings.

| # | Item | Parameters |
|---|---|---|
| 1 | Trauma-based camera shake ([Eiserloh, GDC 2016](https://gdcvault.com/play/1023146/Math-for-Game-Programmers-Juicing)) | `trauma` 0–1, shake = trauma². Max offsets yaw/pitch 2.0°, roll 1.2°, translation 0.06 m. Noise at 18 Hz, decay 1.4/s. Shoved +0.45, shoving +0.15, alarm start +0.25, launch +0.6. Hard cap 0.8 |
| 2 | Hit-stop on shove contact | Freeze both avatars' animation and the attacker's camera for 70 ms (local), then release with an 8 % overshoot |
| 3 | Shove read | 90 ms wind-up arm flash (an additive arc quad), contact ring (scales 0.3 → 1.6 m over 250 ms, α 1 → 0), victim knockback with a 0.35 s stagger and a name-tag wobble |
| 4 | Haptics (`Input.vibrate_handheld(ms, amplitude)`) | Shoved 90 ms @1.0. Landed shove 40 ms @0.6. Pickup 15 ms @0.3. Cell insert 30 ms, gap 60, 30 ms. Countdown last 5 s: 20 ms per tick. Pod armed: heartbeat 2×35 ms each second. **Add `permissions/vibrate=true` to the Android preset**; without it the call does nothing. Many phones ignore amplitude, so keep the patterns distinct by duration |
| 5 | Interactable outline | Current USE target only: `stencil_mode = STENCIL_MODE_OUTLINE`, `stencil_color = ACCENT`, `stencil_outline_thickness` 0.02 ± 0.006 at 2 Hz. Fallback: a `next_pass` material with `grow` and `CULL_FRONT` |
| 6 | Item idle glow | Cells and the core pulse emission 0.7 ↔ 1.0 at 0.8 Hz, with a slow spin (exists for the core) and a 4 cm bob |
| 7 | Pickup tween | The item flies to `carry_point` in 180 ms (`TRANS_BACK EASE_OUT`), scale 1 → 1.15 → 1. Pickup sound (exists) and a 15 ms haptic |
| 8 | Socket insert | Snap in 120 ms, then the socket ring light ramps to full in 300 ms with a reactor "thunk", and the progress count-up tweens |
| 9 | Power-restored light wave | On the third cell, lights come on room by room from the Reactor at 25 m/s. Each room flickers twice (60 ms on, 80 ms off), then holds on, with a spatial "clunk" per room. Ceiling strips use a `wave_origin` / `wave_radius` shader uniform for a chase edge. The `ArtStationFX` state tween becomes per-room delays |
| 10 | Blackout flicker | Three flickers over 0.6 s (on 70, off 90, on 40, off 120, on 30), then off with a 120 ms tail. Ambience low-pass ramps to 800 Hz over 0.4 s. Floor guide strips stay on (exists). Restore = reverse, plus a hum swell |
| 11 | Countdown pulse | Each second: scale 1.0 → 1.18 → 1.0 (`TRANS_BACK`, 260 ms), tick sound (exists). Last 5 s: digits switch to DANGER, vignette radius tightens 10 % and haptic ticks. At 0: a white flash at 0.25 α for 120 ms |
| 12 | Vignette states | Calm 0.55 α edge. Blackout: a cold tint, 0.7 α. Pod armed: red pulse at 1.6 Hz (exists, `sin(t*6)` ≈ 0.95 Hz; raise to ~10 rad/s for urgency) |
| 13 | Run FOV kick | FOV 70 → 76 over 250 ms (`EASE_OUT`) when running, back over 350 ms. Shove landed: −3° punch over 80 ms |
| 14 | Footstep dust | One `GPUParticles3D` per avatar, `emit_particle()` on each footstep while running: 6 particles, life 0.5 s, upward speed 0.4 m/s. Disabled beyond 12 m and in blackout |
| 15 | Landing squash | Jump land: avatar visual scale y 0.88, xz 1.06 for 90 ms, then a spring back. Dust puff of 10 particles |
| 16 | Carried-core sway | The core lags the carry point by a spring (k 60, damping 9) and swings on turns. The carrier's flashlight is tinted cyan |
| 17 | Knock-loose arc | A shove on a carrier ejects the item on a ballistic arc (2.5 m/s up, 3 m/s away) with a spin, a clatter sound and a bounce |
| 18 | Alarm beacons | When the pod is armed: rotating beacon meshes (an emissive "cone" with a UV scroll) in every corridor, at 0.8 rev/s. Emissive only, no extra lights |
| 19 | Button ready flash | When a cooldown ends: ring flash, pop token, 10 ms haptic (see §3) |
| 20 | Alert banner entrance | Slides down 16 px over 220 ms, with the accent bar growing from 0 → 6 px wide. Kind-specific sound |
| 21 | Ambient life | Steam puffs at 2–3 vents per room (GPUParticles3D, 12 particles), one dying, flickering panel per corridor, and slow dust motes in light cones |
| 22 | Result stamp | Title pop, a camera orbit at 12°/s and a confetti-like spark burst in the winner's colour (40 particles, one shot) |

## 6. Graphics recipe for the Godot Mobile renderer

**Know the limits.** These are checked against the 4.7 [renderers table](https://docs.godotengine.org/en/4.7/tutorials/rendering/renderers.html) and the 4.7.2 class reference.

- The colour buffer is **RGB10A2, a medium dynamic range that tops out at 2.0**. Mobile glow needs `glow_hdr_threshold` ≈ 0.9 and `glow_intensity` ≈ 1.5 (Environment docs).
- **8 OmniLights + 8 SpotLights per mesh, 256 of each per view.** Also 8 reflection probes per mesh and 8 decals per surface.
- No SSAO, SSR, SSIL, SDFGI, VoxelGI, volumetric fog, TAA or FSR2.
- Supported: FSR1, MSAA, FXAA, SMAA, debanding, DoF, light projectors, PCSS on omni and spot lights, stencil, CompositorEffects and LightmapGI (rendering only).

**Settings.** Most of these live in `station_builder.gd` `_build_environment` and `ArtStationFX.STATES`.

| Area | Recommendation |
|---|---|
| Tonemap | Try `TONE_MAPPER_AGX` with `tonemap_agx_contrast` 1.2–1.3. It keeps the hue of saturated red, amber and cyan emissives as they brighten ([env docs](https://docs.godotengine.org/en/4.7/tutorials/3d/environment_and_post_processing.html)), and that hue is our whole identity. On Mobile without HDR 2D, Godot forces the AgX white point to 2.0. If you stay on ACES, drop `tonemap_white` from 6.0 to **2.0–3.0**: values above 2.0 never reach the tonemapper on Mobile, so a white point of 6 leaves highlights grey. A/B both on device |
| Exposure | Per state (exists). Emergency 1.05, Restored 1.0, Blackout 1.1. Blackout is made dark by the lights, not by exposure |
| Glow | `glow_intensity` **1.2–1.5** (now 0.75–0.9), `glow_hdr_threshold` 0.9, `glow_strength` 1.1, `glow_bloom` 0.0–0.02, levels 2–5 at 1.0/0.8/0.6/0.4, `GLOW_BLEND_MODE_SCREEN` or `SOFTLIGHT`. Add `glow_map` (procedural lens-dirt noise, `glow_map_strength` 0.4) for a cheap "camera" feel |
| Emissive values | On Mobile, **energy × channel saturates at 2.0**. Trim at 2.6 vs 3.2, or the reactor at 5.0, are indistinguishable. Separate the states by colour, area, flicker and on/off, not by energy above about 2 |
| Banding | `rendering/anti_aliasing/quality/use_debanding = true`. Dark gradients in RGB10A2 band badly, and it's cheap |
| Colour grading | `adjustment_enabled` (exists, contrast 1.08, saturation 1.12). Add a per-state `adjustment_color_correction`: a 32³ `ImageTexture3D` LUT generated in GDScript at startup (teal shadows, warm highlights; red-lifted shadows in Emergency, blue-crushed in Blackout). Swap it at the midpoint of the state tween, hidden by the flicker |
| Fog | Depth fog per state: Emergency `fog_light_color` (0.25, 0.07, 0.05), `fog_density` 0.012. Restored (0.08, 0.1, 0.14), 0.005. Blackout (0.01, 0.015, 0.03), 0.02. Add low height haze: `fog_height` 0.4, `fog_height_density` 0.25. Haze is what makes emissive strips look volumetric |
| Fake light shafts | Additive unshaded cone meshes under ceiling fixtures and beacons. Use fresnel edge fade, `proximity_fade_enabled` (0.5 m) to soften floor intersections, and `depth_draw_never`. 2–4 per room. Dust-mote particles (20 per cone) inside them |
| Reflection probes | One per room (exists, `UPDATE_ONCE` plus refresh on state change). Set `interior = true`, plus `ambient_mode = AMBIENT_COLOR` with a per-room `ambient_color` tint (energy 0.3–0.6). This is free per-room colour variety. `reflection_size.mobile` = 128 (default) is fine |
| Light budget | One shadowless omni per room plus long corridors (exists). Keep ≤ 6 lights touching any merged room or corridor mesh, leaving headroom for flashlights and the carried-core light. Split corridor meshes longer than 20 m. Room lights: `distance_fade_enabled`, begin 28 m, length 8 m. `light_specular` 0.3–0.6 |
| Shadows | Sun: 2 splits, 40 m (exists). Indoors, consider `directional_shadow_max_distance` 25 m. **One shadowed SpotLight: the local player's flashlight during blackout** (`shadow_enabled`, atlas 2048 mobile default). Remote flashlights stay shadowless with `distance_fade` |
| Character grounding | Shadowless omnis make characters float. Give each avatar a **blob shadow quad** (unshaded, multiply, radial texture, 1.1 m), not a `Decal`. Eight players plus three grime decals would blow the 8-decals-per-surface limit on a room's single floor mesh |
| Character rim | In the suit shader: `float f = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0); EMISSION += suit * f * rim;`. `rim` 0.35 in Restored and Emergency, 0.15 in Blackout (keep the tension), 0.6 inside a flashlight cone. Keep walls darker in value than suits (Valorant's rule) |
| Interactable outline | `BaseMaterial3D.stencil_mode = STENCIL_MODE_OUTLINE` (4.5+, [release notes](https://godotengine.org/releases/4.5/)) on the current USE target only. Verify on an Adreno and a Mali device; fall back to the `grow` + `CULL_FRONT` `next_pass` hull |
| AO without SSAO | (1) **Procedural vertex-colour AO in `ArtMeshKit`**: × 0.6 on vertices within 0.3 m of a floor–wall or wall–ceiling joint, × 0.75 under consoles. It fits the box-built geometry and works in every power state. (2) Make sure `texture_gen` writes real AO into the ORM's R channel. (3) Long, thin dark "base grime" decals along wall bases (within the decal budget). (4) Blob shadows |
| LightmapGI | **It cannot bake headless.** In 4.7.2, `LightmapGI` exposes no `bake()` method. The class docs say baking is editor-only and unsuited to procedural levels ([LightmapGI docs](https://docs.godotengine.org/en/4.7/classes/class_lightmapgi.html), [forum, 4.5.1](https://forum.godotengine.org/t/is-it-possible-to-bake-lightmapgi-node-using-headless-godot-editor/129607)), and baking needs a GPU. Our station is built at runtime, so lightmaps would require an `@tool` EditorScript that builds the station into a saved `.tscn`, `ArrayMesh.lightmap_unwrap()` for UV2, `gi_mode = STATIC`, and then a person clicking *Bake Lightmaps*, repeated for every layout change. Three power states would need three `LightmapGIData` swapped via `light_data`, or a neutral bounce/AO-only bake. **Defer**: vertex AO plus probes gets about 70 % of the look at none of the pipeline cost |
| Anti-aliasing | Keep `msaa_3d` 2× (exists; the docs say 2× "may be usable", higher is unlikely on mobile). No TAA or FSR2 on Mobile. Low tier: MSAA off + FXAA |
| Resolution | `rendering/scaling_3d/mode` = FSR (1.0), `scale` 0.77 on 1080p-class phones, `fsr_sharpness` 0.3. The HUD stays native. Add simple dynamic resolution: average the GPU frame time over 2 s, step the scale ±0.05 within 0.6–1.0, with hysteresis |
| Quality tiers | Low: scale 0.6, no MSAA, FXAA, glow levels 2–3 only, no particles beyond 8 m, no flashlight shadow. Medium (default): above. High: scale 0.9–1.0, MSAA 2×, bicubic glow upscale |
| Frame rate | `Engine.max_fps = 60`, plus a 30 fps battery option. Enable `shader_baker/enabled` (§4) |
| Textures | 512² for most tiling sets, 1024² for floors and hero props, 256² for decals. ASTC is already on (`import_etc2_astc`). Mipmaps on, default anisotropic 4× |
| Draw calls and triangles | Target ≤ 400 draw calls and ≤ 300 k visible triangles on mid-range. Watch `Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME`. Merged per-room meshes (exists) are right. Use `MultiMeshInstance3D` for repeated props (crates, bolts, cable clamps), `visibility_range_end` 22 m on small props, and `cast_shadow` off for anything smaller than 0.5 m |
| Avoid | Transparency stacked over haze cones, screen-reading shaders (an extra copy on tile GPUs), per-frame `ReflectionProbe` updates (only during the 0.35 s refresh, as now), and more than 3 full-screen `ColorRect` overlays |

## 7. Accessibility

**Palette check.** These are simulated with the Machado 2009 matrices (severity 1.0, linear RGB) and measured as CIELAB ΔE. Pairs below about 30 are risky for small HUD elements.

| Pair | Normal | Protan | Deutan | Tritan | Verdict |
|---|---|---|---|---|---|
| CREW #5ab0ff vs INFILTRATOR #ff4d5e | 104 | 62 | 88 | 127 | OK. Under protanopia red becomes a dark olive (#7e775d) and loses its "danger" read |
| CREW #5ab0ff vs ACCENT #5fd4ff | 26 | 19 | 19 | 12 | **Fails for everyone.** The crew chip reads as generic UI |
| INFILTRATOR vs AMBER #ffb547 | 64 | 55 | **32** | 53 | Pod alert vs blackout alert collide under deuteranopia |
| INFILTRATOR vs GOOD #6dffb0 | 128 | 48 | **29** | 140 | "Power online" vs "pod armed" collide under deuteranopia |

**Fixes, checked with the same tool:**

- CREW → **#4d8dff**. Contrast with the accent becomes 53, 39, 38 and 24 ΔE (normal, protan, deutan, tritan), and 5.9:1 on the panel.
- AMBER → **#ffe14d**. Against infiltrator red: deutan 43, protan 73.
- GOOD → **#5ff0e0**. Against red: deutan 49, protan 43. It sits close to the accent under tritanopia, so it always carries a ✓ or bolt icon.
- Keep INFILTRATOR #ff4d5e (5.8:1 on #0b1220) and pair it with a hazard-stripe chip border.

**Suit palette** (`net.gd` `PALETTE`, 8 colours). Hue alone can't separate 8 players under colour blindness:

- deutan: red–green ΔE 9.5, blue–purple 5.5, yellow–orange 14
- protan: blue–purple 10, green–orange 13, teal–white 11

Give every suit a **back and visor emblem** (circle, triangle, square, diamond, star, cross, ring, bar) and show it beside the name tag, in the lobby row and in the results timeline. This follows "no essential information by colour alone" ([GAG](https://gameaccessibilityguidelines.com/ensure-no-essential-information-is-conveyed-by-a-fixed-colour-alone/)). Later, add a colour-preset option (Deuteranopia / Protanopia / Tritanopia) that remaps only the UI tokens.

**Redundant cues:**

- Every role, state and alert has **icon + colour + word**: crew = chevron shield, infiltrator = slashed triangle, power = bolt, pod = warning triangle, blackout = crossed bulb.
- Countdowns are two different shapes as well as colours: shuttle = upward chevrons, pod = hazard frame.
- Every audio cue has a visual twin, and every critical visual has an audio twin. Plan captions for voice and VO lines.

**Text.** Xbox guidance is 26 px at 1080p on console, and 14 px minimum / 18 px recommended at 1080p on handhelds ([XAG 101](https://learn.microsoft.com/en-us/gaming/accessibility/xbox-accessibility-guidelines/101)). Phones are smaller and Rajdhani is condensed, so at 720p logical use:

- body ≥ 22 px
- labels and buttons ≥ 20 px
- critical alerts ≥ 24 px Orbitron
- nothing below 18 px

The HUD-scale slider (80–130 %) multiplies all of these. Keep text contrast ≥ 4.5:1 on the glass (TEXT #e8f1ff on the panel ≈ 16:1). Keep the 6–12 px dark outline on any text over the 3D world (exists).

**Motion and input.** Settings for shake 0–100 %, flashes (cap full-screen flashes at 0.25 α and ≤ 3 per second), haptics, left-handed layout, hold-vs-toggle run, and hold-to-fire versus tap for BLACKOUT.

## 8. Prioritised backlog

Effort: S ≤ 1 day, M 2–4 days, L 1+ week.

| # | Item | Tag | Impact | Effort |
|---|---|---|---|---|
| 1 | Mobile HDR fix: AgX (or ACES with white 2–3), glow intensity 1.2–1.5 / threshold 0.9, debanding on, emissive values re-tuned below 2.0 | Rendering | High | S |
| 2 | Character readability: fresnel rim emission on suits + blob shadow quads | Rendering | High | S |
| 3 | Contextual USE upgrade: stencil outline on the target, sticky targeting, verb + icon cross-fade, pickup and insert tweens | UI / Feel | High | S |
| 4 | Haptics + trauma shake + 70 ms hit-stop + shove ring; add `permissions/vibrate=true` | Feel | High | S |
| 5 | Power-restored light wave + blackout flicker choreography + per-room clunk sounds | VFX / Audio | High | M |
| 6 | Palette fixes (CREW #4d8dff, AMBER #ffe14d, GOOD #5ff0e0) + role, state and suit emblems | UI | High | S |
| 7 | Role-reveal choreography (card flip → fly to chip), identical audio and haptics for both roles, icon-only role chip with hold to reveal | UI | High | M |
| 8 | Per-state fog colour/density + height haze + fake light-shaft cones with dust motes | Rendering / VFX | High | M |
| 9 | Countdown and pod-alarm layering: pulse, last-5 s red, vignette tighten, heartbeat haptic, corridor beacons | UI / Feel | High | S |
| 10 | `UiMotion` helper (tokens from §4) applied to every panel, alert and lobby row | UI | Med | S |
| 11 | Touch layout pass: hit sizes, thumb-arc positions, edge exclusion, safe area, hold-to-fire BLACKOUT | UI | Med | S |
| 12 | Settings screen + `user://settings.cfg`: sensitivity, HUD scale and opacity, layout preset, shake, haptics, quality tier | UI | Med | M |
| 13 | Shader baker + effect pre-warm during the briefing (kills first-blackout stutter) | Rendering | Med | S |
| 14 | Procedural vertex AO in `ArtMeshKit` + probe `ambient_mode` per-room tint + `interior` | Rendering | Med | M |
| 15 | FSR 0.77 + quality tiers + simple dynamic resolution | Rendering | Med | M |
| 16 | Results screen: decisive-moment camera orbit, stamp, staggered timeline, 1.5 s button guard | UI | Med | M |
| 17 | Movement feel: run FOV kick, footstep dust, landing squash, carried-core spring sway, knock-loose arc | Feel / VFX | Med | M |
| 18 | Audio polish: blackout low-pass, alarm ducking, distinct UI sound set (confirm, back, error, join, leave) | Audio | Med | M |
| 19 | Per-state 3D LUT generated at startup | Rendering | Low–Med | M |
| 20 | Editor-baked LightmapGI pipeline (EditorScript + UV2 + per-state data). Only if playtests say the flat look hurts | Rendering | Low | L |

**Sources not fetched directly** (network-blocked in this session; the claims come from search excerpts): Riot tech blog, PlayStation Blog, Godot docs and forum, Arm developer blog. The Godot facts were cross-checked against the 4.7.2 class reference XML and the `godot-docs` sources on GitHub (renderers, lights and shadows, lightmap GI, anti-aliasing, environment pages).
