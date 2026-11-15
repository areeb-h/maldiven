# Looks log

How Drift Station looks over time, newest first. Gameplay entries come from `python tools/record_looks.py --label <slug> --note "..."`, which plays real bot rounds on a rendered client with the Mobile renderer; `--from-dir` archives studio renders.

## 2026-11-15 · character-v2

Commit `2a9dc8c` · studio/station renders · 20 frames · [folder](2026-11-15-character-v2/)

Character polish pass on top of the approved v1: LED visor faces (neutral, happy, shocked, angry, suspicious, hurt, downed, ghost), bolted hinge joints and rubber bellows at every joint, 3-finger hands, glowing player numbers, 4 helmet/backpack variants, spring antenna and pack. About 15k triangles and 2 draw calls per character. Before/after joint renders are in the session scratchpad.

| | |
| --- | --- |
| ![run strip](2026-11-15-character-v2/00_run_strip.jpg)<br>run strip | ![faces a](2026-11-15-character-v2/01_faces_a.jpg)<br>faces a |
| ![faces b](2026-11-15-character-v2/02_faces_b.jpg)<br>faces b | ![turntable](2026-11-15-character-v2/03_turntable.jpg)<br>turntable |
| ![front](2026-11-15-character-v2/04_front.jpg)<br>front | ![helmet](2026-11-15-character-v2/05_helmet.jpg)<br>helmet |
| ![joints arms](2026-11-15-character-v2/06_joints_arms.jpg)<br>joints arms | ![joints legs](2026-11-15-character-v2/07_joints_legs.jpg)<br>joints legs |
| ![joints shove](2026-11-15-character-v2/08_joints_shove.jpg)<br>joints shove | ![macro elbow](2026-11-15-character-v2/09_macro_elbow.jpg)<br>macro elbow |
| ![macro knee](2026-11-15-character-v2/10_macro_knee.jpg)<br>macro knee | ![macro shoulder hip](2026-11-15-character-v2/11_macro_shoulder_hip.jpg)<br>macro shoulder hip |
| ![states](2026-11-15-character-v2/12_states.jpg)<br>states | ![aim](2026-11-15-character-v2/13_aim.jpg)<br>aim |
| ![carry](2026-11-15-character-v2/14_carry.jpg)<br>carry | ![action](2026-11-15-character-v2/15_action.jpg)<br>action |
| ![backs lowlight](2026-11-15-character-v2/16_backs_lowlight.jpg)<br>backs lowlight | ![variants back](2026-11-15-character-v2/17_variants_back.jpg)<br>variants back |
| ![fidget](2026-11-15-character-v2/18_fidget.jpg)<br>fidget | ![distance](2026-11-15-character-v2/19_distance.jpg)<br>distance |

## 2026-11-15 · station-v1

Commit `bfa58fd` · studio/station renders · 24 frames · [folder](2026-11-15-station-v1/)

Environment art pass: premium-toy station under cinematic light, every room in emergency / restored / blackout, plus the airlock cycle. 00_* are the plain grey-box comparison renders. Studio renders use the old placeholder crew figure; in-game players use the new suit.

| | |
| --- | --- |
| ![before naive primitives commons](2026-11-15-station-v1/00_before_naive_primitives_commons.jpg)<br>before naive primitives commons | ![before naive primitives overview](2026-11-15-station-v1/01_before_naive_primitives_overview.jpg)<br>before naive primitives overview |
| ![after overview restored](2026-11-15-station-v1/02_after_overview_restored.jpg)<br>after overview restored | ![after overview emergency](2026-11-15-station-v1/03_after_overview_emergency.jpg)<br>after overview emergency |
| ![commons player view restored](2026-11-15-station-v1/04_commons_player_view_restored.jpg)<br>commons player view restored | ![commons player view emergency](2026-11-15-station-v1/05_commons_player_view_emergency.jpg)<br>commons player view emergency |
| ![commons blackout](2026-11-15-station-v1/06_commons_blackout.jpg)<br>commons blackout | ![docking shuttle restored](2026-11-15-station-v1/07_docking_shuttle_restored.jpg)<br>docking shuttle restored |
| ![docking shuttle emergency](2026-11-15-station-v1/08_docking_shuttle_emergency.jpg)<br>docking shuttle emergency | ![reactor restored](2026-11-15-station-v1/09_reactor_restored.jpg)<br>reactor restored |
| ![reactor emergency](2026-11-15-station-v1/10_reactor_emergency.jpg)<br>reactor emergency | ![reactor blackout](2026-11-15-station-v1/11_reactor_blackout.jpg)<br>reactor blackout |
| ![corridor emergency](2026-11-15-station-v1/12_corridor_emergency.jpg)<br>corridor emergency | ![corridor restored](2026-11-15-station-v1/13_corridor_restored.jpg)<br>corridor restored |
| ![corridor blackout guide lights](2026-11-15-station-v1/14_corridor_blackout_guide_lights.jpg)<br>corridor blackout guide lights | ![cargo pod crates restored](2026-11-15-station-v1/15_cargo_pod_crates_restored.jpg)<br>cargo pod crates restored |
| ![cargo pod crates emergency](2026-11-15-station-v1/16_cargo_pod_crates_emergency.jpg)<br>cargo pod crates emergency | ![command vault restored](2026-11-15-station-v1/17_command_vault_restored.jpg)<br>command vault restored |
| ![security armory restored](2026-11-15-station-v1/18_security_armory_restored.jpg)<br>security armory restored | ![engineering restored](2026-11-15-station-v1/19_engineering_restored.jpg)<br>engineering restored |
| ![medical restored](2026-11-15-station-v1/20_medical_restored.jpg)<br>medical restored | ![airlock idle restored](2026-11-15-station-v1/21_airlock_idle_restored.jpg)<br>airlock idle restored |
| ![airlock warning](2026-11-15-station-v1/22_airlock_warning.jpg)<br>airlock warning | ![airlock venting door open](2026-11-15-station-v1/23_airlock_venting_door_open.jpg)<br>airlock venting door open |

## 2026-11-15 · character-v1 (owner approved)

Procedural crew suit, first iteration from the character pass: studio renders, not gameplay. Owner: "this is actually really nice." Kept as the baseline the next character pass must beat. [folder](2026-11-15-character-v1/)

| | |
| --- | --- |
| ![run_strip](2026-11-15-character-v1/00_run_strip.jpg)<br>run strip | ![turntable](2026-11-15-character-v1/01_turntable.jpg)<br>turntable |
| ![front](2026-11-15-character-v1/02_front.jpg)<br>front | ![action](2026-11-15-character-v1/03_action.jpg)<br>action |
| ![states](2026-11-15-character-v1/04_states.jpg)<br>states | ![carry](2026-11-15-character-v1/05_carry.jpg)<br>carry |
| ![stunned](2026-11-15-character-v1/06_stunned.jpg)<br>stunned | ![backs_lowlight](2026-11-15-character-v1/07_backs_lowlight.jpg)<br>backs lowlight |
| ![distance](2026-11-15-character-v1/08_distance.jpg)<br>distance | ![helmet](2026-11-15-character-v1/09_helmet.jpg)<br>helmet |
| ![visor](2026-11-15-character-v1/10_visor.jpg)<br>visor | ![chest](2026-11-15-character-v1/11_chest.jpg)<br>chest |

