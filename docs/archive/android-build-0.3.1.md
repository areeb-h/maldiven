# Friends Lab 0.3.1: invite-entry update

Date: 2026-11-12. Fixes the reported invite-entry flow with defensive paste handling and an importable private text-file alternative. [Usage instructions](pc-server-and-phone.md#paste-unavailable-on-android-import-an-invite-file), [ADR 0024](adr/0024-invite-entry-and-document-import.md), [scoped evidence](milestones/evidence/invite-entry-2026-11-12.json).

| Item | Value |
| --- | --- |
| APK | `maldiven-friends-0.3.1-arm64.apk` |
| Bytes | 28391387 |
| SHA-256 | `75100afd53707734770a9505daa18c8578dca7eb1b612a8cfa0f2d4bf1045e13` |
| Package | `com.areebh.maldiven.friends` |
| Version | 0.3.1-lab / code 4 |
| ABI | ARM64 |
| Signer SHA-256 | `9b7dd5ce7b1d41222675a9cd7ccbaa7f3dec5652169b58bc1b3e0bc08e5cae71` |
| Permission set | INTERNET, RECORD_AUDIO, MODIFY_AUDIO_SETTINGS; unchanged |
| Engine | Official pinned Godot 4.7.2 Standard |

The existing debug signing identity was recovered and reused, with matching certificate verification. Signature, ZIP/ELF 16 KiB alignment, production scripts, secret/test-script exclusions and packaged desktop startup pass. Twenty-one actual Godot Friends Lab checks and four Python endpoint/export tests pass for the recorded source input. The menu checks now include clipboard-empty preservation, formatting/padding tolerance, file import/error recovery and no premature microphone/network activity. Normal and empty-clipboard menu frames were rendered and inspected with software GL. The unused themed-icon resource reference from the official prebuilt template remains as recorded in 0.3.0; main icon/label are present.

Physical Android clipboard/keyboard/native file-picker behaviour, Windows/WSL-to-tunnel routing and audible phone voice are pending owner tests. This is not a claim that the Android report was reproduced on hardware. The earlier complete 87-check record remains historical for its own source fingerprint, not relabelled as a fresh full regression run.

For file import, update/restart the PC launcher to generate private files. Its network protocol is unchanged and the new phone app can still connect using an ordinary valid 0.3.0 invite.
