# Architecture decision records

Updated 2026-11-12. Accepted records indicate an agreed direction, not implementation or successful validation. Proposed records require the listed technical/playtest gates. Superseded records remain historical evidence.

| Record | Topic | Status |
| --- | --- | --- |
| [0001](0001-engine-and-language.md) | Godot and typed GDScript baseline | Proposed baseline; retained |
| [0002](0002-rendering-and-world.md) | Island rendering and world assets | Superseded for active world by 0008 |
| [0003](0003-platform-and-toolchain.md) | Offline Android/toolchain | Superseded for online architecture by 0006/0007; toolchain history retained |
| [0004](0004-device-rendering-workaround.md) | Android horizontal corruption | Proposed; device validation pending |
| [0005](0005-space-station-direction.md) | Space-station social-game direction | Accepted direction |
| [0006](0006-authoritative-multiplayer.md) | Dedicated server authority and hidden state | Proposed |
| [0007](0007-native-voice-feasibility.md) | Early Android voice experiment and provider boundary | Proposed |
| [0008](0008-station-layout-and-assets.md) | Modular station topology and asset pipeline | Proposed |
| [0009](0009-combat-and-recovery.md) | Recoverable conflict and one-weapon scope | Proposed |
| [0010](0010-evidence-and-playtesting.md) | Research, measurement and player participation | Proposed |
| [0011](0011-round-and-session-lifecycle.md) | Match lifecycle, reconnect and outcomes | Proposed; absence response superseded by 0019 |
| [0012](0012-systemic-station-and-expansion.md) | Systemic station and expansion horizons | Proposed |
| [0013](0013-interaction-protocol-and-invariants.md) | Transactions, protocol and invariants | Proposed |
| [0014](0014-bounded-event-director.md) | Bounded event director | Proposed for H2 |
| [0015](0015-experience-and-release-evidence.md) | Experience and release evidence gates | Proposed |
| [0016](0016-allegiance-jobs-and-equipment.md) | Separate allegiance, jobs and equipment | Proposed; H2 job board |
| [0017](0017-evidence-provenance-and-agreements.md) | Evidence provenance and explicit agreements | Proposed |
| [0018](0018-curated-mission-variants.md) | Curated mission variants before procedural combinations | Proposed for H2 |
| [0019](0019-uniform-roster-interruption.md) | Uniform roster grace/interruption without role leak | Proposed H1 clarification |
| [0020](0020-local-admission-experiment.md) | Isolated local admission and identity boundary | Accepted for the verified local lab only |
| [0021](0021-server-clock-motion-and-replicas.md) | Server-clock motion and public pose replicas | Accepted for the initial local movement lab |
| [0022](0022-lan-phone-and-pcm-voice-experiment.md) | LAN phone invites, DTLS and native PCM voice candidate | Accepted for the isolated experiment; physical/provider gates open |
| [0023](0023-public-udp-tunnel-invites.md) | Public UDP tunnel advertisements for the existing phone APK | Accepted for launcher; external route test pending |

ADRs should state context, choice, alternatives/consequences and validation. Record a replacement rather than erasing a decision that informed prior builds.
