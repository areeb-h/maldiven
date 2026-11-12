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
| [0011](0011-round-and-session-lifecycle.md) | Match lifecycle, reconnect and outcomes | Proposed |

ADRs should state context, choice, alternatives/consequences and validation. Record a replacement rather than erasing a decision that informed prior builds.
