# Drift Station trailer: production plan

Companion to [treatment.md](treatment.md) and [script.md](script.md). Shot numbers (S01 to S33) are the script's.

Sections 1 and 2 are the specs for the character and UI work; must-haves come first in each, in the order to take them. Section 3 is the trailer tool, section 4 audio, section 5 puts everything in one order by its effect on the drama, section 6 defines the must-have and dream cuts, section 7 is render cost, and section 8 lists the test stills.

The cast, for reference in every spec:

| Name | Suit | No. | Part |
| --- | --- | --- | --- |
| Jon | blue | 2 | The one we follow. Takes the gun. |
| Sam | orange | 6 | Jon's friend. The infiltrator. |
| Zara | purple | 5 | The one everybody suspects. Crew. |
| Areeb, Maya, Kit | yellow 3, green 4, teal 7 | | The rest of the crew. |

Sizes: **S** under half a day, **M** one to two days, **L** three days or more.

## 1. Character requirements

Files: `scripts/art/crew_model.gd` (rig, poses, API), `crew_body.gd` (mesh), `crew_hand.gd` (gloves), `crew_materials.gd` (suit, visor and ghost shaders), `gun_visual.gd`, `scripts/physics/crew_ragdoll.gd`. The trailer drives all of it through `tools/showcase/studio.gd` and `tools/trailer/cut.gd`, one fixed step per frame, so **every new behaviour must be deterministic under `set_motion(..., delta)`**: no wall-clock time and no unseeded `randf` in anything the camera sees.

Today's studio pose hacks (`hands_up`, `raise_arm`, `glove`, `turn_head` in `studio.gd`) write bones after the pose step and call `_upload()`. They snap, they cannot blend, and they fight the idle. The must-haves below replace them with real `CrewModel` API that the game can use as well.

### Must-have, in build order

**C1. Arm reach (M). `crew_model.gd`, `crew_hand.gd`.**
`set_reach(side: int, target: Vector3, weight: float, glove := "")`: world-space wrist target for either arm, blended into the existing two-bone IK block (where carry, aim, shove and fidget targets are already mixed by weight), with a glove pose that eases in over 0.15 s. `side` 0 left, 1 right; weight 0 releases. When the target is beyond arm length (0.565 m), lean the chest up to 12° and step the shoulder forward before the elbow locks. A locked elbow looks like a mannequin.
Needed for: S05 (cell into socket), S10 (the hand in the dark), S13 (gun off the rack), S19 (hand on the airlock lever), S20 (Zara's arm stretched at the doorway), S32 (the point).
A test still of S10 with today's shove pose standing in for the reach (`A_s10_reach.png`, see Stills) shows why: the arm stops 30 cm short of the cage and the glove is a fist.
Accept: the fingertip lands within 1 cm of the target at weight 1, with no pop when weight animates 0 to 1 over 8 frames.

**C2. Head and eye look-at (S). `crew_model.gd`, `crew_materials.gd`.**
`set_look_target(target: Variant, head_weight := 1.0)`: `null` returns to idle. Head yaw up to ±70°, pitch ±30°, eased, and above 45° the chest follows by a third. The eyes lead the head by three frames and overshoot by 10%. The visor shader's `look` offset tops out at 0.024 today, which is invisible past 2 m: raise the range to about 0.06 so a side-eye reads.
Also `play_head("nod" | "shake", strength)`: a nod is one dip of 14° over 0.5 s; a shake is three swings of ±18° over 0.9 s.
Needed for: nearly every shot. The acting in this trailer is heads turning.

**C3. Faces that read at distance (M). `crew_materials.gd` (visor shader, `EXPRESSIONS`), `crew_model.gd`.**
The suspicious face reads as neutral past 4 m (see `docs/looks/2026-11-15-keyart-v1/08_characters_one_of_you_is_lying.jpg`: the purple suspect at 6 m looks calm). Requirements:
- **Silhouette test.** Each expression must be identifiable from the eye shapes alone at 8 m, FOV 70, 1280×720, where a visor is about 22 px wide. Design at that size first, then scale up.
- **Suspicious**, reworked: left eye squeezed to a flat bar, right eye a three-quarter circle, both pushed hard to one side, a slanted brow bar over the narrowed eye. The asymmetry is the read.
- **Angry**: two bars meeting in a V, matching the infiltrator helmet icon in `ui_icons.gd`. This is the face Sam turns to at the reveal, so the icon and the character become the same shape.
- **New: pleading** (Zara in the airlock): tall ovals, inner corners raised, a slow vertical tremble of 1 px at 8 Hz.
- **New: smug** (Sam, S25 and S32): half-lidded eyes, a single off-centre upturned curve below.
- **Distance compensation**: past 4 m scale the eye glyphs up to 1.3× and lift emission up to 1.25×, by camera distance. In the game this fixes the same readability problem at gameplay range.
- Add the two faces to the expression sheet (`tools/showcase/set_characters.gd`, `faces`) and re-shoot the distance sheet at 2, 4, 8 and 12 m.

**C4. Expression changes as performance (S). `crew_model.gd`, `crew_materials.gd`.**
`set_expression(name, hold := 0.0, blend := 0.12, glitch := false)`. With `glitch`, the visor tears into horizontal static for three frames before the new face appears (the shader has a `glitch` uniform already). S25 is exactly this: happy, three frames of tear, the V.

**C5. The helmet tap (M). `crew_model.gd`, `crew_hand.gd`.**
The trailer's central tell. Sam taps the side of his helmet twice before every blackout: S02 (a friendly greeting, nothing happens), S07 (out of focus in the background, then the lights die), S28 (to the lens, then black). On a second viewing the audience catches it.
`play_gesture("helmet_tap")`, separate from random fidget 1: elbow thrown wide so it reads as a silhouette at 10 m, index finger extended (`point` glove), two contacts at 0.30 s and 0.52 s from the start, total 0.9 s. Emit `gesture_beat(name, index)` on each contact so sound can land on the frame. Random idle fidgets must never pick this gesture, or the tell is noise.
Owner decision for the game: should triggering Blackout play this gesture on the infiltrator's avatar? It would be a real, catchable tell ("readable uncertainty"), and it would make the trailer literally true. The trailer needs only the animation.

**C6. Gesture set (M). `crew_model.gd`, `crew_hand.gd`, then delete the overrides in `tools/showcase/studio.gd`.**
All as `play_gesture(name)` or a held `set_gesture(name, weight)`, blendable, interruptible:
- `wave` (S02, S32): the existing `raise_arm` override, as real API.
- `thumbs_up` (S06): forearm up at chest height, `thumbs_up` glove, a small forward punch.
- `point` (S32): arm straight at a world target (uses C1), `point` glove, chest turned 20° into it.
- `surrender` (S14, S15): the existing `hands_up`, with elbows that sag over a few seconds and palms that turn out.
- `pound` (S26, the ghost on Sam): both fists on a target (C1), alternating strikes at about 3 Hz, the whole chest rocking into each strike.
- `lunge_reach` (S20): a stumbling run with one arm stretched ahead at a target, open glove. The existing shove pose is close but reads as clapping (test still `B_s20_doorway.png`).
- `step_back` (S14, S32): one retreating step with a catch, head staying on the look target.
- `brace` (S09): shoulders up, arms half out, knees bent: somebody who cannot see.

**C7. Shot, downed, carried, waking (M). `crew_model.gd` (`_downed_pose`, `_carried_pose`), `scripts/physics/crew_ragdoll.gd`.**
- S16: the bolt hits; `CrewRagdoll.spawn` collapses the body; the visor glitches, then shows the downed face. The ragdoll must settle within 1.5 s on a seeded run. If it cannot be made repeatable, capture the bone tracks once with `capture()` and replay them.
- S17: the carried pose today is a rigid plank on `carry_anchor`. Wanted: head lolling with the carrier's stride, the lower arm swinging, legs trailing with a half-beat lag; the carrier leaning back to balance and walking with a short heavy stride. The gameplay "carried dangle" from the physics pass is the reference; this is its deterministic version.
- S18: `play_get_up()`: 1.2 s from downed to standing (roll to the side, push off one hand, rise). There is no transition today; the model snaps.
- A downed visor that flickers back to life over the last second of the get-up.

**C8. Light control per character (S). `crew_model.gd`, `crew_materials.gd`.**
`set_lights(visor: float, trim: float, lamp: float)`: independent dimmers for the face, the suit's trim strips and the helmet lamp. The cut hides the face today with `visor.visible = false`. In the blackout a suit is black with trim glowing in its own colour (`34_moments_blackout.jpg`), which is beautiful and also gives every identity away. The thief in S10 has to be dark: trim 0, visor 0. In S29 Sam is lit only by the muzzle flash.
In the game the same dimmers let a downed player's suit fade.

**C9. Visor glints (M). `crew_materials.gd`.**
The visor is an emissive screen with no sense of glass. Add two cheap analytic highlights: `set_visor_glint(index, world_pos, color, size)` draws a soft, stretched highlight where that light would reflect on the curved visor, over the face. Used for the core's cyan in S07, the strobe in S20, the muzzle flash in S16 and the armed pod's red in S25. Plus a constant faint sky gradient with a warm streak for the gas giant, so visors look curved in every shot.
Cap the summed visor luminance so glow never blows a face to white at ECU (the same failure as the reactor).

**C10. Gun handling (S). `crew_model.gd`, `gun_visual.gd`, `crew_hand.gd`.**
- `set_aiming(on, height := 1.0)`: height 0 is a low ready (muzzle at the floor ahead), 1 is levelled; blend over 0.25 s. S22 needs the gun to sink slowly.
- The trigger finger: `grip_gun` to `grip_gun_trigger` as a visible squeeze over four frames before `on_shot()` (S15 is an ECU of it).
- Ammo cells on the gun (`set_ammo`) must be readable from the shooter's side at 1.5 m: three bright cells, a spent one going dark with a one-frame flash.
- Running with the gun (S26): a one-handed run, the gun arm tucked, muzzle down and forward.

**C11. Ghost (M). `crew_materials.gd` (ghost shader), `crew_model.gd`, `scripts/vfx.gd`.**
Ghost Zara is the audience's witness in Act III: she finds Sam at the pod and nobody can hear her. She has to read instantly as (a) dead and (b) Zara.
- Keep 35% of the suit hue under the ghost blue, so purple survives.
- A fresnel rim bright enough to hold against lit walls and against black; faint scanlines drifting up; legs dissolving below the knee as now.
- Any expression in the ghost state, not only the ghost face: S24 needs shocked, then pleading.
- Frost on the visor rim (she went out of the airlock).
- Passing through a wall (S24): a bright line where the body intersects the wall plane, plus a ring ripple from `vfx.gd` on the wall. Must-have is the ripple alone; the intersection line is a dream.
- **Calm it down near the lens.** A test still (`D_s24_ghost_pod.png`) put the ghost 1.5 m from camera: the shader's interior contour lines turn into a bright mesh that hides everything behind it, and the face is forced to a flat bar. Fade the interior lines out within 3 m of the camera, keeping the rim, and keep total ghost luminance under the glow threshold. The script keeps her at 3 m or more regardless.
- Ghost arms that pass through a living body without collision (S26).

**C12. Tension (S). `crew_model.gd`.**
`set_tension(0..1)`: breathing from 0.25 Hz to 0.7 Hz with more chest travel, shoulders lifted, gloves half-closed, a 0.5° head tremor at 1.0. Used on Jon in S19 and S27, Zara in S20, and everybody in S22.

### Dream

- **D-C1. True visor reflections (L).** A 128 px reflection capture per hero close-up so the gun, or the person across the room, appears in the visor. S15's gun ECU would show Zara's raised hands in Jon's visor. `crew_materials.gd`, `tools/showcase/studio.gd`.
- **D-C2. Wear and damage (M).** `set_wear(0..1)` scuffs and dulled paint on shell edges; `add_scorch(local_pos)`, a dark burn with a dying ember rim where a bolt hit (Zara from S16 on); `set_frost(0..1)` creeping from the visor rim (S21, S24). `crew_materials.gd`, `crew_body.gd` (a spare UV channel or decal slot).
- **D-C3. Dot-matrix visor at ECU (S).** Past a pixel-size threshold the face resolves into LED dots with a faint grid, so a visor that fills the frame has texture. `crew_materials.gd`.
- **D-C4. Hero mesh density (M).** Visor bezel and helmet rim at 48 or more segments for shots where the helmet is over 900 px tall at 1440p; checked in S15, S20, S25. `crew_body.gd`, `crew_mesh_kit.gd`.
- **D-C5. Identity in the dark (S).** Orange and yellow trims are close in a blackout. Give each helmet variant its own trim pattern (single bar, double bar, ring, chevrons) so a suit is recognisable by pattern as well as hue. `crew_materials.gd`, `crew_body.gd`. Good for colour-blind players too.
- **D-C6. Cloth and cable secondary motion (M).** Hose and strap sway on the backpack in the sprint (S26) and the drag (S17). `crew_model.gd` springs.

### Performance, shot by shot

What each character does where, so the animation can be checked against the script.

| Shot | Who | Performance | Needs |
| --- | --- | --- | --- |
| S02 | Jon | Walks in, stops, `wave` at Sam. Happy. | C6 |
| S02 | Sam | Arrives last, from the Docking door. `helmet_tap` back at Jon. Happy. | C5 |
| S02 | Zara | Stops a step outside the ring, looking at the floor, then up at the others. Suspicious. | C2, C3 |
| S04 | Jon, Sam | Carry a cell each, side by side. Jon turns his head to Sam, nods. | C2 |
| S04 | Zara | Half behind a pillar, head tracking them as they pass. Suspicious, readable at 7 m. | C2, C3 |
| S05 | Sam | Right hand presses the cell home, palm flat, holds one beat. | C1 |
| S06 | Jon, Sam | Faces go happy; Sam `thumbs_up`; Jon nods. | C6, C2 |
| S07 | Zara | Nearest the vault. Leans in, head tilted. | C2 |
| S07 | Sam | Background, soft focus: `helmet_tap`. | C5 |
| S09 | All | `brace`. Heads snap between beams. Shocked. | C6, C2 |
| S10 | Unknown | A dark arm reaches to the core, fingers open, close on the cage. Trim off, visor off. | C1, C8 |
| S11 | Zara | Caught in a beam beside the empty vault. Shocked. One glove half raised. | C2 |
| S13 | Jon | Reach to the rack, close on the grip, lift. Angry. | C1, C10 |
| S14 | Jon | Gun levelled. Tension 0.6. | C10, C12 |
| S14 | Zara | `surrender`, then one step forward. Pleading. | C6, C3 |
| S14 | Sam | At Jon's right shoulder. Looks at Zara, then at Jon. One nod. | C2 |
| S14 | Others | `step_back`, widening the ring. | C6 |
| S15 | Jon | ECU: trigger finger squeezes. | C10 |
| S16 | Zara | Hit, ragdoll, downed. | C7 |
| S17 | Sam, Zara | Sam carries her. Dangle. | C7 |
| S18 | Zara | Dropped on the airlock floor, downed. At the end, a hand twitches and the visor flickers. | C7 |
| S18 | Sam | Sets her down, walks out without looking back. | C7 |
| S19 | Jon | Hand to the lever, stops short, fingers flex. Looks back at Sam. Tension 1.0. | C1, C12 |
| S19 | Sam | One slow `nod`. | C2 |
| S20 | Zara | `play_get_up`, sees the open doorway, `lunge_reach` at it. Pleading. Shoved; staggers back (existing hit and stun). | C7, C6, C3, C9 |
| S20 | Sam | Steps into the doorway and shoves her back in (existing `play_shove`). Does not look at Jon. | existing |
| S21 | Zara | Weightless ragdoll, frost. | existing |
| S22 | All | Stand. Wait. Heads turn to each other. Jon's gun sinks to low ready. Sam is not there. | C2, C10, C12 |
| S24 | Zara (ghost) | Drifts through the Cargo wall, stops dead. Shocked. | C11 |
| S24 | Sam | At the pod, back to us, core seated. | existing |
| S25 | Sam | Head turns over the shoulder. Happy, glitch, the V. | C2, C4, C9 |
| S26 | Jon | Sprint with the gun. Angry. | C10 |
| S26 | Zara (ghost) | `pound` on Sam; her hands pass through him. | C11, C6 |
| S27 | Jon | Skids in, levels the gun. | C10 |
| S28 | Sam | Turns to the lens. Smug. `helmet_tap`. | C3, C5 |
| S29 | Sam | One frame in the muzzle flash, mid-lunge, arms out (the shove pose at full thrust). | C8 |
| S32 | All | The spawn ring again. Five `step_back` from Sam; Zara `point`s at him. Sam: smug, then happy; `wave`. | C6, C3 |

## 2. UI and title requirements

Files: `scripts/hud.gd`, `scripts/ui/hud_briefing.gd`, `hud_alerts.gd`, `hud_countdown.gd`, `hud_result.gd`, `hud_markers.gd`, `ui_icons.gd`, `ui_motion.gd`, `scripts/ui_style.gd`, and `scripts/crew_member.gd` for name tags.

The idea that drives all of it: **the trailer is one round's event timeline, played back.** The design doc says "the timeline is the story". So the trailer's text is neither marketing copy nor voice-over: it is the game's own result-screen rows, appearing one at a time as lower thirds, and the trailer ends on the real result card. Every piece of UI the trailer shows must be the real component, instanced by the trailer tool, never a look-alike built in `cut.gd`. That is what keeps the trailer honest, and why each item below is also a game improvement.

One requirement applies to everything here: **each component must run standalone.** It needs a static constructor or a `present(data: Dictionary)` that takes plain data (no `Net`, no `StationRules` instance), lays out at any size from 1280×720 to 2560×1440, takes its time from a `step(delta)` or an explicit `set_progress(t)` (the trailer renders at a fixed step and cannot wait on tweens tied to wall-clock time), and has a flag that drops safe-area margins and touch controls.

### Must-have, in build order

**U1. The timeline row and a live event ticker (M). `hud_result.gd`, new `scripts/ui/hud_ticker.gd`, `hud.gd`, `ui_style.gd`.**
- Extract the result timeline's row (time, icon, text with names in suit colour) into `HudResult.make_row(time_s, icon, bbcode) -> Control`.
- New `HudTicker`: a lower-left stack; each event slides in (0.2 s), holds (2.5 s by default, settable), fades (0.4 s). At most two rows visible.
- In the game: public events appear live ("Power restored (3/3)", "The lights went out", "The cargo pod is armed", "Zara was spaced"). Events that would reveal a role are anonymised live ("Someone triggered a blackout") and named only on the result screen. This is the design's "readable uncertainty" pillar as an interface, and it is missing today.
- In the trailer: the same component is the lower third. Type at 3.3% of frame height, left margin 8% of width, baseline at 80% of height (inside the 2.39:1 picture), time in amber, names in suit colour, the rest off-white. Rows the script uses:
  `0:00 Round started with 6 crew aboard.` · `1:30 Sam inserted a power cell (3/3).` · `2:02 Someone triggered a blackout.` · `2:09 Someone took the core.` · `3:40 Jon shot Zara.` · `4:05 Zara was spaced.` · `4:11 The cargo pod is armed.`

**U2. Result screen with a staged reveal (M). `hud_result.gd`, `ui_motion.gd`.**
The real card (`docs/looks/2026-11-15-ui-v2/08_720_result.jpg`) shows everything at once. Stage it, as `HudResult.present(data)` with `set_progress(t)`:
1. 0.0 s: the outcome title ("STATION LOST", "CREW ESCAPED", "CORE STOLEN").
2. 0.6 s: "THE INFILTRATOR WAS", with an empty slot that cycles through every player's avatar and name at 12 per second.
3. 1.4 s: the slot lands, a hard stop: avatar, name in suit colour, one white frame behind it.
4. 1.8 s: timeline rows cascade in, 60 ms apart. Rows that were anonymous during the round resolve to names now: "Someone" flips to "Sam" in orange, with a small red marker. This is the moment friends shout at each other. Give it the animation.
5. A turning-point tag on the row where it went wrong: a red chip, "ZARA WAS CREW", on the "spaced" row.
6. PLAY AGAIN pulses once per second.
The trailer shows steps 2 and 3 full-frame in S31 and uses the PLAY AGAIN button as the end slate's call to action in S33.

**U3. Role card (S). `hud_briefing.gd`.**
`HudBriefing.present({role, name, color})`, standalone. A cinematic variant: no panel chrome, the helmet icon large (crew: LED eyes; infiltrator: the red V), "YOU ARE CREW" or "YOU ARE THE INFILTRATOR", one line beneath. In 0.3 s, hold, out 0.2 s.
The trailer flashes it twice: over S02 for 1.2 s ("YOU ARE CREW", blue, as Jon arrives), and over S25 for 0.8 s ("YOU ARE THE INFILTRATOR", red, as Sam's face changes). Same card, same position, the second in red: the audience learns the rule from the first and gets hit with the second.

**U4. Blackout treatment (S). `hud_alerts.gd`, `hud.gd`, `scripts/crew_member.gd`.**
- Alert "LIGHTS OUT" with the blackout icon, kind `danger`, via `HudAlerts.present(text, kind)` standalone.
- When a blackout starts, the HUD itself reacts: chrome drops to 30% opacity over 0.2 s with two flicker frames; name tags over heads stutter and go out one by one, 40 ms apart. Reverse when the power returns.
- The trailer shows the alert alone on black in S08: for 1.5 s it is the only thing on screen.

**U5. Name tags (S). `scripts/crew_member.gd`, `ui_style.gd`.**
The trailer needs names attached to bodies or the timeline rows mean nothing. The game's tags, cleaned up: a small pill, a suit-colour dot plus the name, 2.2% of frame height, fading with distance, never overlapping another tag (push apart vertically). A static `make_name_tag(name, color)` so the trailer can attach one to a `CrewModel`.
Shown in S02 (all six, for about 3 s, then fading), S14 (Jon, Zara, Sam) and S32 (all six). Nowhere else: faces carry the rest.

**U6. Gun ammo (S). `hud.gd`, `ui_icons.gd`.**
- For the holder: three charge pips beside the action button, in the gun's cell colour. Firing pops a pip: scale 1.4, one white frame, then hollow.
- For everybody else: a small blaster glyph on the armed player's name tag. The design says the holder is "the most trusted or most feared person aboard"; today nobody can tell who that is from across a room.
- The trailer shows the pips bottom centre: all three with the card "ONE GUN. THREE SHOTS." in S13, the pop to two in S16, and the pop to one in S29, where the pip is the only light on a black frame.

**U7. Countdown ring (S). `hud_countdown.gd`.**
`HudCountdown.present(kind, total_s)` with `set_remaining(s)`, standalone. Replaces the 30%-of-frame digit in today's cut, which covers the action it counts. Bottom centre, 14% of frame height, the draining ring plus digit. Kinds: `airlock` (3.5 s, amber), `pod` (20 s, red), `shuttle` (30 s, cyan).
Add a last-three-seconds state for the game too: the ring thickens and the digit punches on every tick.
Trailer: S20 (airlock 3, 2, 1) and S26 to S28 (pod, running in real time from 12 down to 2).

**U8. Logo lockup (M). `ui_style.gd` (`UiStyle.logo(height, state)`), `ui_icons.gd`, `scripts/main.gd` (home screen).**
The title today is a plain `Label` in the title font. Build a lockup:
- DRIFT over STATION, title font, STATION tracked out to DRIFT's width, both on a shared grid.
- The **O** of STATION is a crew helmet visor seen head-on: a ring with two LED eyes. State `crew`: white eyes. State `infiltrator`: the eyes snap to the red V. The game's whole premise, inside the wordmark.
- A one-line variant (DRIFT STATION) for narrow slots, and an icon-only variant (the O) that matches the app icon.
- Drawn in code (`_draw` or a generated mesh), sharp at any size, with `set_state(name, blend)` for the flip.
- Use it on the home screen, the lobby header and the result card, as well as in the trailer.
Trailer: S30 lands the lockup in the `crew` state on the hit; 1.2 s later the O flips to the V on the sub-boom.

**U9. Card typography (S). `ui_style.gd`, `tools/trailer/cut.gd`.**
One small system, so every card comes from the same family as the game's UI:
- `UiStyle.card_statement(text)`: centred, title font, 10% of frame height, off-white `Color(0.93, 0.96, 1.0)`, tracking +4%, for at most five words. Used twice only: "ONE OF YOU IS LYING." (S12) and "ONE GUN. THREE SHOTS." (S13, at 5% height, bottom third).
- `UiStyle.card_line(text)`: body bold, 4% height, for the tagline.
- Lower thirds are U1.
- All text stays inside the 2.39:1 picture, with 8% side margins.
- Nothing fades slowly. Text cuts on or snaps in over three frames; it cuts off. The only slow fade in the trailer is the last one.

**U10. End card and slate (S). `ui_style.gd`, `tools/trailer/cut.gd`.**
- S30: the lockup; beneath it, after the flip, `card_line`: "2–8 friends. One of you is lying."
- S33: the one-line lockup, small, at the top; the real primary button (`UiStyle.button("PLAY AGAIN", true)`) in the centre, pulsing; beneath it "ANDROID · PC" in the head font, amber. The platform line must match what ships: check it against the README before the final render.

**U11. Cinematic HUD mode (S). `hud.gd`.**
`Hud.set_cinematic(true)`: hides touch controls, the menu button, edge markers and the objective chip; keeps the alerts, ticker, countdown and ammo pips. The trailer needs it to instance real components over a clean frame; it also gives the game a spectator and screenshot mode for nothing.

### Dream

- **D-U1. Accuse (M; needs an owner decision because it is a new verb).** Hold to point at a player: your avatar plays `point` (C6), an amber SUSPECT chevron sits over the target for 3 s for everyone, and the timeline logs "Jon accused Zara". The game has no vote and the trailer does not pretend it has. If this ships before the final render, S14 gains the chevron over Zara and a row `3:31 Jon accused Zara.`; if not, the shot works on the gesture alone. `hud_markers.gd`, `hud.gd`, `scripts/station_rules.gd`, `scripts/crew_member.gd`.
- **D-U2. Ghost HUD (S).** A cold desaturated tint, a "ONLY GHOSTS CAN SEE YOU" chip, living players' tags readable through walls. A half-second flash of it at the head of S24 would tell the audience what a ghost is without a word. `hud.gd`.
- **D-U3. Animated timeline icons (S).** Each row's icon plays a 0.3 s animation as the row lands (the cell slots in, the blaster recoils, the airlock irises). `ui_icons.gd`, `ui_motion.gd`.
- **D-U4. Lobby rematch moment (S).** After PLAY AGAIN the lobby shows last round's infiltrator with a small red V on their card until the next round starts: a grudge marker. S32 would open on it. `scripts/main.gd`.
- **D-U5. A custom title face (L).** A drawn wordmark, replacing the stock title font in the lockup, with the stencil cuts used on the station's floor lettering. `ui_style.gd`, `assets/`.

## 3. Trailer tool

Files: `tools/trailer/cut.gd` (the cut), `tools/trailer/trailer.gd` (the renderer), `tools/trailer/make_video.py` (encode and mix), `tools/trailer/render_trailer.py`, `tools/showcase/studio.gd` (the rig), `scripts/vfx.gd`.

### Must-have

| # | Item | Size | Files | For |
| --- | --- | --- | --- | --- |
| T1 | **The new beat list.** 33 `shot_NN_*` methods replacing the 16 beats, each one script shot. A `cuts(lt, [times])` helper returning the index and local time, lifted from `beat_countdown`, for S15, S24, S26 and S29. Keep the old cut as `cut_v1.gd` until the new one is approved. | L | `cut.gd` | All |
| T2 | **Camera kit.** `rack(focus_a, focus_b, k)`: animate the focus point and depth (a lerp into `frame()`). `dolly_zoom(subject, fov_a, fov_b, k)`: solve camera distance so the subject keeps its size. `whip(target_a, target_b, lt, t0, frames)`. `handheld(strength)`: seeded noise as a pure function of absolute time, so a resumed render matches; applied after `frame()`. Roll already exists in `frame()`. | M | `cut.gd`, `studio.gd` | S04, S09 to S20, S15a, S11, S19, S23 to S28 |
| T3 | **Real UI in the overlay.** Replace the four `Label`s with a host that instances the real components (U1 to U10) and steps them with the cut's `dt`: `row(lt, at, time, bbcode)`, `role_card(...)`, `alert(...)`, `ring(kind, remaining)`, `pips(n)`, `name_tag(actor, name)`, `logo(state)`, `result(progress)`. | M | `cut.gd` | Every shot with text |
| T4 | **Cue sheet 2.** Cues gain `dur`, `fade_out`, `pan` and `lowpass`; a `stop(sound)` cue; a `silence(lt, at, dur)` that hard-mutes the effects bus; a per-shot `score_gain`. Today a long cue such as `ambience_emergency` plays to its end across later shots, and nothing can be silenced. `make_video.py` builds the filter graph from the sheet. | M | `cut.gd`, `trailer.gd` (sheet format), `make_video.py` | S08, S21, S24a, S26, S29 |
| T5 | **Grade per shot.** `grade(exposure, glow, saturation, contrast)` with the visor glow cap, resetting in `begin_shot`. Generalise `restore_power_soft()`. | S | `cut.gd`, `studio.gd` | S05, S06, S20, all ECUs |
| T6 | **Light helpers.** Flashlights that start off and click on at a time; a spot that follows the camera target (S11); a strobe-locked spot (S20); `key_from(source_pos, subject, color, energy)` for one-light close-ups. | S | `cut.gd`, `studio.gd` | S09, S11, S20, S15 |
| T7 | **Ragdoll repeatability.** Record the bone transforms of the S16 and S21 ragdolls on the first pass (`CrewRagdoll.capture()` per frame to a file beside the frames) and replay them when the file exists, so partial and resumed renders match. | M | `cut.gd`, `scripts/physics/crew_ragdoll.gd` | S16, S21 |
| T8 | **Render by shot.** `--shots S14-S16` (resolved to frame ranges from `BEATS`), and `--sheet`: one frame at 20, 50 and 80% of each shot to a contact sheet at 640×360, for review without a render. Extend `--check` to sample each sub-cut. | S | `trailer.gd`, `render_trailer.py` | Iteration |
| T9 | **Small VFX.** A ghost wall ripple (a ring on a wall plane); a one-frame muzzle light strong enough for S29; a bolt-impact burst on a suit. | S | `scripts/vfx.gd` | S24, S29, S16 |
| T10 | **Vertical teaser recut.** 15 s from the master frames: S20, S21 (3 s), S28, S29, S30. The current teaser logic picks ranges; give it the new ones. | S | `make_video.py` | Teaser |
| T11 | **Docs.** Update `tools/trailer/README.md` with the new beat table. | S | `tools/trailer/README.md` | |

### Dream

| # | Item | Size | Files | For |
| --- | --- | --- | --- | --- |
| D-T1 | **Sub-frame motion blur** on two shots: render S16 and S26 at 120 fps and average four frames into one (`tmix` in ffmpeg). Costs four times the frames for 8.5 s. | M | `trailer.gd`, `make_video.py` | S16, S26 |
| D-T2 | **Slow motion.** `Engine.time_scale` and the cut's `dt` scaled together per shot, so the S16 fall can run at half speed for twelve frames. | M | `cut.gd`, `trailer.gd` | S16 |
| D-T3 | **Lens artefacts.** An additive horizontal streak and a small flare billboard on the brightest emitter in frame (flashlights in S09, the muzzle in S16, the pod beacon in S27). Faked with vfx slots; the Mobile renderer has no lens effects. | M | `scripts/vfx.gd`, `studio.gd` | S09, S16, S27 |
| D-T4 | **Film finish in the encode.** Fine grain and a slight vignette added by ffmpeg, to take the CG cleanness off flat walls. | S | `make_video.py` | All |
| D-T5 | **An inner airlock door with a porthole** that closes at the vent. A change to the station and to the rules (today you can walk out during the warning, and the scene is written around that). Only if the owner wants it in the game. | L | `scripts/station_builder.gd`, `scripts/station_rules.gd`, `scripts/art/station_fx.gd` | S18 to S20 |

## 4. Audio and score

Everything is synthesised: effects by `tools/generate_audio.py`, music by `tools/generate_music.py` (its `CUT` dict mirrors `cut.gd`; one render takes about 35 s on `heavy.sh --quick`). No recorded sound.

### Must-have

| # | Item | Size | Files |
| --- | --- | --- | --- |
| A1 | **New score, `trailer_theme_v2.wav`, 107.5 s**, to the score map in the treatment and the cue table at the end of the script. Key of D. Written as stems (`drone`, `pulse`, `clock`, `drums`, `hits`, `bloom`, `title`) plus the full mix, so the mix can mute a stem. Reuse from the current score: the bloom, the tritone drone and heartbeat, the title swell, the sub-boom. New: the two-hit motif (two low hits 0.22 s apart), the clock, the 120 BPM run. The three silences are in the score as true zeros. | L | `tools/generate_music.py`, `assets/audio/music/` |
| A2 | **`helmet_tap`**: one dry, hard click (one hit per file; the cut fires it twice, 0.22 s apart). A knuckle on a helmet shell: a short noise burst through a high resonance, 40 ms. It has to be recognisable on the third hearing. | S | `tools/generate_audio.py` |
| A3 | **`power_up` retuned** so its final pitch is D, matching the score's entry. Check the game still sounds right. | S | `tools/generate_audio.py` |
| A4 | **`breath_helmet`**: 6 s of slow breathing as filtered noise with a small resonance, loopable. | S | `tools/generate_audio.py` |
| A5 | **`flashlight_click`, `lever_clunk`, `servo_reach`, `tinnitus`, `slot_tick`, `slot_stop`.** Small. `lever_clunk` is two-stage (latch, then a heavy throw). | M for the set | `tools/generate_audio.py` |
| A6 | **The mix** (with T4): score ducked under effects as now; the digital silence in S21 checked on the waveform (no reverb tails crossing the cut: truncate them); the gunshot in S29 as the loudest peak of the file. Master to about -14 LUFS as now. | S | `make_video.py` |

### Dream

- **D-A1. A separate vertical-teaser score (S).** 15 s, built on the taps and the title hit. `tools/generate_music.py`.
- **D-A2. Room acoustics per location (M).** A short reverb for Commons, a tight dead one for the airlock, none outside. `make_video.py` or pre-rendered variants.
- **D-A3. A human breath (S, and the only recording in the film).** One real recorded breath for S21 in place of the synthesised one. The owner's call.

## 5. One order, by effect on the drama

If only the first five happen, the trailer still works. Each line says what the film loses without it.

| Rank | Item | Size | Without it |
| --- | --- | --- | --- |
| 1 | **T1, the new cut**: one story, three people, 33 shots | L | There is no trailer |
| 2 | **A1 + T4, the score and the silences** | L + M | The vent has sound. The centre of the film is gone |
| 3 | **C5 + A2, the helmet tap** | M + S | No tell, no last shot, no reason to watch twice |
| 4 | **C1 + C2, reach and look-at** | M + S | No hand in the dark, no hand on the lever, nobody looks at anybody |
| 5 | **U1 + T3, the timeline rows as real UI** | M + M | The trailer has no words, or fake ones |
| 6 | **C7, shot, carried, waking** | M | S16 to S20 are stiff: a plank being carried, a body that snaps upright |
| 7 | **C3 + C4, faces that read; the glitch to the V** | M + S | Zara's pleading and Sam's reveal are played on faces that say nothing |
| 8 | **T2, the camera kit** | M | Every shot is the same eased push again |
| 9 | **C11 + T9, the ghost** | M + S | The witness is a noisy blue shape |
| 10 | **U2 + U8, the result reveal and the logo** | M + M | The ending is a plain label |
| 11 | **C6, the gesture set** | M | S32, the sting, has no step back and no point |
| 12 | **C8 + C9, suit lights and visor glints** | S + M | The thief glows; visors are flat screens |
| 13 | **U3, U4, U6, U7, U5**: role card, alert, pips, ring, tags | S each | Rules are less clear; the gun's three shots are not counted |
| 14 | **T5 to T8, C10, C12, A3 to A6** | S to M | Polish and safety |
| 15 | Everything marked dream | | |

## 6. Two cuts

### Must-have cut: 1:45.0, 32 shots, 3,150 frames

All shots except S03. Built from every must-have item above. Where a must-have is late, the script degrades in a known way, without changing the story:

| If this is missing | Then |
| --- | --- |
| C1 reach | S10: the shove pose, a tighter crop on the glove, the core lifted by reparenting as now. S19: Jon's hand rests beside the lever and the console lighting up does the work. S13: the current pickup (the gun appears in the hand on a cut to the visor) |
| C3 new faces | Pleading becomes shocked; smug becomes happy; keep every face inside 2 m |
| C5 gesture | Use fidget 1 (the existing helmet tap), forced with `play_fidget(1)`, and time the cut to it |
| C7 get-up and dangle | S20 opens with Zara already standing; S17 uses the current carried pose and a wider, darker frame |
| C9 glints | Nothing replaces them; the shots still work |
| C11 ghost rework | Keep her 4 m or more from the lens and in profile; the current ghost face throughout |
| U1 to U8 real components | The trailer cannot ship with look-alikes. Hold the render, or drop that element (the story survives on rows and the title alone) |
| T7 ragdoll replay | Render S16 and S21 each in a single pass and never resume inside them |

### Dream cut: 1:47.5, 33 shots, 3,225 frames

The must-have cut, plus:

- S03, the cell lifted from the floor (C1 on both arms).
- True visor reflections in S15b and S25 (D-C1); scorch on Zara from S16, frost in S21 and S24 (D-C2); dot-matrix visors at ECU (D-C3).
- Sub-frame motion blur on S16 and S26 (D-T1); half-speed fall in S16 (D-T2); streaks and flares (D-T3); grain (D-T4).
- The accuse chevron and row in S14 (D-U1), if the verb ships; the ghost HUD flash at the head of S24 (D-U2); the lobby grudge marker opening S32 (D-U4).
- Room acoustics (D-A2).

## 7. Render cost

Measured on this machine (4 cores, software Vulkan, no GPU): about 3 s of wall time per frame at 2560×1440 with 4× MSAA. The key-art log has 5.2 s per frame for a busy stretch (the betrayal, 38 to 43 s of the old cut), so I give both.

Not all frames cost the same. Black, card and UI-only frames (S08, S12, most of S29, S30, S33, and S31 if its background is a still) come to about 390 frames and render in well under a second each if the 3D viewport is disabled for them (a small `trailer.gd` change, part of T8; otherwise they cost a full frame of a parked camera).

| | Frames | 3D frames | At 3 s | At 5.2 s |
| --- | --- | --- | --- | --- |
| **Must-have cut** | 3,150 | about 2,760 | **2.3 h** | 4.0 h |
| Dream cut, plain | 3,225 | about 2,835 | 2.4 h | 4.1 h |
| Dream cut with sub-frame blur (S16 and S26: 255 frames × 3 extra) | 3,990 rendered | about 3,600 | 3.0 h | 5.2 h |

Plan for **one must-have master at about 2.3 to 4 hours**, on one `heavy.sh` slot, plus:

| Step | Cost |
| --- | --- |
| Engine start and station build, per run | about 1 min |
| `--check` over all shots (headless, no rendering) | about 5 min |
| Contact sheet (T8), 99 frames at 640×360 | about 5 min |
| Full preview at 640×360, 15 fps (1,575 frames) | about 25 min each; allow three |
| Per-act masters instead of one run: Act I 660 frames (0.55 h), Act II 1,440 frames, 90 of them black (1.1 h), Act III with titles 1,050 frames, about 300 of them black or UI (0.65 h), at 3 s | The same total, but a failure costs one act |
| Re-shoots after review | allow 15%: about 0.4 h |
| Score render | 35 s each |
| Encode and mix | about 5 min |

Total budget to a finished must-have master: **about 4.5 hours of machine time at the 3 s rate**, or about 7 hours if the heavier rate holds everywhere. Nothing should be rendered at 1440p until the contact sheet and one full preview are approved.

Ways to cut cost without hurting the picture, in order: 2× MSAA in the blackout shots (S09 to S11, where edges are dark on dark); shadows off on fill spots; render S21 and S01, which have no crew in close-up, at 1920×1080 and upscale; hold S30 and S33 as stills.

## 8. Test stills

Four stills at 1280×720, preview quality, rendered through `heavy.sh --quick` in one engine run (about 2 minutes). They are in the scratchpad, not the repo. Each changed something in the script.

| Still | Path | What it was for | What it changed |
| --- | --- | --- | --- |
| A | `/tmp/claude-0/-home-user-maldiven/31b9ade9-c535-5a0e-b4db-12a801c32fe1/scratchpad/trailer_director/stills/A_s10_reach.png` | S10: does the core alone light a reaching glove in the blackout? | Yes, and well; no extra light is needed. Cyan light turns the orange suit green-grey, so the colour hides the thief by itself. But the stand-in shove pose stops 30 cm short and shows a fist and the chest plate: the shot needs C1 and a tighter frame, and the trim has to be switched off (C8) |
| B | `/tmp/claude-0/-home-user-maldiven/31b9ade9-c535-5a0e-b4db-12a801c32fe1/scratchpad/trailer_director/stills/B_s20_doorway.png` | S20: the airlock doorway from Commons | The framing works: the striped OUTER HULL DOOR behind her is the backdrop. It also confirmed there is no inner door, which is why the scene became "she runs for the opening and is shoved back" and not "hands on the glass". The pink wash is too bright: exposure 0.7 in the script |
| C | `/tmp/claude-0/-home-user-maldiven/31b9ade9-c535-5a0e-b4db-12a801c32fe1/scratchpad/trailer_director/stills/C_s04_observation.png` | S04: the carry through Observation with the planet in the window | The two-shot is lovely as it is: cells lighting the chests. The planet is not there: from this room only a small dark moon shows. So the scene plays under stars, and Zara's mark moved to the rail at frame right, where the first position hid her |
| D | `/tmp/claude-0/-home-user-maldiven/31b9ade9-c535-5a0e-b4db-12a801c32fe1/scratchpad/trailer_director/stills/D_s24_ghost_pod.png` | S24: over the ghost's shoulder to Sam at the armed pod | Wrong as composed: at 1.5 m the ghost shader is a bright mesh that hides the subject, and her face is a flat bar. S24 became two set-ups (she arrives in profile at 4.5 m; then her point of view, without her in it), and C11 gained the near-lens requirement. The pod's own POD ARMED sign reads clearly and is used as the shot's text |

The script that made them: `/tmp/claude-0/-home-user-maldiven/31b9ade9-c535-5a0e-b4db-12a801c32fe1/scratchpad/trailer_director/stills.gd`.
