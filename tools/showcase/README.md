# Key-art showcase

Store-page quality stills of the Drift Station crew, rendered in the real
station with the real character model, props and VFX. Nothing here is used by
the game; it is a photo studio on top of it.

| File | What it does |
| --- | --- |
| `showcase.gd` | Entry point (`extends SceneTree`): parses arguments, sets still-image quality (MSAA, shadow atlas, bokeh), runs the shot list. |
| `studio.gd` | The studio rig: builds the station, sockets and VFX once; per-shot set reset; crew placement and posing; lights; camera with depth of field; capture. |
| `shots.gd` | The shot list (`SHOTS`) and one function per shot. Extends `studio.gd`. |

## Running

```sh
GODOT=tools/.cache/godot-4.7.2/Godot_v4.7.2-stable_linux.x86_64
xvfb-run -a -s "-screen 0 1920x1080x24" $GODOT --path . \
    --rendering-method mobile --resolution 1920x1080 --fixed-fps 30 \
    --script res://tools/showcase/showcase.gd -- --out /tmp/keyart [--only lineup,ghost]
```

- `--out <dir>`: where the PNGs go (created if missing). Required.
- `--only key[,key...]`: render only these shots (keys are listed in `SHOTS`
  in `shots.gd`, e.g. `lineup`, `portraits`, `blackout`). Use it while iterating:
  software Vulkan (lavapipe) needs roughly 1 to 2 minutes per frame at 1080p,
  plus about a minute to build the station.
- `--fixed-fps 30` matters: VFX bursts, trails and strobes advance by a fixed
  1/30 s per rendered frame, so each shot lands on the frame it was timed for
  however slow the renderer is. Without it the script warns.
- Each saved frame prints `showcase: saved <path>`. The exit code is non-zero if
  any shot failed to save.
- On some software-Vulkan setups the engine can stall on exit after the last
  frame is saved; wrapping the command in `timeout` is harmless.

## Shot list

| Key | Output | Shot |
| --- | --- | --- |
| `lineup` | `01_crew_lineup.png` | Seven crew in a V in Commons, gas giant behind, low camera. |
| `lying` | `02_one_of_you_is_lying.png` | Five crew in Command under emergency red; focus on the suspicious one at the back. |
| `portraits` | `03a`-`03d` | Four 3/4 helmet portraits with rim light and shallow focus. |
| `core_run` | `04_core_run.png` | Sprinting with the core down a corridor, chaser behind. |
| `shove` | `05_shove.png` | Mid-shove impact; the victim drops a power cell. |
| `gun` | `06_gun_question.png` | Aiming the gun in Security; the target's hands are up. |
| `rescue` | `07_rescue.png` | Carrying a downed crewmate to the medbay. |
| `airlock` | `08_airlock.png` | Trapped in the airlock; a sinister operator at the console. |
| `ghost` | `09_ghost.png` | A ghost drifts through the Reactor as power returns. |
| `blackout` | `10_blackout.png` | Flashlights in the blackout. |
| `shuttle` | `11_shuttle_escape.png` | Loading the core into the shuttle during the countdown. |
| `turntable` | `12_turntable_trio.png` | Front, 3/4 and back of one crewmate. |
| `overhead` | `13_overhead_station.png` | Tilt-shift view down into the station. |
| `selfie` | `14_squad_selfie.png` | The squad selfie. |

## Adding a shot

1. Write a function in `shots.gd` named `shot_<something>(out: String) -> Error`
   with a short header comment saying what the frame is about. The usual shape:

   ```gdscript
   ## 15 Example: one line on the story of the frame.
   func shot_example(out: String) -> Error:
       begin_shot("restored", 1515)              # power state + random seed
       var m := crew("teal", Vector3(0, 0, 2), 0.0, "happy", 0, 7)
       pose(m, 1.4)                               # step the rig to an idle pose
       spot(Vector3(-2, 3, 5), Vector3(0, 1.2, 2), WARM, 5.0, 35.0, 9.0, true)  # key
       spot(Vector3(1.5, 2.4, -1), Vector3(0, 1.3, 2), COOL, 8.0)                # rim
       frame(Vector3(0.6, 1.4, 5.5), Vector3(0, 1.3, 2), 30.0, Vector3(0, 1.6, 2))
       return await capture(out, "15_example.png")
   ```

2. Add `{"key": "example", "method": "shot_example"}` to `SHOTS`.
3. Render just that shot with `--only example`, look at the PNG at full size,
   and iterate.

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
- Pose overrides the model has no API for yet: `hands_up(m)` and
  `turn_head(m, yaw_deg, pitch_deg)`. Call them after the last pose step.
- Props: `hold(anchor, kind)` parents a cell, core or gun to `carry_anchor` /
  `hand_anchor` like gameplay (cells and cores get their glow fx);
  `place_item(kind, xform)` puts one in the world; `fly(node, from, to, arc,
  frames)` throws it so trails draw a real path; `flashlight(m, target)` gives a
  crewmate a gameplay flashlight plus a soft beam cone.
- Lights: `spot(...)`, `omni(...)` and `three_point(...)`. Keep rims and fills
  shadowless; one shadowed key per shot is plenty.
- `frame(pos, target, fov, focus, depth, blur, near_blur, roll_deg)`: aims the
  camera and sets `CameraAttributesPractical` depth of field so that a slab of
  `depth` metres around `focus` stays sharp.
- `capture(out, file, warm)`: freezes the crew (faces settle, no blinks), lets
  `warm` frames render and saves the PNG. Fire VFX bursts a few frames before
  `capture` (`await wait(n)` first) so they are mid-flight when the frame is taken.
