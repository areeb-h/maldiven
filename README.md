# Maldiven: Drift Station

**Drift Station** is a third-person 3D social-deduction game for 2–8 friends, Android first (PC works too). A dying station has lost power. The crew carries power cells to the reactor, unlocks the core and tries to fly it out on the shuttle. One of them is the infiltrator, who wants the core in the cargo pod instead, and can kill the lights to get it there. Expect shoving, scrums at the shuttle and arguments over the end-of-round timeline. Godot 4.7.2, Mobile renderer, Jolt physics. Version 0.4.0.

## Play the week-1 build

Open the project in Godot 4.7.2 and press Play, or run:

```bash
godot --path .
```

The main scene is `res://scenes/main.tscn`. A round: ~6 s private role briefing → **Stabilise** (lights out; carry the 3 cells from Engineering, Medical and Security to the Reactor) → **Extraction** (power back, the core vault in Command opens) → **Result** (outcome, who the infiltrator was, event timeline, rematch). Crew win by loading the core into the shuttle in Docking and surviving its 30 s countdown. The infiltrator wins by arming the cargo pod in Cargo and surviving 20 s. If the 10-minute timer runs out, everyone loses. Full rules in [docs/design.md](docs/design.md).

There's no in-game voice yet. Play in the same room or on a Discord call.

## Controls

| Action | Desktop | Touch |
| --- | --- | --- |
| Move | WASD | Left floating stick |
| Run | Shift | |
| Look | Right-mouse drag | Drag on the right side |
| Jump | Space | Jump button |
| Interact (pick up / drop / insert / pull out) | E | Interact button (shows what it will do) |
| Shove | F | Shove button |
| Sabotage: Blackout (infiltrator only) | Q | Sabotage button |
| Menu | Esc | |

## Hosting and joining

- **Dedicated PC server (one command):** `python tools/host_station.py` (Python 3.11+, Windows/macOS/Linux). It downloads the pinned Godot on first run, starts a headless server where every phone is a player, and opens a live control panel in your browser (join address, QR, players, start round, kick, station log). Full guide: [docs/hosting.md](docs/hosting.md).
- **Host from a phone:** choose Host on the main menu, on any phone or PC. The host plays too. The lobby shows the host's IP.
- **Join:** on the same Wi-Fi the room shows up automatically. If it doesn't (some routers and phones block broadcast), type the host's IP.
- Ports: game UDP **24600**, LAN discovery UDP broadcast **24601**. Allow them through the firewall on the hosting PC.
- Late joins are refused while a round is running. Wait for the result screen.
- **Over the internet:** not yet. For now use the [Friends Lab tunnel approach](docs/pc-server-and-phone.md#phone-on-mobile-data-or-another-wi-fi) or wait for week 3.

Why a listen server: [ADR 0025](docs/adr/0025-listen-server-prototype.md).

## Tests and builds

```bash
python tools/test_station.py      # rules unit tests + headless networked bot round (host + 2 clients on loopback)
python tools/validate_project.py  # pinned-engine bootstrap, fresh import, regressions, pack export, packaged startup
python tools/build_android.py     # APK; needs Godot 4.7.2 Android export templates + Android SDK
```

Python 3.11+. Engine versions and checksums are pinned in `toolchain.lock.json`. The APK requests the INTERNET permission. If the Mobile renderer shows horizontal bands on your phone, try the Compatibility build, `python tools/build_android.py --renderer compatibility` ([ADR 0004](docs/adr/0004-device-rendering-workaround.md)).

## Project layout

| Path | What |
| --- | --- |
| `scenes/main.tscn` | Main scene: menu, lobby, station, round |
| `scripts/station_layout.gd` | Station map: rooms, corridors, sockets, item and player spawns |
| `scripts/` | Game scripts |
| `scenes/legacy/`, `scripts/legacy/` | The old island prototype, kept runnable |
| `tests/` | Godot test scripts |
| `tools/` | Python test, validation and build tools |
| `assets/` | Models and previews |
| `experiments/net-lab/` | Friends Lab: separate PC-server + phone voice experiment, base for week-3 voice |
| `docs/` | Design, roadmap, ADRs |

## Docs

- [Design](docs/design.md): the game, in one doc
- [Roadmap](docs/roadmap.md): week-by-week checklist
- [ADRs](docs/adr/README.md): decisions that still apply
- [Friends Lab voice experiment](docs/pc-server-and-phone.md): PC server + phone PCM voice, tunnel setup
- [Archive](docs/archive/README.md): the earlier detailed plan, blueprint and reports
