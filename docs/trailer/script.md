# Drift Station launch trailer: shooting script

"What Happened". 33 shots, 1:47.5 at 30 fps (3,225 frames). The must-have cut drops S03 and runs 1:45.0 (3,150 frames); every later timecode then moves 2.5 s earlier.

Read [treatment.md](treatment.md) first for the why. What has to be built is in [production-plan.md](production-plan.md); codes such as C1 or U7 point there.

## How to read a shot

Each shot becomes one entry in `BEATS` in `tools/trailer/cut.gd`, named `shot_NN_slug`, with the duration given. Inside a shot:

- **lt** is beat-local time in seconds, the same `lt` every beat method receives.
- Positions are world metres `(x, y, z)`, the floor at y 0, from `scripts/station_layout.gd`. Yaw 0 faces +Z, as in `studio.gd`'s `crew()`.
- **Cam** gives position, look-at target, vertical FOV, and focus, in the terms of `frame(pos, target, fov, focus, depth, blur, near_blur, roll)`. "A to B" is an eased `cam_move`.
- **Power** is the `begin_shot` state: `emergency`, `restored` or `blackout`.
- Sound names are files in `assets/audio/`; names marked *new* are listed in the plan.
- Camera positions are composed from the layout and from four test stills. Props move between builds, so run `trailer.gd --check` on every shot before rendering it.

### Cast

| Key | Suit, variant, number | Tag |
| --- | --- | --- |
| `jon` | blue, 2, 2 | Jon |
| `sam` | orange, 2, 6 | Sam |
| `zara` | purple, 1, 5 | Zara |
| `areeb` | yellow, 1, 3 | Areeb |
| `maya` | green, 3, 4 | Maya |
| `kit` | teal, 0, 7 | Kit |

### Standing rules

- Letterbox as now (`BARS` 0.128). All text inside the picture area.
- Handheld drift is **off** in S01 to S07, **on** (0.4°, 2 cm, 0.7 Hz) from S09 to S20, **off** in S21 and S22, **on** at double strength in S23 to S28, **off** after.
- Glow cap: `glow_intensity` at or under 0.85 in any shot where a visor is taller than a third of the frame.
- Timeline rows (U1) cut in, hold 2.5 s, cut out. Written below as `ROW`.
- No dissolves. "Cut" means a hard cut.

## Shot index

| Shot | Time | Dur | Where | What |
| --- | --- | --- | --- | --- |
| S01 | 0:00.0 | 5.0 | Exterior | The dead station |
| S02 | 0:05.0 | 5.5 | Commons | Six arrive. The wave, the tap |
| S03 | 0:10.5 | 2.5 | Medical | Gloves lift a cell (dream cut only) |
| S04 | 0:13.0 | 5.0 | Observation | The carry. Zara watches |
| S05 | 0:18.0 | 3.5 | Reactor | Sam's hand, the third cell, the wave |
| S06 | 0:21.5 | 3.0 | Reactor | Light on faces. Thumbs-up |
| S07 | 0:24.5 | 5.0 | Command | The vault opens. The tap, unseen |
| S08 | 0:29.5 | 1.5 | Black | Lights out |
| S09 | 0:31.0 | 4.0 | Command | Visors and beams |
| S10 | 0:35.0 | 2.5 | Command | A hand in the dark |
| S11 | 0:37.5 | 2.5 | Command | The empty vault. Zara |
| S12 | 0:40.0 | 1.5 | Black | ONE OF YOU IS LYING. |
| S13 | 0:41.5 | 3.5 | Security | The gun |
| S14 | 0:45.0 | 4.0 | Commons | The ring |
| S15 | 0:49.0 | 3.0 | Commons | Five close-ups |
| S16 | 0:52.0 | 2.0 | Commons | The shot |
| S17 | 0:54.0 | 4.0 | Commons | Sam carries her |
| S18 | 0:58.0 | 3.5 | Airlock | Set down |
| S19 | 1:01.5 | 2.5 | Commons | The lever |
| S20 | 1:04.0 | 3.5 | Airlock doorway | The klaxon, in one take |
| S21 | 1:07.5 | 5.0 | Exterior | Silence |
| S22 | 1:12.5 | 3.0 | Commons | Nothing happens |
| S23 | 1:15.5 | 1.5 | Commons | The alarm |
| S24 | 1:17.0 | 4.0 | Cargo | The ghost finds Sam |
| S25 | 1:21.0 | 1.5 | Cargo | The face changes |
| S26 | 1:22.5 | 6.5 | Commons to Cargo | The run, nine cuts |
| S27 | 1:29.0 | 2.0 | Cargo | Gun up |
| S28 | 1:31.0 | 1.5 | Cargo | Tap, tap |
| S29 | 1:32.5 | 2.0 | Black | One flash |
| S30 | 1:34.5 | 4.0 | Title | DRIFT STATION |
| S31 | 1:38.5 | 2.5 | Result card | THE INFILTRATOR WAS |
| S32 | 1:41.0 | 4.0 | Commons | Again |
| S33 | 1:45.0 | 2.5 | Slate | PLAY AGAIN |

---

## Act I: False calm

### S01. The dead station
**0:00.0 to 0:05.0 (5.0 s). Exterior, above the station's south-east corner.**

- **Characters:** none.
- **Action:** The station hangs in front of the gas giant with only its red emergency strips alive. Nothing moves except the pulse of those strips.
- **Camera:** The room lens, FOV 46. `(52, 16, 44)` to `(50.5, 15.4, 42)`, target `(22, 0, -6)` to `(21, 1, -7)`; a slow drift, the reverse of the current end card. Focus far, no blur.
- **Light and VFX:** Power `emergency`. Exposure 0.7 so the red strips are the only bright thing. Fade up from black over lt 0.0 to 1.2 (the only fade-in in the film).
- **Sound:** `ambience_emergency` at -14 dB from lt 0, and under it *new* `breath_helmet`: slow breathing inside a suit, close, at -10 dB. No music. At lt 4.0 a very low D drone begins, almost inaudible.
- **Text:** `ROW` at lt 2.2: `0:00  Round started with 6 crew aboard.`
- **Transition:** Cut.

### S02. Six arrive
**0:05.0 to 0:10.5 (5.5 s). Commons.**

- **Characters and staging:** All six walk in at 2.6 m/s and form a loose ring around `(0, 0, 0.3)`.
  - `jon` from the Medical corridor: `(0, 0, 6.6)` to `(0.1, 0, 2.3)`, starts lt 0.0. Happy.
  - `areeb` `(-6.8, 0, 0.6)` to `(-2.2, 0, 0.3)`, lt 0.2. Happy.
  - `maya` `(0.9, 0, 6.6)` to `(-1.5, 0, 2.0)`, lt 0.4. Happy.
  - `kit` `(-0.9, 0, -6.6)` to `(-0.3, 0, -2.0)`, lt 0.3. Neutral.
  - `zara` from the Command corridor: `(0.6, 0, -6.6)` to `(1.5, 0, -3.6)`, lt 0.9. She stops 1.5 m outside the ring. Suspicious.
  - `sam` last, from the Docking door: `(7.6, 0, 0.4)` to `(2.1, 0, 1.0)`, lt 1.3. Happy.
- **Action:** lt 2.6: Jon sees Sam and waves (`wave`, right arm). lt 3.5: Sam, arriving, answers with `helmet_tap`: two taps, contacts at lt 3.8 and 4.02. Jon nods. lt 4.4: Zara's head turns from the floor to the pair (look target: Sam). Nobody looks at Zara.
- **Camera:** The room lens, FOV 52, eye height. A slow quarter orbit, as the current `beat_assemble`: radius 5.0 around `(0, 1.15, 0.3)`, angle 205° to 240°, height 1.7 to 1.4. It ends as a loose two-shot of Jon and Sam with Zara small between their shoulders, out of focus. Focus `(1.0, 1.4, 1.6)`, depth 3.0, blur 0.05.
- **Light:** Power `emergency`. The red is warm here: add a soft amber spot from `(3, 2.8, 4)` on the Jon and Sam mark, energy 2.
- **Sound:** Six sets of `footstep_1..3` at -10 dB, staggered. *New* `helmet_tap` ×2 at lt 3.8 and 4.02, 0 dB, dry, centre. These two clicks are the loudest thing in Act I so far. Drone continues.
- **Text and UI:** Name tags (U5) on all six from lt 1.8 to 4.8. Role card (U3) lt 0.4 to 1.6, in the picture's upper third: the crew helmet icon, `YOU ARE CREW`, in blue.
- **Transition:** Cut on Zara's look.

### S03. A cell comes off the floor (dream cut only)
**0:10.5 to 0:13.0 (2.5 s). Medical, at the loose cell `(-4, 0, 23)`.**

- **Characters:** `jon`, crouched reach; we see only his gloves and forearms.
- **Action:** Two blue gloves come down into frame, open, and close around a power cell (C1 on both arms, `grip_large`). The cell's energy window brightens as it is lifted out of frame.
- **Camera:** The accusation lens used gently, FOV 26. Floor level, `(-4.9, 0.3, 23.5)`, target the cell `(-4, 0.35, 23)`, tilting up 8° with the lift. Focus on the cell, depth 0.4, blur 0.14, near blur on.
- **Light:** Power `emergency`. The cell's own amber light (`Vfx.CELL_COLOR`) is the key.
- **Sound:** `pickup` at lt 0.9; a small servo whirr (*new* `servo_reach`) at lt 0.3.
- **Text:** none.
- **Transition:** Cut.

### S04. The carry
**0:13.0 to 0:18.0 (5.0 s). Observation, the floor below the viewing deck.**

- **Characters and staging:** `jon` and `sam`, each carrying a cell, walk east side by side at 1.6 m/s: Jon `(27.6, 0, 20.4)` to `(35.6, 0, 20.4)`, Sam `(29.0, 0, 19.6)` to `(37.0, 0, 19.6)`. `zara` stands on the deck at the rail, `(33.6, 0.24, 17.4)`, half behind a pillar, body turned away, head following them (look target: Jon). Suspicious.
- **Action:** lt 1.6: Jon turns his head to Sam and nods. Sam's face flicks happy. lt 3.2: they pass under Zara. She does not move, except her head.
- **Camera:** The friend lens, FOV 38. Low, 0.8 m, tracking with them: `(27.0, 0.8, 23.6)` to `(30.6, 0.9, 23.4)`, target 1.5 m ahead of the pair at chest height. This is test still C's framing, with Zara moved into view at frame right. **Rack focus** at lt 3.2 to 3.9: from the pair (depth 2.5, blur 0.08) to Zara at 7 m.
- **Light:** Power `emergency`. The cells light the carriers' chests and visors from below. Zara gets a rim only: a cool spot from behind her, `(35, 2.6, 15.5)`, energy 3, so she is a shape.
- **Sound:** Two sets of carrying footsteps (slower, -8 dB). Drone. On the rack, one soft low note (the first score note that is not the drone).
- **Text:** none.
- **Transition:** Cut.

### S05. The third cell
**0:18.0 to 0:21.5 (3.5 s). Reactor, socket `reactor_1` at `(58, 0, 23)`.**

- **Characters and staging:** `sam` at `(58.0, 0, 21.85)`, yaw 0, holding a cell. `reactor_2` and `reactor_3` already filled.
- **Action:** An orange glove pushes the cell into the seat (lt 1.3, the existing reparent to the socket seat, plus C1: the right palm stays flat on the cell's cap). He holds it there for one beat. lt 2.7: the power wave. The glove is lit blue-white for six frames.
- **Camera:** The accusation lens, FOV 24. `(57.0, 1.2, 22.5)` to `(57.15, 1.2, 22.6)`, target the socket seat. The reactor core at `(62, 19.3)` is behind the camera and never in frame: we see its light arrive. Focus on the seat, depth 0.5, blur 0.12.
- **Light and VFX:** Power `emergency`, exposure 0.85. lt 1.3: `vfx.burst("insert_cell")`. lt 2.7: `vfx.burst("power_wave", Vfx.REACTOR_CORE)` and `restore_power_soft()`. White flash ramp to alpha 0.3 over lt 3.36 to 3.5, as the current cut.
- **Sound:** `insert_cell` at lt 1.3. A riser from it. **120 ms of silence** at lt 2.58. `power_up` at lt 2.7, retuned so its tail lands on D (the score enters on that D).
- **Text:** `ROW` at lt 1.7: `1:30  Sam inserted a power cell (3/3).`
- **Transition:** Cut through the flash.

### S06. Light on faces
**0:21.5 to 0:24.5 (3.0 s). Reactor.**

- **Characters and staging:** `sam` `(58.0, 0, 21.85)`, turning from the socket to `jon` at `(59.4, 0, 21.2)`. `areeb` `(60.6, 0, 22.3)` and `maya` `(57.0, 0, 20.4)` at the frame edges.
- **Action:** The flash fades (alpha 0.3 to 0 over lt 0 to 0.35). The room is still red. lt 0.8: the lights come up (`restore_power_soft()` again, from `emergency`) and every face goes happy within four frames of each other. lt 1.5: Sam gives Jon a `thumbs_up`. lt 2.1: Jon nods.
- **Camera:** The friend lens, FOV 36. From the socket wall looking west: `(60.9, 1.45, 23.0)` to `(60.6, 1.5, 22.8)`, target `(58.7, 1.5, 21.5)`. The core is off frame right and keys them from that side. Focus on Sam, depth 1.6, blur 0.08.
- **Light:** `emergency` to `restored` at lt 0.8. Reactor 0.75, glow 0.85, exposure 0.85.
- **Sound:** The D major bloom on lt 0.8 (the best moment of the current score, now on faces).
- **Text:** none.
- **Transition:** Cut on Jon's nod.

---

## Act II: The lights die

### S07. The vault opens
**0:24.5 to 0:29.5 (5.0 s). Command, the vault at `(0, 0, -23.5)`.**

- **Characters and staging:** Seen from behind, a loose crowd facing the vault: `zara` nearest, `(0.6, 0, -21.9)`; `jon` `(-1.3, 0, -20.6)`; `areeb` `(1.7, 0, -20.3)`; `maya` `(-2.5, 0, -19.9)`; `kit` `(2.7, 0, -19.6)`. `sam` hangs back at `(1.9, 0, -17.9)`, close to the lens at frame right, back to us, soft.
- **Action:** lt 1.4: the vault's field drops (`set_state(true, false, false)`); cyan spills over five visors. lt 2.4: Zara leans in, head tilted. lt 4.15: at the right edge, out of focus, Sam's arm comes up: `helmet_tap`, contacts at lt 4.45 and 4.67. **The focus does not move.** lt 5.0: mid-push, the cut.
- **Camera:** The room lens, FOV 46. Push `(0.2, 1.5, -15.4)` to `(0.0, 1.3, -18.2)`, target the core `(0, 1.15, -23.5)`. Focus on the core, depth 2.0, blur 0.1: the crowd is soft, Sam softer.
- **Light and VFX:** Power `restored`. A cyan spot on the vault as in the current `beat_vault`. The gas giant is over the far wall (Command looks north at it). Visor glints (C9) in cyan on Zara and Jon.
- **Sound:** The bloom thins to one held high note. `revive` at lt 1.4 for the field, as now. `helmet_tap` ×2 at lt 4.45 and 4.67, -6 dB, panned right, dry. The second tap is the last sound.
- **Text:** none. The story's most important event has no caption.
- **Transition:** **Smash cut to black** at lt 5.0, 0.33 s after the second tap, mid-move.

### S08. Lights out
**0:29.5 to 0:31.0 (1.5 s). Black.**

- **Picture:** Full black (`card(1.0)`); park the camera as `beat_title_sting` does.
- **Sound:** `power_down` at lt 0.0, 0 dB. Score cut dead. Then, close and dry: a scuffle of footsteps (lt 0.5 to 1.2), one `shove` at -4 dB (lt 0.8), one `drop` (lt 1.05). Somebody says nothing.
- **UI:** The real alert (U4), alone on black, lt 0.25 to 1.5: the blackout icon and `LIGHTS OUT`.
- **Transition:** Cut.

### S09. Visors and beams
**0:31.0 to 0:35.0 (4.0 s). Command.**

- **Characters and staging:** The S07 marks, but scattered by half a metre each (seeded), all in `brace`. Everyone shocked. `sam` is not in the room. `zara` is now at `(1.5, 0, -22.3)`, beside the vault.
- **Action:** Black, with five floating visor faces and five suits drawn in their own trim colours. lt 0.6, 1.0, 1.3, 1.9: four flashlights click on, one at a time (Jon's first). Beams sweep and cross. Heads snap to each beam (look targets jump). Nobody's beam is on the vault yet.
- **Camera:** The friend lens, FOV 40. Low, `(-3.4, 0.9, -17.4)` to `(-3.0, 1.0, -18.0)`, target `(0, 1.3, -21)`. Handheld starts here. Focus on Jon, depth 2.5, blur 0.1.
- **Light:** Power `blackout`, fog density 0.008. `flashlight()` per character with beam energy 0.07, lights off until each click. The vault area is kept out of every beam: aim sweeps at walls and at each other.
- **Sound:** *New* `flashlight_click` ×4. Breathing, footsteps shuffling. A low pulse begins on D and E-flat, slow.
- **Text:** `ROW` at lt 0.4: `2:02  Someone triggered a blackout.`
- **Transition:** Cut.

### S10. A hand in the dark
**0:35.0 to 0:37.5 (2.5 s). Command, at the vault. (This happened during S08. The cut is the trailer remembering.)**

- **Characters and staging:** The thief (the `sam` model) at `(0.45, 0, -22.75)`, yaw 180, with `set_lights(0, 0, 0)` (C8): no visor, no trim. Only an arm is ever in frame.
- **Action:** From frame right an arm enters, lit by nothing but the core: a glove, fingers opening (C1, `open`), reaching between the cage's bars. The fingers close on the core's cage (`grip_core`) at lt 1.3. lt 1.6: the core is lifted out of frame right, and its light goes with it. The frame falls to black over six frames.
- **Camera:** The accusation lens, FOV 24. `(-0.75, 1.2, -22.95)`, target `(0.1, 1.08, -23.35)`, static but for the handheld. Test still A proved the core lights a glove well by itself, and that cyan light turns an orange suit green-grey: the colour gives nothing away. It also showed today's shove pose stops 30 cm short, so the shot depends on C1; and the frame must stay tight enough to keep the chest plate out.
- **Light:** Power `blackout`. The vault field already down. No added lights.
- **Sound:** `servo_reach` at lt 0.2. `pickup` at lt 1.3, pitched down. The pulse drops out for this shot; only a breath.
- **Text:** none.
- **Transition:** Cut on black.

### S11. The empty vault
**0:37.5 to 0:40.0 (2.5 s). Command.**

- **Characters and staging:** `zara` at `(1.5, 0, -22.3)`, facing the vault. `jon` off camera at `(-1.6, 0, -19.6)`: the beam is his.
- **Action:** A beam finds the vault cage: empty, the socket's status lamp amber. Hold eight frames. lt 0.9: the beam whips right, the camera with it, and stops on Zara, one glove half raised towards the cage, visor shocked. She turns her head into the light (look target: the lens). lt 2.0: three more beams arrive on her from off frame, one after another.
- **Camera:** The friend lens, FOV 34, at Jon's eye: `(-1.6, 1.5, -19.8)`. Target from `(0, 1.1, -23.5)` to Zara's head `(1.5, 1.6, -22.3)`: a **whip pan** over five frames (lt 0.9 to 1.07). Focus follows the target, depth 1.2, blur 0.1.
- **Light:** Power `blackout`. One `flashlight` spot from the camera position, parented to the pan. Three more from `(-3, 1.4, -19)`, `(2.5, 1.4, -18.5)`, `(0.5, 1.4, -18)` switched on at lt 2.0, 2.15, 2.3.
- **Sound:** The two-hit motif (two low hits 0.22 s apart) as the beam lands on the empty cage, lt 0.25. A whoosh on the whip. `flashlight_click` ×3.
- **Text:** `ROW` at lt 1.3: `2:09  Someone took the core.`
- **Transition:** Cut.

### S12. Card
**0:40.0 to 0:41.5 (1.5 s). Black.**

- **Picture:** Black. Statement card (U9): `ONE OF YOU IS LYING.` Snaps in over three frames at lt 0.1, cuts out with the shot.
- **Sound:** A dissonant stab on the card, then near silence.
- **Transition:** Cut.

### S13. The gun
**0:41.5 to 0:45.0 (3.5 s). Security, the armory rack at `(37, 0, -24.5)`.**

- **Characters and staging:** `jon` at `(37.0, 0, -22.9)`, yaw 180, facing the rack. The gun is seated in the `armory` socket, unlocked.
- **Action:** ECU of the gun on the rack, its three charge cells lit. A blue glove comes in (C1), hesitates for six frames a hand's width away, then closes on the grip (`grip_gun`) at lt 1.3 and lifts it clear. lt 2.0: the camera tilts with the gun, up to Jon's visor: angry. He looks at the gun, then past the lens (look target: the Commons door).
- **Camera:** The accusation lens, FOV 24. `(37.9, 1.25, -23.7)` to `(38.0, 1.5, -23.2)`, target the gun's seat, then Jon's visor. Focus rides the gun, then the visor; depth 0.4, blur 0.14, near blur on.
- **Light:** Power `restored`. Cold. One warm kicker from below the rack, as the current `beat_gun`.
- **Sound:** A dry tick pattern starts (the clock). `pickup` at lt 1.3, with a metallic latch layered in.
- **Text and UI:** Statement card, small (5% height), lower third, lt 1.5 to 3.3: `ONE GUN. THREE SHOTS.` Ammo pips (U6) appear with it, bottom centre: three lit.
- **Transition:** Cut.

### S14. The ring
**0:45.0 to 0:49.0 (4.0 s). Commons.**

- **Characters and staging:** `zara` at `(-2.6, 0, 0)`, facing east; behind her, to the west, the dark airlock doorway. `jon` at `(1.4, 0, 0)`, facing her, aiming. `sam` at `(2.3, 0, 0.9)`, just behind Jon's shoulder. `areeb` `(-0.6, 0, 3.2)`, `maya` `(-0.4, 0, -3.2)`, `kit` `(-3.6, 0, 2.8)`.
- **Action:** Nobody moves for the first second and a half. Zara's hands are up (`surrender`). lt 1.5: Areeb, Maya and Kit each `step_back`, 0.15 s apart: the ring opens. lt 2.6: Sam looks from Zara to Jon and gives one nod. lt 3.3: Zara takes one step towards Jon.
- **Camera:** The room lens, FOV 54, **from above**: `(0.6, 3.6, 6.2)` to `(0.4, 3.0, 5.6)`, target `(-0.6, 0.9, 0)`. One of two shots in the film that look down. The floor lettering and the ring of bodies make the composition. Focus on the Jon and Zara line, deep.
- **Light:** Power `restored`, flat and bright. No added lights: this is how it looks when it happens to you.
- **Sound:** The clock, plus one layer. Room tone. Three shuffled steps for the step-backs.
- **Text and UI:** Name tags on Jon, Zara and Sam, lt 0.3 to 2.5. (Dream, D-U1: an amber SUSPECT chevron over Zara and `ROW` `3:31  Jon accused Zara.`)
- **Transition:** Cut on her step.

### S15. Five close-ups
**0:49.0 to 0:52.0 (3.0 s). Commons. Same marks.**

Five cuts inside one beat, as `beat_countdown` does it. All on the accusation lens.

| Cut | lt | Subject | Camera | Performance |
| --- | --- | --- | --- | --- |
| a | 0.0 to 0.9 | Zara | **Dolly zoom**: from 2.6 m at FOV 30 to 1.5 m at FOV 50, her visor held the same size while the room stretches behind her. Target her visor. | Pleading. Hands up, sagging. A `shake` of the head. |
| b | 0.9 to 1.6 | Jon | FOV 24, 1.1 m, a quarter off his aim line. | Angry. Tension 0.8. A cold glint (C9). |
| c | 1.6 to 2.2 | Sam, over Jon's shoulder | FOV 28. Focus on Sam, Jon's helmet soft in the foreground. | Neutral. One blink. That is all. |
| d | 2.2 to 2.6 | The muzzle | FOV 20, straight down the barrel, 0.5 m. | The three charge cells behind it, soft. |
| e | 2.6 to 3.0 | The trigger finger | FOV 20, from below the gun hand. | `grip_gun` to `grip_gun_trigger` over four frames (C10). |

- **Light:** Power `restored`. For a and b, one key each from the direction of the other person.
- **Sound:** The clock doubles on each cut. A tick on every cut. At lt 2.9, everything stops: 100 ms of silence.
- **Text:** none.
- **Transition:** **Smash cut** on the trigger.

### S16. The shot
**0:52.0 to 0:54.0 (2.0 s). Commons.**

- **Characters and staging:** Marks as S14, Zara one step forward at `(-1.9, 0, 0)`.
- **Action:** The first frame **is** the muzzle flash. `on_shot()`, `vfx.burst("muzzle_flash")`, `vfx.tracer` from the muzzle to Zara's chest, `vfx.burst("impact")` on her. She folds: `CrewRagdoll.spawn` with velocity `(-2.4, 0.6, 0.2)`; visor glitch, then the downed face. She slides to rest near `(-3.4, 0, 0.2)` by lt 1.3. Everyone else flinches (`play_hit` at quarter strength, or a `step_back`). Jon's gun stays up, shaking (tension 1.0).
- **Camera:** The friend lens, FOV 40, in profile from the south: `(-0.4, 1.1, 5.4)`, target `(-0.4, 1.1, 0)`, locked but for one hard shake on frame 1 (4 cm, decaying over 0.3 s). Jon at frame right, Zara left, the bolt crossing the whole frame.
- **Light and VFX:** Power `restored`. The flash is a real light for two frames (the vfx light slot). Zara's visor glint in bolt colour on frame 1 (C9).
- **Sound:** `gunshot` at lt 0.0, +2 dB, the loudest effect so far. The clock is gone. `downed` at lt 0.5. The two-hit motif, low, at lt 0.9.
- **Text and UI:** Ammo pips: the third pops and goes hollow at lt 0.0; pips out at lt 0.8. `ROW` at lt 1.0: `3:40  Jon shot Zara.`
- **Note:** Render this shot in one pass from its first frame, or replay recorded bone tracks: the ragdoll must not change between runs.
- **Transition:** Cut.

### S17. Sam carries her
**0:54.0 to 0:58.0 (4.0 s). Commons, towards the airlock.**

- **Characters and staging:** `sam` carries `zara` (downed, carried; the current `beat_drag` rig with C7's dangle) from `(-1.0, 0, 0.6)` to `(-8.2, 0, 0.2)` at 1.9 m/s. `jon` walks ahead and to the side, to the console: `(-2.5, 0, 2.2)` to `(-5.8, 0, 2.5)`, gun at low ready. `areeb`, `maya`, `kit` stand where they were, small in the background, watching.
- **Action:** Sam, the helpful one, does the carrying. Zara's head lolls with his stride; one arm swings. Jon does not look at them.
- **Camera:** The friend lens, FOV 44, from inside the airlock corridor looking east, low: `(-11.6, 0.95, -0.6)` to `(-11.2, 1.0, -0.7)`, target from `(-4, 1.3, 0.6)` to `(-7, 1.2, 0.4)`. They walk into the lens. Focus on Sam.
- **Light:** Power `restored`. The airlock doorway's hazard frame edges the shot, dark.
- **Sound:** Drums out. A tritone drone and a slow heartbeat. Heavy footsteps at -10 dB.
- **Text:** none.
- **Transition:** Cut as Sam's body fills the frame.

### S18. Set down
**0:58.0 to 1:01.5 (3.5 s). Inside the airlock, `(-12.5, 0, 0)`.**

- **Characters and staging:** `zara` lies in the foreground at `(-12.4, 0, 0.2)`, downed. `sam` straightens up over her at `(-11.3, 0, 0.1)` and walks out east to `(-8.4, 0, -0.9)`. Through the doorway beyond, `jon` at the console, `(-5.8, 0, 2.5)`.
- **Action:** Sam sets her down, turns and leaves without looking back. lt 2.6: in the foreground, soft, Zara's glove twitches; her visor flickers.
- **Camera:** The friend lens, FOV 34. On the airlock floor, `(-14.4, 0.4, -2.0)`, target `(-7.6, 1.3, 1.2)`. This is the key-art airlock framing (`32_moments_airlock.jpg`) from floor height: the body large and soft, the doorway, the console small and sharp beyond it. Focus on Jon, depth 2.5, blur 0.1. At lt 2.6 a short rack to the glove.
- **Light:** Power `restored`; airlock state `idle`. The chamber is dimmer than Commons: drop exposure to 0.8 and let the doorway be the light.
- **Sound:** Heartbeat. Sam's steps going away. A very small electronic flicker at lt 2.6.
- **Text:** none.
- **Transition:** Cut.

### S19. The lever
**1:01.5 to 1:04.0 (2.5 s). Commons, the airlock console at `(-6.5, 0, 3.5)`.**

- **Characters and staging:** `jon` at `(-5.8, 0, 2.5)`, facing the console, gun in the right hand at low ready. `sam` behind him at `(-7.6, 0, 0.6)`, at the mouth of the airlock corridor.
- **Action:** Jon's left hand goes out to the lever (C1) and stops short. Fingers flex. lt 0.9: he looks back over his shoulder at Sam (look target: Sam). lt 1.3: Sam gives one slow `nod`. lt 1.9: Jon's hand closes and pulls. The console goes active (`set_state(false, false, true)`).
- **Camera:** The accusation lens, FOV 28. `(-7.4, 1.4, 2.2)` to `(-7.2, 1.45, 2.4)`: the hand and lever in the foreground, Jon's visor above, Sam soft behind. **Roll** from 0° to 6° over the shot. Focus: hand, then rack to Sam for the nod, back to the hand.
- **Light:** Power `restored`. Under-light from the console in red, as the current `beat_console`, coming up from energy 0 to 7 on the pull.
- **Sound:** Heartbeat, faster. *New* `lever_clunk` at lt 1.9. Then nothing for four frames.
- **Text:** none.
- **Transition:** Cut on the clunk.

### S20. The klaxon
**1:04.0 to 1:07.5 (3.5 s). The airlock doorway, seen from Commons. One take, real time: the game's 3.5 s warning.**

- **Characters and staging:** `zara` starts on the floor at `(-12.4, 0, 0.2)`. `sam` stands just outside the doorway at `(-8.9, 0, -0.75)`, at the left edge of frame, back to us.
- **Action:**
  - lt 0.0: `station.set_airlock_state("warning")`. Red strobe. Zara is already rising (`play_get_up`, started 0.6 s before the cut so that she is on one knee on frame 1).
  - lt 0.7: she is up, and sees the open doorway and the lens. Pleading.
  - lt 1.0 to 1.9: she runs for it, `(-12.4)` to `(-10.4)` in x, one arm stretched at us (`lunge_reach`).
  - lt 1.9: Sam steps into the doorway (`(-9.4, 0, -0.1)`) and shoves (`play_shove`); contact at lt 2.07: `play_hit` on Zara, `vfx.burst("shove_impact")`. She goes back 2 m, stunned, arms flailing, to `(-12.5, 0, 0.1)`.
  - lt 3.3: she looks up. lt 3.5: the cut.
- **Camera:** The accusation lens, FOV 32. `(-7.9, 1.35, 0.55)`, target `(-10.9, 1.45, 0.05)`, pushing in 0.4 m. Roll held at 6°. Test still B is this frame: the hazard-striped OUTER HULL DOOR behind her is the backdrop. Focus on Zara throughout; Sam is a dark shape at the edge.
- **Light:** Power `restored` with exposure 0.7, so the strobe owns the frame. A red spot from `(-9.0, 2.4, 0.8)` on her, energy 6, switched with the strobe (2.6 Hz, as `station_fx`). Visor glint in red (C9).
- **Sound:** `airlock_warning` at lt 0.0, 0 dB, alone: no score. `shove` at lt 2.07. A tick at lt 0.5, 1.5 and 2.5.
- **Text and UI:** Countdown ring (U7), kind `airlock`, bottom centre: 3 at lt 0.5, 2 at lt 1.5, 1 at lt 2.5.
- **Transition:** **Hard cut** on lt 3.5, the instant the count ends.

### S21. Silence
**1:07.5 to 1:12.5 (5.0 s). Exterior, off the station's west hull.**

- **Characters and staging:** `zara`, the weightless ragdoll of the current `beat_spaced`: spawned at `(-14.4, 0.4, 0)`, velocity `(-2.2, 0.45, 1.0)`, spin 3.2 rad/s.
- **Action:** The outer door is open. Frost streams out. A small purple figure turns slowly, end over end, across the frame towards the gas giant, getting smaller. Nothing else.
- **Camera:** The room lens, FOV 50. **Locked off, no handheld, roll back to 0°:** `(-17.6, 1.3, 6.4)`, target `(-19.6, 2.2, -1.2)`. The hull is a white wall at frame right, the planet fills the left. She crosses from right to left and is not followed.
- **Light and VFX:** `set_airlock_state("venting")`, `vfx.burst("airlock_vent")` at lt 0.0, `vfx.burst("spaced")` at lt 0.5, as now.
- **Sound:** **Nothing. Digital silence from lt 0.0 to 1.5**: no ambience, no score, no effect, not even the vent. At lt 1.5, `breath_helmet`, very quiet (-18 dB), slowing. At lt 4.2 it stops.
- **Text:** `ROW` at lt 2.5, held to the end: `4:05  Zara was spaced.`
- **Note:** As S16: render in one pass, or replay a recording.
- **Transition:** Hard cut.

---

## Act III: What happened

### S22. Nothing happens
**1:12.5 to 1:15.5 (3.0 s). Commons.**

- **Characters and staging:** Four people: `jon` at `(-4.6, 0, 2.2)`, turned from the console towards the room; `areeb` `(-0.6, 0, 3.2)`, `maya` `(-0.4, 0, -3.2)`, `kit` `(-3.6, 0, 2.8)`. Sam's mark by the corridor mouth is empty. Nobody remarks on it.
- **Action:** They wait for the round to end. Spacing the infiltrator ends it on the spot. It does not end. lt 1.0: Maya looks at Areeb. lt 1.6: Areeb looks at Jon. lt 2.0: Jon looks down at the gun in his hand, and it sinks to low ready (C10).
- **Camera:** The room lens, FOV 54, eye level, static: `(4.6, 1.5, 4.4)`, target `(-2, 1.2, 0.6)`. Wide, with too much empty floor in it.
- **Light:** Power `restored`; airlock state `idle`. Flat.
- **Sound:** `ambience_station` at -16 dB. One thin high tone (*new* `tinnitus`), fading up.
- **Text:** none. No row: nothing happened.
- **Transition:** Cut on the alarm.

### S23. The alarm
**1:15.5 to 1:17.0 (1.5 s). Commons.**

- **Characters:** `jon`, same mark.
- **Action:** Red washes in from the east. Jon's head snaps towards the Docking door (look target `(8, 1.5, 0)`); behind him three heads do the same, two frames apart. His face: shocked, then angry.
- **Camera:** The accusation lens, FOV 28, `(-2.4, 1.5, 0.9)`, target Jon's visor. A short hard push of 0.3 m. Handheld back on, doubled.
- **Light and VFX:** At lt 0.0, `station.set_state("emergency", 0.0)` and `vfx.burst("alarm_strobe")` at the Docking door. From here to S29 the red is the cold alarm red.
- **Sound:** `alarm_pod` at lt 0.0, 0 dB, cutting the tinnitus tone. The score slams in at 120 BPM on the downbeat.
- **Text:** `ROW` at lt 0.3: `4:11  The cargo pod is armed.`
- **Transition:** Cut.

### S24. The ghost finds Sam
**1:17.0 to 1:21.0 (4.0 s). Cargo. Two set-ups in one beat.**

**a. lt 0.0 to 1.8: she comes through the wall.**
- **Characters:** `zara` as a ghost (`set_ghost(true)`, `vfx.attach_item_fx(ghost, "ghost")`), drifting north through Cargo's south wall: `(39.6, 0.3, 7.6)` to `(39.8, 0.3, 5.4)`.
- **Action:** A ripple spreads on the wall, and a pale purple figure slides out of it, looking around. At lt 1.4 she stops as if she had hit something. Shocked (C11: ghosts take any face).
- **Camera:** The friend lens, FOV 36. `(36.0, 1.4, 3.4)`, target her chest; in profile, 4.5 m away, against the dark wall. Test still D showed the ghost shader turns to a bright mesh close to the lens and hides whatever is behind it, so she is never nearer than 3 m and never in front of the subject.
- **Sound:** `ghost_drift` at lt 0.0, -4 dB. The score drops to pulse only, low-passed, as if heard through a wall.

**b. lt 1.8 to 4.0: what she sees.**
- **Characters and staging:** `sam` at `(42.15, 0, 4.5)`, yaw 90, facing the pod, back to us. The core is seated in the `pod` socket: `set_state(true, false, true)`.
- **Action:** He stands quite still with one hand resting on the core. The pod's own sign reads CARGO POD, and under it POD ARMED, in the station's lettering.
- **Camera:** Her eye. The friend lens, FOV 34: `(39.9, 1.55, 5.5)` pushing to `(40.5, 1.55, 5.2)`, target Sam's helmet. Test still D's framing, without the ghost in it. Focus on Sam, depth 1.5.
- **Light:** Power `emergency`. A red spot from `(43.6, 1.0, 6.0)` on him, energy 8. Core cyan on his chest and hand.
- **Sound:** The score un-filters over this half. `alarm_pod` continuing.
- **Text and UI:** Countdown ring, kind `pod`, appears at lt 1.8 reading 16 (15.7), running in real time so that it reaches 12.0 as S26 begins.
- **Transition:** Cut.

### S25. The face changes
**1:21.0 to 1:22.5 (1.5 s). Cargo.**

- **Characters:** `sam`, same mark.
- **Action:** His head turns over his left shoulder, 65°, the chest following by a third (C2). The face is happy: the same face as the thumbs-up. lt 0.7: the visor tears for three frames and comes back as the red V (`set_expression("angry", 0, 0.0, true)`, C4).
- **Camera:** The accusation lens, FOV 22. `(41.0, 1.62, 5.6)`, target his visor. Static. The visor fills a third of the frame.
- **Light:** As S24b. A red glint on the visor (C9).
- **Sound:** On the glitch: a burst of static and the two-hit motif, at full weight for the first time.
- **Text and UI:** Role card (U3), in the same place as in S02, lt 0.7 to 1.5: the infiltrator helmet icon, `YOU ARE THE INFILTRATOR`, in red. The ring is hidden for this shot and returns in S26.
- **Transition:** Cut.

### S26. The run
**1:22.5 to 1:29.0 (6.5 s). Commons, Docking, Cargo. Nine cuts in one beat.**

Jon's run is continuous under the cuts: `x = -4 + 6.2 · lt` along `z = 0.6`, east, at full run speed with the gun (C10). He passes the Docking door at lt 1.9, the shuttle at lt 3.9, and enters Cargo at lt 6.0.

Three set-ups:
- **A, Jon:** the camera runs backwards 3.2 m ahead of him at 1.3 m height, FOV 40, target his visor, with a footfall shake (2 cm on each plant). Head-on, so the lack of motion blur does not show. Light follows the rooms: red, alarm strobes passing.
- **B, the pod:** FOV 28, `(40.2, 1.0, 6.2)`, target the pod socket: the core in its seat, Sam's legs, the red beacon. Slow push.
- **C, the ghost:** FOV 36, from the pod's side, `(43.0, 1.5, 6.6)`, target Sam's shoulder: Sam in profile, calm, and ghost Zara beyond him at `(41.2, 0.2, 3.9)`, 3 m from the lens, `pound`ing at his back. Her fists go through him.

| Cut | lt | Set-up | Note |
| --- | --- | --- | --- |
| 1 | 0.0 to 1.2 | A | Jon breaks into the run from the console. |
| 2 | 1.2 to 2.2 | B | The ring reads 11. |
| 3 | 2.2 to 3.1 | A | The Docking door; the shuttle coming up behind him. |
| 4 | 3.1 to 3.9 | C | She is screaming. No sound from her. |
| 5 | 3.9 to 4.6 | A | Past the shuttle, the crew's way out, at full speed. He does not look at it. |
| 6 | 4.6 to 5.2 | B | The ring reads 7. |
| 7 | 5.2 to 5.7 | A | The Cargo corridor. |
| 8 | 5.7 to 6.1 | C | Her hands, through his chest. |
| 9 | 6.1 to 6.5 | A | Into Cargo. |

- **Light:** Power `emergency` throughout. `vfx.countdown_pulse` at the pod on each B cut.
- **Sound:** Full drums at 120 BPM, the alarm call on top, one layer added per cut, a hit on every cut. Footsteps on A at 3.6 per second. On the C cuts, the mix ducks 6 dB for the length of the cut: her silence.
- **Text and UI:** Countdown ring, kind `pod`, real time, 12.0 at lt 0.0 to 5.5 at lt 6.5. Visible on A and B, hidden on C.
- **Transition:** Cut.

### S27. Gun up
**1:29.0 to 1:31.0 (2.0 s). Cargo.**

- **Characters and staging:** `jon` stops at `(37.6, 0, 1.2)`, facing south-east, and levels the gun at Sam. `sam` at the pod, `(42.15, 0, 4.5)`, back still turned. Ghost `zara` at `(40.6, 0.2, 2.6)`, between them and off to one side, looking from one to the other.
- **Action:** Jon skids (0.4 m of slide), raises the gun (`set_aiming(true)`), holds. Tension 1.0: the muzzle is not steady.
- **Camera:** The friend lens, FOV 36, over Jon's gun shoulder: `(36.6, 1.55, 0.5)`, target Sam. **Rack focus** at lt 0.9 to 1.4 from the gun's charge cells (two lit, one dark) to Sam, 5.4 m away.
- **Light:** Power `emergency`. Sam is a silhouette against the pod's red beacon.
- **Sound:** The drums drop to half time. Jon's breath. Ticks, one per second.
- **Text and UI:** Ring: 5.5 down to 3.5. Ammo pips return: two lit.
- **Transition:** Cut.

### S28. Tap, tap
**1:31.0 to 1:32.5 (1.5 s). Cargo.**

- **Characters:** `sam`, same mark.
- **Action:** He turns round, unhurried (yaw 90 to -60 over lt 0.0 to 0.6), to face Jon, which is to say the lens. Smug (C3). He raises his right hand: `helmet_tap`, started at lt 0.65, contacts at lt 0.95 and 1.17. On the second tap his visor goes dark (`set_lights(0, ...)`).
- **Camera:** The accusation lens, FOV 26, at Jon's eye: `(37.9, 1.6, 1.4)`, target Sam's visor, 5 m away, pushing 0.5 m. Sam is centred, looking at us.
- **Light:** As S27, with a soft frontal fill, energy 1.5, so the face reads.
- **Sound:** The score **stops dead** at lt 0.9. `helmet_tap` at lt 0.95 and 1.17, 0 dB, dry, centre: the same two clicks as 0:08 and 0:28.
- **Text and UI:** Ring: 3.5 down to 2.0. It dies with the lights.
- **Transition:** **Smash cut to black** at lt 1.5: 0.33 s after the second tap, the same gap as S07.

### S29. One flash
**1:32.5 to 1:34.5 (2.0 s). Black, and two frames of Cargo.**

- **Picture:** lt 0.0 to 0.8: black. Two ammo pips, bottom centre, are the only thing on screen. lt 0.8 to 0.867 (**two frames**): the S28 camera, power `blackout`; the muzzle flash lights Sam **already in mid-air towards the lens**, 1.5 m away, arms out (the shove pose at full thrust), visor dark. `vfx.burst("muzzle_flash")`, `vfx.tracer` going wide past his shoulder. lt 0.867 to 2.0: black. The second pip pops and goes hollow. One left.
- **Sound:** lt 0.0 to 0.8: silence. `gunshot` at lt 0.8, +3 dB. `shove` at lt 0.93. `drop` at lt 1.3 (a gun on a deck). The tail rings out alone.
- **Text:** none. We never learn how it ends.
- **Transition:** Cut on the title hit.

### S30. Title
**1:34.5 to 1:38.5 (4.0 s). Black.**

- **Picture:** lt 0.0: the logo lockup (U8) lands, state `crew`: DRIFT over STATION, the O a visor with two white eyes. lt 1.2: the eyes snap to the red V. lt 1.8: beneath it, `card_line`: `2–8 friends. One of you is lying.`
- **Sound:** The title hit at lt 0.0 (D, the heroic swell from the current score, shortened). The sub-boom on the flip, lt 1.2. The swell is cut off at lt 4.0, not faded.
- **Transition:** Cut.

### S31. The result
**1:38.5 to 1:41.0 (2.5 s). The result card (U2), full frame, over a blurred, darkened Cargo.**

- **Picture:** lt 0.0: `THE INFILTRATOR WAS` and a slot cycling through six avatars and names, twelve a second: Jon, Zara, Areeb, Maya, Kit, Sam, Jon, Zara. lt 1.4: it stops on **Sam**, in orange, with one white frame behind it. lt 1.7: one timeline row resolves beneath: `2:02  Someone` becomes `Sam triggered a blackout.`; and a red chip on another: `4:05  Zara was spaced.  ZARA WAS CREW`.
- **Sound:** Dry. *New* `slot_tick` on every change, *new* `slot_stop` at lt 1.4. No music.
- **Transition:** Cut.

### S32. Again
**1:41.0 to 1:45.0 (4.0 s). Commons. A new round.**

- **Characters and staging:** All six on the spawn ring: `StationLayout.spawn_point(i, 6)`, radius 3.5, in the order jon, maya, zara, kit, areeb, sam, all facing the centre. Everyone alive, clean, happy. Zara too.
- **Action:** lt 0.0 to 0.9: six friends, as if nothing had happened. lt 1.0: five of them `step_back` from Sam, within three frames of each other; five heads turn to him. lt 1.6: Zara `point`s at him, arm straight (angry). lt 2.2: Sam looks left, looks right (look targets), smug; lt 2.9: face to happy, and he `wave`s.
- **Camera:** The room lens, FOV 50, **from above** (the second and last look down): `(0, 5.4, 7.4)` to `(0, 5.0, 6.8)`, target `(0, 0.8, 0)`. The ring, the floor lettering, and after lt 1.0 the hole in the ring around one orange figure. The gas giant is over the far wall.
- **Light:** Power `emergency`: a round starts in the red. It is warm again, exactly as in S02.
- **Sound:** `lobby_theme`, its first bar, bright, from lt 0.0 at -8 dB. Five steps at lt 1.0. It plays on, innocent, and is cut mid-phrase.
- **Text and UI:** Name tags on all six from lt 0.2. (Dream, D-U4: open on the lobby card with a small red V on Sam's.)
- **Transition:** Cut, mid-wave, mid-phrase.

### S33. Slate
**1:45.0 to 1:47.5 (2.5 s). Black.**

- **Picture:** The one-line lockup, small, at the top. Centre: the real primary button, `PLAY AGAIN`, pulsing once a second. Beneath it, amber: `ANDROID · PC`. Fade to black over lt 2.0 to 2.5 (the only fade-out in the film).
- **Sound:** `ui_click` at lt 0.1. One last pair of low hits, 0.22 s apart, at lt 0.9. Out.
- **Transition:** End.

---

## Cue summary for the score

Hits that the music must land on (full cut; subtract 2.5 s after 0:10.5 for the must-have cut):

| Time | Event |
| --- | --- |
| 0:04.0 | D drone enters |
| 0:08.80, 0:09.02 | Taps (S02) |
| 0:20.58 | 120 ms silence |
| 0:20.70 | Power hit |
| 0:22.30 | Bloom: lights on faces |
| 0:25.90 | Vault field drops |
| 0:28.95, 0:29.17 | Taps (S07) |
| 0:29.50 | Blackout: score out |
| 0:31.00 | Dread pulse in |
| 0:37.75 | Two-hit motif: the empty vault |
| 0:40.10 | Card stab |
| 0:41.50 | Clock starts; layers at 0:45.0, 0:49.0, 0:49.9, 0:50.6, 0:51.2, 0:51.6 |
| 0:51.90 | 100 ms silence |
| 0:52.00 | Gunshot: clock out |
| 0:52.90 | Two-hit motif |
| 0:54.00 | Tritone drone and heartbeat |
| 1:03.40 | Lever: all out |
| 1:04.00 to 1:07.50 | Klaxon alone |
| 1:07.50 to 1:09.00 | Digital silence |
| 1:12.50 | Tinnitus tone |
| 1:15.50 | Alarm: 120 BPM, downbeat |
| 1:17.00 to 1:18.80 | Low-passed |
| 1:21.70 | Glitch: two-hit motif, full |
| 1:22.50 | The run: hits at 1:23.7, 1:24.7, 1:25.6, 1:26.4, 1:27.1, 1:27.7, 1:28.2, 1:28.6 |
| 1:29.00 | Half time |
| 1:31.90 | Score out |
| 1:31.95, 1:32.17 | Taps (S28) |
| 1:33.30 | Gunshot |
| 1:34.50 | Title hit |
| 1:35.70 | Sub-boom: the logo flips |
| 1:38.50 | Out |
| 1:41.00 | Lobby theme, bar 1 |
| 1:45.00 | Cut. Click. Last two hits at 1:45.90 |
