# Run Friends Lab on your PC and Android phone

This is the **0.3.0 Friends Lab**: one shared 3D test room, up to six crew slots, authoritative movement, nearby push-to-talk and room radio. Install it beside the older island app. Your PC runs the server; your phone runs the game. The default mode uses the **same home Wi-Fi/LAN**. If the phone is on mobile data or another network, use the [free UDP tunnel setup](#phone-on-mobile-data-or-another-wi-fi) below. The PC can use Ethernet.

This build does not provide internet matchmaking, a built-in public relay, account login, match recovery, weapons or missions. The PC launcher can advertise a separately configured UDP tunnel to the existing APK. A Windows server walkthrough is provided below; its launcher was exercised on Linux loopback, so Windows execution and actual phone audio still need your test.

## 1. Prepare the Windows PC once

1. Install **Python 3.11 or later** from <https://www.python.org/downloads/windows/>. Include the Python launcher (`py`).
2. Download **Godot 4.7.2 Standard for Windows x86-64**, not .NET, from the [pinned official release](https://github.com/godotengine/godot/releases/tag/4.7.2-stable). Extract the complete ZIP, for example into `C:\Tools\Godot`. Keep the regular EXE beside the `_console.exe`.
3. Open PowerShell in your existing `maldiven` clone. Update it:

```powershell
git pull --ff-only
py -3 --version
& "C:\Tools\Godot\Godot_v4.7.2-stable_win64_console.exe" --version
```

The engine output must start with `4.7.2.stable.official.`. The launcher rejects other versions. Change the example executable path to your extracted file. Serving the game requires **no Android SDK, Java, export templates, pip packages or Godot editor import**.

## 2. Start the server

From the repository folder in normal PowerShell:

```powershell
py -3 tools/run_friends_server.py --godot "C:\Tools\Godot\Godot_v4.7.2-stable_win64_console.exe"
```

The terminal prints the private PC address and opens a local **private invite page** in your browser. Keep the terminal open. Press `Ctrl+C` to stop the room cleanly.

If the detected address belongs to a VPN or the wrong adapter, run `ipconfig`, find the **IPv4 Address** under your active Wi-Fi/Ethernet adapter and restart with it:

```powershell
py -3 tools/run_friends_server.py --godot "C:\Tools\Godot\Godot_v4.7.2-stable_win64_console.exe" --host 192.168.1.20
```

Replace `192.168.1.20` with your actual PC address. `127.0.0.1` is not the PC address to use on a phone. The server binds only that specified private IPv4 interface, not every interface.

If Windows asks about network access, allow the Godot executable on **Private networks**. Your trusted home network must have the Windows Private profile. If no prompt appears and connection times out, run this once in **Administrator PowerShell** to permit the room's UDP port from the local subnet:

```powershell
New-NetFirewallRule -DisplayName "Maldiven Friends LAN" -Direction Inbound -Action Allow -Protocol UDP -LocalPort 24567 -RemoteAddress LocalSubnet -Profile Private
```

An optional cleanup command, after testing:

```powershell
Remove-NetFirewallRule -DisplayName "Maldiven Friends LAN"
```

Use the same custom port in the firewall rule if you launch with `--port`. Do not disable the firewall or forward a router port for this LAN test. See [Microsoft's command reference](https://learn.microsoft.com/en-us/powershell/module/netsecurity/new-netfirewallrule).

## Phone on mobile data or another Wi-Fi

Use this mode when the phone cannot reach the PC's private network. The PC still hosts the game; a third-party tunnel forwards its UDP traffic. **No new APK is needed:** Friends Lab 0.3.0 already accepts a public IPv4 in the private invite. Its old “Same Wi-Fi required” menu text describes the original default mode and can be ignored for a tunnel invite.

As checked on 2026-11-12, [Playit.gg](https://playit.gg/) lists custom **UDP** in its free tier and says no credit card is required. TCP and TCP+UDP tunnels are different products and may require Premium. Use only the free UDP option. No payment or hosted VM is required for these instructions. See the [official supported tunnel list](https://playit.gg/login).

1. On the PC, create a free Playit account and download its [Windows agent](https://playit.gg/download).
2. Run the agent and follow its account-linking instructions. Keep the agent running.
3. Create **one custom UDP tunnel**, with one public port. Configure these local forwarding values:

| Setting | Value |
| --- | --- |
| Protocol/type | UDP (free), not TCP or TCP+UDP |
| Local address | `127.0.0.1` |
| Local port | `24567` |
| Port count | `1` |
| Proxy Protocol, if offered | Off; forward the original UDP payload |

4. Copy the tunnel's **public hostname/IP and assigned public port**. This is different from local port 24567. The tunnel might use a public port such as 32100; use the one actually assigned to you.
5. Update your clone and start the game server, replacing the example address with your actual public allocation:

```powershell
git pull --ff-only
py -3 tools/run_friends_server.py --godot "C:\Tools\Godot\Godot_v4.7.2-stable_win64_console.exe" --public-address "YOUR-TUNNEL-HOSTNAME:PUBLIC-PORT"
```

For example, if Playit actually assigned `your-name.gl.ply.gg:32100`, the final argument would be `--public-address "your-name.gl.ply.gg:32100"`. Do not copy that example as a working server address. Do not use a URL with `https://` or a local/private PC address.

The launcher binds the Godot server to **127.0.0.1:24567**, resolves the supplied public hostname to IPv4 once, and creates invites containing the public IP/port. It does not create a tunnel or verify public reachability. Keep **both the game server terminal and Playit agent running**. The agent must be on the same PC as this loopback-bound server. Do not combine `--public-address` with `--host` or `--local-only`.

6. Transfer **Crew 1 / Invite A** privately to your phone. Paste it into **Maldiven Friends Lab** and connect using mobile data or your other Wi-Fi. A second person uses Crew 2, and so on. Only the PC runs Playit; no Playit installation is needed on the phones.

The normal ten-minute expiry/single-use rules still apply. If the public allocation or its resolved IP changes, restart the game launcher with the updated allocation and copy fresh invites. If you choose `--port` to change the local game port, update the tunnel's local port to match; its public port is still independent.

**If connection times out:** check that the agent is online, the tunnel is UDP, its local target is 127.0.0.1:24567, the public port in the launcher matches Playit, and both processes remain open. Allow the agent's network access if Windows prompts. This route does not require a router port-forward or a broad inbound Windows firewall rule; the local agent connects to the local game server. Do not enable the optional Proxy Protocol.

The tunnel forwards the existing certificate-checked DTLS packets. Invites still carry the game server's certificate and single-use ticket; the tunnel does not replace application authentication. Actual Playit routing, latency and physical phone audio remain to be tested on your PC/phone. A local smoke test is not proof that this external route works.

## 3. Connect the phone

1. Install **`maldiven-friends-0.3.0-arm64.apk`** from the build/download supplied with this milestone. Its name is **Maldiven Friends Lab** and its package is `com.areebh.maldiven.friends`; the island app can stay installed.
2. For default LAN mode, connect the phone to the same Wi-Fi as the PC. For `--public-address` mode, keep the UDP agent online; the phone can use another network. Unrelated VPNs and guest/client isolation can affect connectivity.
3. On the PC invite page, click the text area for **Crew 1 / Invite A** and copy the complete `MDV1.` text. Transfer it privately to your phone using your usual method. It includes the server certificate and a one-use admission credential. Do not publish or screenshot it for a public bug report.
4. Open the phone app, choose **Paste invite**, then **Connect to PC**. You can also paste directly into the text field.
5. A second phone uses **Crew 2 / Invite A**, and so on. Each person needs a different crew slot. You should see the other crew members in the shared room.

Both A and B expire **10 minutes after server startup**. B is a spare for the same crew slot after a leave; it cannot join while that identity is connected. A used or failed admission can consume its ticket. If both are spent or expired, stop/restart the server to create a fresh room and invites, then reconnect everyone. A restart disconnects the existing room. A lost connection does not resume the old session automatically.

The invite page is a local file, not a website served to your phone. The phone does not need to open a PC URL. Game and voice traffic use UDP directly to the PC.

## 4. Move and test voice

- Left thumb: move with the pad. Right thumb: hold **HOLD TO TALK**. The fingers have independent ownership, so you can walk and talk together.
- Choose **Enable mic** and grant Android microphone permission. This permits PTT; it does not start continuous capture. You must release and press talk after enabling permission.
- Hold talk until it says **TALKING**. The client waits for the server's grant before starting microphone capture. Release or slide away to stop.
- **Nearby · 8 m** sends only to crew within 8 metres according to server positions. **Radio · room** sends to all other admitted crew. These buttons select the sending channel; you can hear both incoming channels. Nearby is range-gated, with no wall occlusion or positional volume falloff yet.
- **Mute sound** drops incoming playback and stops current outgoing PTT. While muted you cannot transmit. Unmute, then press talk again. **Leave** returns to the invite screen.
- Keyboard on a desktop client: WASD/arrows, Shift to run, Space to talk, Escape to leave.

**Use headphones first.** This native PCM candidate has no echo cancellation, noise suppression, Opus compression or automatic audio-route recovery. Speakerphone/Bluetooth quality is not established. It is a feasibility build, not the final voice system. No audio recording or transcription is implemented. The PC decrypts PCM in memory to route it; this is encrypted client-to-server transport, not end-to-end encryption between players.

## 5. Quick two-phone acceptance pass

Record the phone model/Android version, PC OS, Wi-Fi setup and result for each item:

| Check | What should happen |
| --- | --- |
| Join with two different slots | Both phones show two crew and each other's movement |
| Move and hold talk together | Movement and PTT continue with separate fingers |
| Deny mic permission | Movement/listening remain available; no outgoing capture |
| Grant permission, then press talk | Other phone hears you using headphones |
| Release talk | Capture stops immediately; an already delivered short playback buffer can drain |
| Walk apart beyond nearby range | Nearby transmission stops reaching the distant listener |
| Choose Radio and talk again | Distant admitted listener hears the radio |
| Mute sound | No new local playback; outgoing PTT stops |
| Switch apps while talking | Microphone capture and movement input stop; returning requires a fresh talk press |
| Leave and retry with B | Returns to menu; the spare ticket can join the same slot after cleanup |
| Stop PC server | Phone returns to menu, or times out and returns if the network fails silently |

Run the same pass on three phones before marking the P1 gate complete. Also test headset disconnect, screen lock, permission revocation, a call interruption and a 15-minute session. Report failures; do not mark latency, thermal behaviour or audio intelligibility as passed without measurements.

## Troubleshooting

| Symptom | Check |
| --- | --- |
| Python command missing | Reinstall Python with launcher, or use `python` if that resolves to Python 3.11+ |
| Wrong Godot version | Pass the extracted 4.7.2 Standard console EXE, not an unrelated `godot` on PATH |
| No invite page opens | Open the exact `invites.html` path printed by the terminal; `--no-browser` intentionally skips opening it |
| Bind failed | Use the current adapter IPv4; close an existing server or choose another `--port` |
| Connection times out | PC terminal running; same LAN; correct IP; Private firewall rule; VPN off; no guest/client isolation |
| Expired/replayed/identity in use | Use the spare B invite after leaving, a different crew slot, or restart for fresh invites |
| Certificate handshake fails | Copy a fresh invite from the running server; check both clocks; do not bypass verification |
| Certificate older than one year | Stop the server, move both `server.key` and `server.crt` aside, then restart to regenerate a pair and fresh invites |
| Mic denied | Android Settings → Apps → Maldiven Friends Lab → Permissions → Microphone; then return, enable and press talk again |
| Hear echo or feedback | Use headphones on every device; keep devices apart; AEC is not implemented |
| APK will not update | This is a debug-signed test app. An APK signed by a different local key needs the old Friends Lab app uninstalled first; island app is separate |
| Locked after a crash | Confirm no Godot friends server is still running, then delete only `server.lock` in the printed private state folder |

The default PC state folder is `%LOCALAPPDATA%\Maldiven\FriendsLab`. It contains the private key, ticket ledger, local invite page and metadata-only `server.log`. The launcher removes inherited Windows ACLs and grants the current user and SYSTEM; native Windows verification remains pending. Logs never include tickets or PCM samples. Do not commit this directory or send it wholesale when reporting bugs. Restart truncates the current log.

## Linux/macOS and development

Linux x86-64 can bootstrap the pinned editor automatically:

```bash
python3 tools/run_friends_server.py
```

On macOS, install Godot 4.7.2 Standard and pass its executable:

```bash
python3 tools/run_friends_server.py --godot /Applications/Godot.app/Contents/MacOS/Godot
```

Allow local incoming UDP according to your OS firewall. Default state is `$XDG_STATE_HOME/maldiven-friends` or `~/.local/state/maldiven-friends`. The launcher requires Python 3.11+ on every platform and refuses state inside the repository.

For a desktop client, first import `experiments/net-lab/project.godot` with the pinned Godot editor, then run that project; it opens the same invite UI. This is a separate project from the island root `project.godot`.

Build with `python tools/build_friends_android.py` only on a host with the matching export templates and configured Android SDK/JDK. `--pack-only` checks the exported entry point without Android. `python tools/test_friends_lab.py` runs synthetic PCM/DTLS/lifecycle tests; it cannot prove physical audio quality. For engine API references, see [ENetConnection](https://docs.godotengine.org/en/4.7/classes/class_enetconnection.html), [TLSOptions](https://docs.godotengine.org/en/4.7/classes/class_tlsoptions.html), [AudioEffectCapture](https://docs.godotengine.org/en/4.7/classes/class_audioeffectcapture.html) and [Android export](https://docs.godotengine.org/en/4.7/tutorials/export/exporting_for_android.html).

For a desktop-only development room, `python tools/run_friends_server.py --local-only` binds loopback. Its invites cannot be used from a phone. This is the smoke-test mode used by the build host.
