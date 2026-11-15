# Trailer

An ~80 s, 1280x720, 30 fps trailer cut in code, rendered in the real station
with the real crew, items and VFX, plus a 15 s vertical teaser.

| File | What it does |
| --- | --- |
| `cut.gd` | The cut: `BEATS` (method, seconds) and one method per beat. Each beat dresses its set on its first frame, then drives crew (`set_motion`, expressions, holds, shoves), camera moves (eased lines and Catmull-Rom splines with depth of field), VFX bursts and title cards from the beat-local time, and fires audio cues. Built on `tools/showcase/studio.gd`. |
| `trailer.gd` | Entry point: warms up, then renders frame by frame at a fixed 1/fps step, saving `frames/f_00000.png ...` and `cues.json` (the cue sheet and render time). |
| `render_trailer.py` | One command for everything: finds or downloads the pinned Godot (or `--godot PATH`), refreshes the class cache, renders (xvfb-run only when there is no display; Mobile renderer, or GL Compatibility on a display without Vulkan such as WSLg), stops a stalled engine exit, encodes, prints the MP4 paths. |
| `make_video.py` | ffmpeg assembly: effects track from the cue sheet (`assets/audio/*.wav`), the score (`assets/audio/music/trailer_theme.wav`) ducked under the effects when present, H.264 MP4 under a size budget, and the vertical teaser. |

## Beats

| Time | Beat |
| --- | --- |
| 0-7 | Cold open in the Cargo blackout: flashlights sweep, three crew edge forward, a red visor wakes with an angry face and blinks. |
| 7-9.5 | Title sting: DRIFT STATION / TRUST NO ONE. |
| 9.5-17 | The crew walks into Commons under emergency light and gathers; a wave, a helmet tap. |
| 17-23.5 | The last cell slots into the Reactor, the power wave rolls out and the lights come up on the crew. |
| 23.5-28 | The vault field drops; the core glows. |
| 28-33.5 | "ONE OF YOU IS LYING", then snap close-ups of suspicious faces, landing on purple. |
| 33.5-38.5 | Orange takes the gun from the armory, turns and fires past the lens. |
| 38.5-48.5 | Betrayal in Docking: green shoves the core carrier, the core flies (a real rigid body), green grabs it; the corridor chase. |
| 48.5-59 | Purple carries a body to the airlock, works the console under the warning strobe; the door blows and the body tumbles into the stars. |
| 59-67 | Pod countdown against shuttle countdown, cross-cut faster and faster. |
| 67-72.5 | The shuttle climbs away towards the gas giant. |
| 72.5-80.5 | End card: DRIFT STATION, "Restore the power. Save the core. Trust no one.", "2-8 FRIENDS · ANDROID". |

## Rendering

One command (Linux, WSL, macOS or Windows with Python 3 and ffmpeg):

```sh
python3 tools/trailer/render_trailer.py --preview   # 640x360, 15 fps draft
python3 tools/trailer/render_trailer.py             # final 1280x720, 30 fps -> builds/trailer/trailer.mp4
```

Options: `--from/--to` (seconds, partial render), `--out DIR` (default
`builds/trailer`), `--godot PATH`, `--renderer auto|mobile|forward_plus|gl_compatibility`,
`--skip-import`, `--no-video`, plus `make_video.py` options such as `--music`
or `--max-mb`. GL Compatibility has no depth of field, so the picture is a
little flatter there. Budget: on a 4-core CPU with software Vulkan the draft
takes about 20 minutes and the final render a few hours.

The steps it runs, by hand:

```sh
GODOT=tools/.cache/godot-4.7.2/Godot_v4.7.2-stable_linux.x86_64
# Preview: 640x360, 15 fps (fps and --fixed-fps must match).
xvfb-run -a -s "-screen 0 640x360x24" $GODOT --path . --rendering-method mobile \
    --resolution 640x360 --fixed-fps 15 --script res://tools/trailer/trailer.gd \
    -- --out /tmp/trailer_preview --fps 15 --preview [--from 38.5 --to 48.5]
# Final: 1280x720, 30 fps.
xvfb-run -a -s "-screen 0 1280x720x24" $GODOT --path . --rendering-method mobile \
    --resolution 1280x720 --fixed-fps 30 --script res://tools/trailer/trailer.gd \
    -- --out /tmp/trailer_final --fps 30
python3 tools/trailer/make_video.py --render /tmp/trailer_final --out /tmp/trailer_video
```

- `--from/--to` render part of the cut (seconds) for iterating on one beat; the
  teaser is only built from a full render.
- The run ends with `trailer: done, N frames in S s`; under software Vulkan the
  engine can stall on exit after that line, so stopping it then is safe.
- Godot's Movie Maker (`--write-movie`) is not used: frames must start on the
  first beat rather than at engine start-up, and the shutdown stall can stop
  Movie Maker from finalising its WAV. Audio is mixed from the cue sheet instead.

## Editing the cut

Add or change a beat method in `cut.gd` and its entry in `BEATS`. Inside a beat:
`first` is true on its first frame (call `begin_shot` and build the cast with
`actor()`); every frame, move crew with `walk()` / `drive()`, the camera with
`cam_move()` / `spline()` + `frame()`, fire one-off events with `crossed(lt, t)`
and sounds with `cue(lt, t, "sound", gain_db)`, and draw cards with `card()` /
`digit()`. Crew not driven in a frame idle automatically.
