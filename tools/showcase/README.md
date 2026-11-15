# Key-art showcase

Store-page quality stills of Drift Station, rendered in the real station with
the real character model, gloves, props, sockets and VFX. Nothing here ships in
the game; it is a photo studio on top of it. The trailer in `tools/trailer/`
reuses the same studio rig.

| File | What it does |
| --- | --- |
| `showcase.gd` | Entry point (`extends SceneTree`): parses arguments, sets still-image quality (MSAA, shadow atlas, bokeh), runs the sets. |
| `studio.gd` | The studio rig: builds the station, sockets and VFX once; per-shot set reset; crew placement, posing and pose overrides; items; lights; the floating product stage; camera with depth of field; capture. |
| `set_characters.gd` | Set 1: lineup hero, colour roster, every LED face, suit variants, portraits, "one of you is lying", turntable, squad selfie. |
| `set_station.gd` | Set 2: exterior with the planet, tilt-shift overhead, every room's establishing shot, the corridor, the power wave. |
| `set_items.gd` | Set 3: product shots of the gun, cell and core, the three together, every socket. |
| `set_moments.gd` | Set 4: core run, shove, gun stand-off, rescue, airlock, ghost, blackout, shuttle, spaced. |

## Running

```sh
GODOT=tools/.cache/godot-4.7.2/Godot_v4.7.2-stable_linux.x86_64
xvfb-run -a -s "-screen 0 1920x1080x24" $GODOT --path . \
    --rendering-method mobile --resolution 1920x1080 --fixed-fps 30 \
    --script res://tools/showcase/showcase.gd -- --out /tmp/keyart \
    [--set characters,items] [--only lineup,ghost] [--preview]
```

- `--out <dir>`: frames go to `<dir>/1_characters`, `2_station`, `3_items`,
  `4_moments`. Required.
- `--set name[,name...]`: only these sets (`characters`, `station`, `items`,
  `moments`).
- `--only key[,key...]`: only these shots (keys are in each set's `SHOTS`).
- `--preview`: no MSAA, small shadow atlases, low-quality bokeh. Use it with a
  small `--resolution` (e.g. 960x540) while composing.
- `--fixed-fps 30` matters: VFX bursts, trails and strobes advance by a fixed
  1/30 s per rendered frame, so each shot lands on the frame it was timed for
  however slow the renderer is. Without it the script warns.
- Cost on software Vulkan (lavapipe, 4 cores): about a minute to build the
  station, then roughly 1-2 minutes per 1080p frame; a preview frame at 960x540
  is several times cheaper. On a shared machine, queue renders (this project
  uses `scratchpad/coordination/heavy.sh`).
- Each saved frame prints `showcase: saved <path>` and the run ends with
  `showcase: done, N shot(s), M failed` (exit code 1 if any failed). Under
  lavapipe the engine can stall during shutdown after the last 3D frame; that
  line means everything is saved, so wrapping the command in `timeout` or
  stopping it after the line is safe.

## Shot list

| Set | Key | Output | Shot |
| --- | --- | --- | --- |
| characters | `lineup` | `01_crew_lineup.png` | Seven crew in a V in Commons, gas giant behind, low camera. |
| | `roster` | `02_roster_all_colours.png` | All eight colours on the floating stage. |
| | `faces` | `03_expressions.png` | Every LED face: neutral, happy, shocked, angry, suspicious, hurt, downed, ghost. |
| | `variants` | `04_variants.png` | The four helmet and backpack styles. |
| | `portraits` | `05a`-`05d` | Four 3/4 helmet portraits with rim light and shallow focus. |
| | `lying` | `06_one_of_you_is_lying.png` | Five crew in Command; focus on the suspicious one at the back. |
| | `turntable` | `07_turntable_trio.png` | Front, 3/4 and back of one crewmate. |
| | `selfie` | `08_squad_selfie.png` | Orange points at the lens, purple photobombs. |
| station | `exterior` | `01_exterior_planet.png` | The station in front of the gas giant. |
| | `overhead` | `02_overhead_tilt_shift.png` | Tilt-shift view down into the open-topped station. |
| | `commons` ... `observation` | `03`-`11` | Establishing shot of each room in its signature light. |
| | `reactor_wave` | `09_reactor_power_wave.png` | The last cell goes in; the power wave rolls out. |
| | `corridor` | `12_corridor.png` | The long Command-Security corridor in emergency red. |
| items | `gun_hero`, `cell_hero`, `core_hero` | `01`-`03` | Product shots on the floating stage. |
| | `items_trio` | `04_items_trio.png` | Gun, cell and core together. |
| | `sockets` | `05_sockets.png` | Every interaction socket in one arc. |
| moments | `core_run` | `01_core_run.png` | Sprinting with the core down a corridor, chaser behind. |
| | `shove` | `02_shove.png` | Mid-shove impact; the victim loses a power cell. |
| | `gun` | `03_gun_standoff.png` | Over the shoulder: the gun levelled, the target's hands up. |
| | `rescue` | `04_rescue.png` | Carrying a downed crewmate to the medbay. |
| | `airlock` | `05_airlock.png` | Trapped in the airlock; a sinister operator at the console. |
| | `ghost` | `06_ghost.png` | A ghost drifts past the Reactor as power returns. |
| | `blackout` | `07_blackout.png` | Flashlights in the blackout. |
| | `shuttle` | `08_shuttle_escape.png` | Loading the core into the shuttle during the countdown. |
| | `spaced` | `09_spaced.png` | The airlock vents; a crewmate tumbles out towards the gas giant. |

## Adding a shot

1. Pick the set it belongs to and write a function there named
   `shot_<something>(out: String) -> Error`, with a short header comment saying
   what the frame is about. The usual shape:

   ```gdscript
   ## 13 Example: one line on the story of the frame.
   func shot_example(out: String) -> Error:
       begin_shot("restored", 1513)              # power state + random seed
       var m := crew("teal", Vector3(0, 0, 2), 0.0, "happy", 0, 7)
       hold(m, "cell")                            # items first: they pick the grips
       pose(m, 1.4, 0.0, true)                    # step the rig (carrying) to a pose
       spot(Vector3(-2, 3, 5), Vector3(0, 1.2, 2), WARM, 5.0, 35.0, 9.0, true, 0.3)  # key
       spot(Vector3(1.5, 2.4, -1), Vector3(0, 1.3, 2), COOL, 8.0)                     # rim
       frame(Vector3(0.6, 1.4, 5.5), Vector3(0, 1.3, 2), 30.0, Vector3(0, 1.6, 2))
       return await capture(out, "13_example.png")
   ```

2. Add `{"key": "example", "method": "shot_example"}` to that set's `SHOTS`.
3. Preview just that shot (`--preview --resolution 960x540 --only example`),
   look at the PNG at full size, iterate, then render it at 1920x1080.

A new set is a script that `extends "res://tools/showcase/studio.gd"` with
`const FOLDER` and `const SHOTS`; add it to `SETS` in `showcase.gd`.

### Studio helpers (`studio.gd`)

- `begin_shot(power, seed)`: frees the previous set, sets the power state
  (`emergency`, `restored`, `blackout`), resets the airlock, sockets and camera.
- `crew(colour, pos, yaw_deg, face, variant, number)`: adds a `CrewModel`;
  colours are the eight player colours by name (`COLORS`). `face(m, point)`
  turns a crewmate towards a floor point.
- Posing: `pose(m, seconds, speed, carrying, stunned)` steps `set_motion` at a
  fixed 60 Hz; `pose_stride(m, speed, phase, carrying)` stops a walk or run on a
  chosen point of the gait cycle; `pose_overlay(m, t)` advances a `play_shove()`
  / `play_hit()` to `t` seconds. Keep idle holds under about 5 s, or the
  model's random fidgets start (trigger one on purpose with `play_fidget(kind)`).
- Pose overrides the model has no API for yet: `hands_up(m)`, `raise_arm(m,
  side)`, `turn_head(m, yaw_deg, pitch_deg)` and `glove(m, side, pose)` (a
  CrewHand pose such as `open`, `point`, `thumbs_up`, `wave`, `fist`; side 0
  left, 1 right). Call them after the last pose step; `clear_hit_flash(m)` keeps
  a `play_hit()` recoil without its red "shot" flash.
- Props: `hold(m, kind)` gives a crewmate a cell, core or gun like gameplay
  (`carry_anchor` / the right glove's `hand_anchor`, plus `set_held_item` so the
  gloves grip it; cells and cores get their glow fx). Call it before posing.
  `seat_item(socket_id, kind)` seats an item in a socket; `place_item(kind,
  xform)` puts one in the world; `fly(node, from, to, arc, frames)` throws it so
  trails draw a real path; `flashlight(m, target)` gives a crewmate a gameplay
  flashlight plus a soft beam cone; `muzzle(gun)` finds the gun's muzzle.
- Product stage: `stage(radius)` builds a dark glossy disc high above the
  station (stars and the gas giant behind), `stage_lighting()` gives it a night
  studio look (pair with `begin_shot("blackout", ...)`), `stage_item(kind,
  xform)` stands an item on it.
- Lights: `spot(...)`, `omni(...)` and `three_point(...)`. Keep rims and fills
  shadowless; one shadowed key per shot is plenty. A low `specular` on frontal
  keys keeps them from washing out the glossy visor.
- `frame(pos, target, fov, focus, depth, blur, near_blur, roll_deg)`: aims the
  camera and sets `CameraAttributesPractical` depth of field so that a slab of
  `depth` metres around `focus` stays sharp.
- `capture(out, file, warm)`: freezes the crew (faces settle, no blinks), lets
  `warm` frames render and saves the PNG. Fire VFX bursts a few frames before
  `capture` (`await wait(n)` first) so they are mid-flight when the frame is taken.
