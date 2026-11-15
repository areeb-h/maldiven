# Looks log

How Drift Station looks over time, newest first. Gameplay entries come from `python tools/record_looks.py --label <slug> --note "..."`, which plays real bot rounds on a rendered client with the Mobile renderer; `--from-dir` archives studio renders.

## 2026-11-15 · keyart-v1

Commit `2d86313` · studio/station renders · 40 frames · [folder](2026-11-15-keyart-v1/)

Final key art: 37 stills (characters, station, items, gameplay moments, UI) rendered from the finished game, plus trailer frames. The 80 s trailer (720p, scored) and the 15 s vertical teaser are regenerated with `python3 tools/trailer/render_trailer.py`; the videos are kept out of git.

| | |
| --- | --- |
| ![characters crew lineup](2026-11-15-keyart-v1/00_characters_crew_lineup.jpg)<br>characters crew lineup | ![characters roster all colours](2026-11-15-keyart-v1/01_characters_roster_all_colours.jpg)<br>characters roster all colours |
| ![characters expressions](2026-11-15-keyart-v1/02_characters_expressions.jpg)<br>characters expressions | ![characters variants](2026-11-15-keyart-v1/03_characters_variants.jpg)<br>characters variants |
| ![characters portrait blue happy](2026-11-15-keyart-v1/04_characters_portrait_blue_happy.jpg)<br>characters portrait blue happy | ![characters portrait purple suspicious](2026-11-15-keyart-v1/05_characters_portrait_purple_suspicious.jpg)<br>characters portrait purple suspicious |
| ![characters portrait red angry](2026-11-15-keyart-v1/06_characters_portrait_red_angry.jpg)<br>characters portrait red angry | ![characters portrait orange shocked](2026-11-15-keyart-v1/07_characters_portrait_orange_shocked.jpg)<br>characters portrait orange shocked |
| ![characters one of you is lying](2026-11-15-keyart-v1/08_characters_one_of_you_is_lying.jpg)<br>characters one of you is lying | ![characters turntable trio](2026-11-15-keyart-v1/09_characters_turntable_trio.jpg)<br>characters turntable trio |
| ![characters squad selfie](2026-11-15-keyart-v1/10_characters_squad_selfie.jpg)<br>characters squad selfie | ![station exterior planet](2026-11-15-keyart-v1/11_station_exterior_planet.jpg)<br>station exterior planet |
| ![station overhead tilt shift](2026-11-15-keyart-v1/12_station_overhead_tilt_shift.jpg)<br>station overhead tilt shift | ![station commons](2026-11-15-keyart-v1/13_station_commons.jpg)<br>station commons |
| ![station command vault](2026-11-15-keyart-v1/14_station_command_vault.jpg)<br>station command vault | ![station security](2026-11-15-keyart-v1/15_station_security.jpg)<br>station security |
| ![station docking shuttle](2026-11-15-keyart-v1/16_station_docking_shuttle.jpg)<br>station docking shuttle | ![station cargo pod](2026-11-15-keyart-v1/17_station_cargo_pod.jpg)<br>station cargo pod |
| ![station engineering](2026-11-15-keyart-v1/18_station_engineering.jpg)<br>station engineering | ![station reactor power wave](2026-11-15-keyart-v1/19_station_reactor_power_wave.jpg)<br>station reactor power wave |
| ![station medical](2026-11-15-keyart-v1/20_station_medical.jpg)<br>station medical | ![station observation](2026-11-15-keyart-v1/21_station_observation.jpg)<br>station observation |
| ![station corridor](2026-11-15-keyart-v1/22_station_corridor.jpg)<br>station corridor | ![items gun](2026-11-15-keyart-v1/23_items_gun.jpg)<br>items gun |
| ![items power cell](2026-11-15-keyart-v1/24_items_power_cell.jpg)<br>items power cell | ![items core](2026-11-15-keyart-v1/25_items_core.jpg)<br>items core |
| ![items items trio](2026-11-15-keyart-v1/26_items_items_trio.jpg)<br>items items trio | ![items sockets](2026-11-15-keyart-v1/27_items_sockets.jpg)<br>items sockets |
| ![moments core run](2026-11-15-keyart-v1/28_moments_core_run.jpg)<br>moments core run | ![moments shove](2026-11-15-keyart-v1/29_moments_shove.jpg)<br>moments shove |
| ![moments gun standoff](2026-11-15-keyart-v1/30_moments_gun_standoff.jpg)<br>moments gun standoff | ![moments rescue](2026-11-15-keyart-v1/31_moments_rescue.jpg)<br>moments rescue |
| ![moments airlock](2026-11-15-keyart-v1/32_moments_airlock.jpg)<br>moments airlock | ![moments ghost](2026-11-15-keyart-v1/33_moments_ghost.jpg)<br>moments ghost |
| ![moments blackout](2026-11-15-keyart-v1/34_moments_blackout.jpg)<br>moments blackout | ![moments shuttle escape](2026-11-15-keyart-v1/35_moments_shuttle_escape.jpg)<br>moments shuttle escape |
| ![moments spaced](2026-11-15-keyart-v1/36_moments_spaced.jpg)<br>moments spaced | ![ui home](2026-11-15-keyart-v1/37_ui_home.jpg)<br>ui home |
| ![ui lobby](2026-11-15-keyart-v1/38_ui_lobby.jpg)<br>ui lobby | ![ui role reveal](2026-11-15-keyart-v1/39_ui_role_reveal.jpg)<br>ui role reveal |

## 2026-11-15 · station-v2

Commit `84bb235` · studio/station renders · 18 frames · [folder](2026-11-15-station-v2/)

Station layout and detail pass: a new Observation lounge splits the 48 m service corridor, raised decks with ramps in Cargo and Observation, cover pillars, wall screens, vents and conduits, room plaques and floor arrows, story props per room, small animated details, and 107 props with fitted colliders. Text is merged into mesh geometry and shadows come from the simple collision shapes: Commons gameplay view drops from 45 to 34 draw calls. 'pair_' frames are before/after.

| | |
| --- | --- |
| ![overview2 restored](2026-11-15-station-v2/00_overview2_restored.jpg)<br>overview2 restored | ![observation restored](2026-11-15-station-v2/01_observation_restored.jpg)<br>observation restored |
| ![observation back emergency](2026-11-15-station-v2/02_observation_back_emergency.jpg)<br>observation back emergency | ![commons east restored](2026-11-15-station-v2/03_commons_east_restored.jpg)<br>commons east restored |
| ![commons west emergency](2026-11-15-station-v2/04_commons_west_emergency.jpg)<br>commons west emergency | ![command restored](2026-11-15-station-v2/05_command_restored.jpg)<br>command restored |
| ![command side blackout](2026-11-15-station-v2/06_command_side_blackout.jpg)<br>command side blackout | ![cargo north restored](2026-11-15-station-v2/07_cargo_north_restored.jpg)<br>cargo north restored |
| ![docking restored](2026-11-15-station-v2/08_docking_restored.jpg)<br>docking restored | ![engineering emergency](2026-11-15-station-v2/09_engineering_emergency.jpg)<br>engineering emergency |
| ![medical west restored](2026-11-15-station-v2/10_medical_west_restored.jpg)<br>medical west restored | ![corridor service blackout](2026-11-15-station-v2/11_corridor_service_blackout.jpg)<br>corridor service blackout |
| ![airlock emergency](2026-11-15-station-v2/12_airlock_emergency.jpg)<br>airlock emergency | ![pair airlock emergency](2026-11-15-station-v2/13_pair_airlock_emergency.jpg)<br>pair airlock emergency |
| ![pair cargo north restored](2026-11-15-station-v2/14_pair_cargo_north_restored.jpg)<br>pair cargo north restored | ![pair commons east restored](2026-11-15-station-v2/15_pair_commons_east_restored.jpg)<br>pair commons east restored |
| ![pair commons west emergency](2026-11-15-station-v2/16_pair_commons_west_emergency.jpg)<br>pair commons west emergency | ![pair corridor service restored](2026-11-15-station-v2/17_pair_corridor_service_restored.jpg)<br>pair corridor service restored |

## 2026-11-15 · physics-v1

Commit `00319a0` · studio/station renders · 6 frames · [folder](2026-11-15-physics-v1/)

Physics pass, as frame strips: ragdoll collapse when shot, carried body dangling, shove stagger, loose items bouncing, props knocked over, and the airlock vent blowing everything into space. Host-authoritative rigid bodies replicate at 25 Hz only while moving (about 3 KB/s per client in a scrum).

| | |
| --- | --- |
| ![sheet airlock vent](2026-11-15-physics-v1/00_sheet_airlock_vent.jpg)<br>sheet airlock vent | ![sheet carried dangle](2026-11-15-physics-v1/01_sheet_carried_dangle.jpg)<br>sheet carried dangle |
| ![sheet items bounce](2026-11-15-physics-v1/02_sheet_items_bounce.jpg)<br>sheet items bounce | ![sheet props knocked](2026-11-15-physics-v1/03_sheet_props_knocked.jpg)<br>sheet props knocked |
| ![sheet ragdoll collapse](2026-11-15-physics-v1/04_sheet_ragdoll_collapse.jpg)<br>sheet ragdoll collapse | ![sheet shove stagger](2026-11-15-physics-v1/05_sheet_shove_stagger.jpg)<br>sheet shove stagger |

## 2026-11-15 · items-v2

Commit `3f10be4` · studio/station renders · 17 frames · [folder](2026-11-15-items-v2/)

Items and sockets pass: blaster with ammo charge cells and a grip sized for the glove, power cell with an animated energy window, caged core (10% smaller so it stays under the visor), and all 7 socket types with animated floating labels and 8 states each, in emergency and restored power.

| | |
| --- | --- |
| ![gun 0](2026-11-15-items-v2/00_gun_0.jpg)<br>gun 0 | ![gun 1](2026-11-15-items-v2/01_gun_1.jpg)<br>gun 1 |
| ![gun ammo1](2026-11-15-items-v2/02_gun_ammo1.jpg)<br>gun ammo1 | ![cell 0](2026-11-15-items-v2/03_cell_0.jpg)<br>cell 0 |
| ![cell 1](2026-11-15-items-v2/04_cell_1.jpg)<br>cell 1 | ![core 0](2026-11-15-items-v2/05_core_0.jpg)<br>core 0 |
| ![core 1](2026-11-15-items-v2/06_core_1.jpg)<br>core 1 | ![held gun restored 0](2026-11-15-items-v2/07_held_gun_restored_0.jpg)<br>held gun restored 0 |
| ![held cell restored 0](2026-11-15-items-v2/08_held_cell_restored_0.jpg)<br>held cell restored 0 | ![held core emergency 0](2026-11-15-items-v2/09_held_core_emergency_0.jpg)<br>held core emergency 0 |
| ![sheet reactor restored](2026-11-15-items-v2/10_sheet_reactor_restored.jpg)<br>sheet reactor restored | ![sheet vault restored](2026-11-15-items-v2/11_sheet_vault_restored.jpg)<br>sheet vault restored |
| ![sheet shuttle restored](2026-11-15-items-v2/12_sheet_shuttle_restored.jpg)<br>sheet shuttle restored | ![sheet pod emergency](2026-11-15-items-v2/13_sheet_pod_emergency.jpg)<br>sheet pod emergency |
| ![sheet armory restored](2026-11-15-items-v2/14_sheet_armory_restored.jpg)<br>sheet armory restored | ![sheet medbay restored](2026-11-15-items-v2/15_sheet_medbay_restored.jpg)<br>sheet medbay restored |
| ![sheet airlock console emergency](2026-11-15-items-v2/16_sheet_airlock_console_emergency.jpg)<br>sheet airlock console emergency |   |

## 2026-11-15 · ui-v2

Commit `079f442` · studio/station renders · 16 frames · [folder](2026-11-15-ui-v2/)

UI and HUD fine-detail pass: colour-blind-safe palette with icon and word on every cue, icon-only role chip, cell pips, queued alerts, draining countdown rings, edge markers to the core, pod and downed crew, safe-area thumb-zone controls, hold-to-fire blackout, lobby crew cards with an IP chip, and a result timeline. 1280×720 plus a 2400×1080 phone, and frames from a real networked bot round.

| | |
| --- | --- |
| ![720 home](2026-11-15-ui-v2/00_720_home.jpg)<br>720 home | ![720 lobby](2026-11-15-ui-v2/01_720_lobby.jpg)<br>720 lobby |
| ![720 briefing](2026-11-15-ui-v2/02_720_briefing.jpg)<br>720 briefing | ![720 stabilise](2026-11-15-ui-v2/03_720_stabilise.jpg)<br>720 stabilise |
| ![720 extraction](2026-11-15-ui-v2/04_720_extraction.jpg)<br>720 extraction | ![720 pod](2026-11-15-ui-v2/05_720_pod.jpg)<br>720 pod |
| ![720 downed](2026-11-15-ui-v2/06_720_downed.jpg)<br>720 downed | ![720 ghost](2026-11-15-ui-v2/07_720_ghost.jpg)<br>720 ghost |
| ![720 result](2026-11-15-ui-v2/08_720_result.jpg)<br>720 result | ![720 home error](2026-11-15-ui-v2/09_720_home_error.jpg)<br>720 home error |
| ![2400x1080 lobby](2026-11-15-ui-v2/10_2400x1080_lobby.jpg)<br>2400x1080 lobby | ![2400x1080 extraction](2026-11-15-ui-v2/11_2400x1080_extraction.jpg)<br>2400x1080 extraction |
| ![gameplay 03 spawn commons](2026-11-15-ui-v2/12_gameplay_03_spawn_commons.jpg)<br>gameplay 03 spawn commons | ![gameplay 05 carrying cell 1](2026-11-15-ui-v2/13_gameplay_05_carrying_cell_1.jpg)<br>gameplay 05 carrying cell 1 |
| ![gameplay 08 power restored](2026-11-15-ui-v2/14_gameplay_08_power_restored.jpg)<br>gameplay 08 power restored | ![gameplay 11 after shuttle](2026-11-15-ui-v2/15_gameplay_11_after_shuttle.jpg)<br>gameplay 11 after shuttle |

## 2026-11-15 · icons-v2

Commit `31b1c34` · studio/station renders · 9 frames · [folder](2026-11-15-icons-v2/)

Bespoke icon set (48 icons plus 14 aliases): crew helmet with LED eyes vs infiltrator helmet with a red V-slit, the real cell/core/blaster/shuttle/pod silhouettes, two-tone by default plus full-colour and hex/rounded badges. Readable from 18 px; shapes stay distinct under deuteranopia and protanopia. 00 is the old generic set for comparison.

| | |
| --- | --- |
| ![before overview](2026-11-15-icons-v2/00_before_overview.jpg)<br>before overview | ![after overview](2026-11-15-icons-v2/01_after_overview.jpg)<br>after overview |
| ![after deuteranopia](2026-11-15-icons-v2/02_after_deuteranopia.jpg)<br>after deuteranopia | ![zoom face](2026-11-15-icons-v2/03_zoom_face.jpg)<br>zoom face |
| ![zoom mask](2026-11-15-icons-v2/04_zoom_mask.jpg)<br>zoom mask | ![zoom cell](2026-11-15-icons-v2/05_zoom_cell.jpg)<br>zoom cell |
| ![zoom core](2026-11-15-icons-v2/06_zoom_core.jpg)<br>zoom core | ![zoom airlock](2026-11-15-icons-v2/07_zoom_airlock.jpg)<br>zoom airlock |
| ![zoom throw](2026-11-15-icons-v2/08_zoom_throw.jpg)<br>zoom throw |   |

## 2026-11-15 · character-v3

Commit `7f1781a` · studio/station renders · 22 frames · [folder](2026-11-15-character-v3/)

Owner feedback pass (roundness, surface smoothness, limbs, suit and helmet upgrade): curved wraparound armour with two-piece sculpted thighs, domed knee and elbow caps, smoother 14–16-sided limbs, continuous engraved panel lines, a shaped torso with an off-white abdominal plate, curved hip tassets and backpack, a layered helmet with bezel glow, ear pods and a brow, and ghost legs that dissolve below the knee. About 19k triangles, 2 draw calls. Hands are still the built-in gloves; the dedicated CrewHand comes next.

| | |
| --- | --- |
| ![faces all](2026-11-15-character-v3/00_faces_all.jpg)<br>faces all | ![quarter](2026-11-15-character-v3/01_quarter.jpg)<br>quarter |
| ![legs](2026-11-15-character-v3/02_legs.jpg)<br>legs | ![front](2026-11-15-character-v3/03_front.jpg)<br>front |
| ![side](2026-11-15-character-v3/04_side.jpg)<br>side | ![back](2026-11-15-character-v3/05_back.jpg)<br>back |
| ![helmet](2026-11-15-character-v3/06_helmet.jpg)<br>helmet | ![visor](2026-11-15-character-v3/07_visor.jpg)<br>visor |
| ![run strip](2026-11-15-character-v3/08_run_strip.jpg)<br>run strip | ![walk strip](2026-11-15-character-v3/09_walk_strip.jpg)<br>walk strip |
| ![states](2026-11-15-character-v3/10_states.jpg)<br>states | ![carry](2026-11-15-character-v3/11_carry.jpg)<br>carry |
| ![aim](2026-11-15-character-v3/12_aim.jpg)<br>aim | ![action](2026-11-15-character-v3/13_action.jpg)<br>action |
| ![stunned](2026-11-15-character-v3/14_stunned.jpg)<br>stunned | ![ghost](2026-11-15-character-v3/15_ghost.jpg)<br>ghost |
| ![macro knee](2026-11-15-character-v3/16_macro_knee.jpg)<br>macro knee | ![macro elbow](2026-11-15-character-v3/17_macro_elbow.jpg)<br>macro elbow |
| ![joints legs](2026-11-15-character-v3/18_joints_legs.jpg)<br>joints legs | ![variants back](2026-11-15-character-v3/19_variants_back.jpg)<br>variants back |
| ![backs lowlight](2026-11-15-character-v3/20_backs_lowlight.jpg)<br>backs lowlight | ![distance](2026-11-15-character-v3/21_distance.jpg)<br>distance |

## 2026-11-15 · gameplay-v1

Commit `55eab36` · studio/station renders · 13 frames · [folder](2026-11-15-gameplay-v1/)

First real gameplay capture: a 3-player networked bot round (crew win by shuttle), Mobile renderer, phone touch HUD. Character v2 suits (limb rework in progress). Known issues found here: countdown overlaps the alert banner at 720p; camera too high/far so characters read small.

| | |
| --- | --- |
| ![home](2026-11-15-gameplay-v1/00_home.jpg)<br>home | ![lobby](2026-11-15-gameplay-v1/01_lobby.jpg)<br>lobby |
| ![briefing](2026-11-15-gameplay-v1/02_briefing.jpg)<br>briefing | ![spawn commons](2026-11-15-gameplay-v1/03_spawn_commons.jpg)<br>spawn commons |
| ![near cell 1](2026-11-15-gameplay-v1/04_near_cell_1.jpg)<br>near cell 1 | ![carrying cell 1](2026-11-15-gameplay-v1/05_carrying_cell_1.jpg)<br>carrying cell 1 |
| ![before reactor 1](2026-11-15-gameplay-v1/06_before_reactor_1.jpg)<br>before reactor 1 | ![after reactor 1](2026-11-15-gameplay-v1/07_after_reactor_1.jpg)<br>after reactor 1 |
| ![power restored](2026-11-15-gameplay-v1/08_power_restored.jpg)<br>power restored | ![at vault](2026-11-15-gameplay-v1/09_at_vault.jpg)<br>at vault |
| ![before shuttle](2026-11-15-gameplay-v1/10_before_shuttle.jpg)<br>before shuttle | ![after shuttle](2026-11-15-gameplay-v1/11_after_shuttle.jpg)<br>after shuttle |
| ![result](2026-11-15-gameplay-v1/12_result.jpg)<br>result |   |

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

