# Hosting a game

Drift Station needs one **host** per game: the device that runs the station.
Everyone else joins it over the same Wi-Fi. There are two ways to host.

## Option 1: host from a phone

The quickest way, with no computer needed.

1. Everyone connects to the same Wi-Fi.
2. One person opens Drift Station and taps **Host**. They play too.
3. Everyone else opens Drift Station: the station appears under
   **Nearby stations**. Tap it to join.
4. When everyone is in, the host taps **Start round**.

The hosting phone does a little more work than the others, so pick one that's
charged and not too old.

## Option 2: run a server on your PC

A computer runs the station in the background and every phone is a player.
Good for bigger groups, older phones, or when nobody wants to be the host.

**You need:** Python 3.11 or newer ([python.org/downloads](https://www.python.org/downloads/);
on Windows, tick *Add python.exe to PATH* during the install) and a copy of
this project. Nothing else: the right Godot engine (4.7.2) downloads itself the
first time (90 MB on Windows, 170 MB on macOS), checked against the official checksums.

**Start it** from the project folder:

```
Windows:        py tools\host_station.py
macOS / Linux:  python3 tools/host_station.py
```

The terminal shows the address phones can type, in big digits, and the control
panel opens in your browser at <http://127.0.0.1:24680>. The panel only works
on this computer. From it you can:

- see the join address and a QR code of it,
- watch who's connected (with their colour and ping) and remove someone,
- start a round (it needs at least 2 players), follow the timer and phases,
  and send everyone back to the lobby,
- rename the station: click its name at the top,
- read the live station log, and open **Troubleshooting**.

Phones join exactly as in option 1: same Wi-Fi, then the station under
**Nearby stations**, or **Join by IP** with the address on screen. Roles stay on
the phones: the panel never shows who the infiltrator is until the round ends,
so the person running the PC can play on their phone too. After a round ends,
everyone goes back to the lobby automatically after 45 seconds (or press
**Back to lobby**).

Useful options (`py tools\host_station.py --help` lists them all):

| Option | What it does |
| --- | --- |
| `--room-name "Friday crew"` | The station name phones see (it's remembered for next time) |
| `--max-players 6` | Limit the seats (2 to 8) |
| `--auto-lobby 0` | Stay on the results until you press Back to lobby |
| `--no-browser` | Don't open the panel automatically |
| `--public-address host:port` | Show an internet address from a UDP tunnel in the panel |

### Stopping the server

Press **Ctrl+C** in the terminal, or **Stop server** in the panel. The phones
are told the station is closing and go back to their home screen, then the
server shuts down. (Press Ctrl+C twice to quit immediately.) If you close the
terminal window instead, the server notices and closes itself within about 20
seconds.

## Troubleshooting

**The station doesn't appear under Nearby stations.** Try **Join by IP** with
the address the terminal shows. If that doesn't connect either, it's the
network or the firewall:

- **Windows Firewall.** The first time, Windows may ask whether Godot can use
  the network: allow it on **Private networks**. The launcher checks the
  firewall and prints a command if it looks blocked. Run it once in a terminal
  opened with *Run as administrator*:

  ```
  netsh advfirewall firewall add rule name="Drift Station server" dir=in action=allow protocol=UDP localport=24600-24601 profile=private
  ```

  If Windows calls your home Wi-Fi a *Public* network, switch it to *Private*:
  Settings › Network & internet › Wi-Fi › your network › Network profile type.
- **macOS** may ask whether Godot can accept incoming connections: click Allow.
- **Linux** with ufw: `sudo ufw allow 24600:24601/udp`.
- **Guest Wi-Fi** usually keeps devices apart. Use the main network.
- **Client isolation.** Some routers (offices, dorms, hotels, some mesh
  systems) block devices from talking to each other. Turn off *AP isolation* /
  *client isolation* in the router, or plug the PC into the router with a cable.
- **Mobile data or a VPN** on a phone hides the station. Turn them off.

**"Port 24600 is already in use".** Another Drift Station (the game or a
server) is running on this computer. Close it and press **Restart** in the panel.

**"Version mismatch".** Every phone and the server must run the same version
of the game. Update the app, or pull the latest project on the PC.

**Playing with friends elsewhere.** Nearby stations only works on the local
network. Over the internet you need a UDP tunnel or a router port forward to
UDP 24600 on the PC (the game always uses port 24600); start the server with
`--public-address` so the panel shows that address.

## For developers

- The server is the normal game started headless with
  `godot --headless --path . -- --dedicated [--room-name=…] [--max-players=8]`.
  `scripts/server/dedicated_server.gd` hosts with an empty roster (the PC is
  ENet peer 1 but not a player), creates the `StationWorld` for each round and
  runs the authoritative rules, timers and physics. Phones can't tell it apart
  from a phone host.
- **Control protocol.** `tools/host_station.py` passes `--control-port` and a
  random `--control-token`; the server listens on 127.0.0.1 only. Messages are
  newline-delimited JSON over TCP: first `{"hello": token}`, then commands
  `{"id": 1, "cmd": "start_round" | "back_to_lobby" | "kick" | "set_room_name" | "stop", "args": {…}}`
  (`kick` takes `{"id": peer}`, `set_room_name` takes `{"name": …}`), answered
  by `{"type": "reply", "id": 1, "ok": true}` or `{"ok": false, "error": "…"}`.
  The server pushes `{"type": "status", …}` every 0.5 s: room name, state
  (`lobby`/`briefing`/`stabilise`/`extraction`/`result`), players (id, name,
  colour, `lobby`/`ok`/`downed`/`dead`, ping), the round timer, power cells and
  countdowns, the event feed, LAN addresses and version. It is built from
  `StationRules.public_snapshot()` only, so roles never appear; the winner,
  infiltrator and timeline are added once the round reaches `result`. If the
  launcher disconnects for 20 s the server closes the station by itself.
- The panel (`tools/server_panel/`) is static HTML/CSS/JS served by the
  launcher with the game fonts from `assets/fonts/`; it polls `/api/status`
  and posts to `/api/command` (requests need the `X-Drift-Panel` header and a
  localhost `Host`, so other websites can't drive it). The QR encoder in
  `qr.js` is written for this panel.
- Tests: `python tools/test_host_station.py` runs the launcher in test mode and
  plays a full round with headless bot phones against the PC server.
- Logs of the last five server runs are in `tools/.cache/host_station/`.
