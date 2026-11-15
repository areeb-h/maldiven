# Android Friends Lab 0.3.0 build

Date: 2026-11-12. Separate install package `com.areebh.maldiven.friends`; root island remains 0.2.0.

| Item | Observed value |
| --- | --- |
| APK | `maldiven-friends-0.3.0-arm64.apk` |
| Bytes | 28387291 |
| APK SHA-256 | `58f31d957c9e9bdc180500fae2e5f69cb1d5871e76c90336a8300112a0a15d75` |
| Input fingerprint | `8ab48e3ae5e8cca9f7bf61c8c565f5b2a4403c6c543c985908fa8e2da79d3c1c` |
| Godot | 4.7.2.stable.official.ed1daf0bf Standard |
| Export templates | Official pinned 4.7.2 archive, checksum verified |
| Build host | Linux x86-64; Java 21.0.13 |
| SDK tools | Build-tools 35.0.1; platform-tools 37.0.1; Android 35 platform installed |
| Template manifest | minSdk 24 / targetSdk 36 / compileSdk 36 |
| ABI | arm64-v8a only |
| Version | code 3 / name 0.3.0-lab |
| Renderer | GL Compatibility; 2x MSAA |
| Permissions | INTERNET, RECORD_AUDIO, MODIFY_AUDIO_SETTINGS |
| Signing | Debug; verified v2/v3 signature |

The prebuilt Android template controls the target/compile manifest; no custom Gradle/native compilation was performed. The exporter reports using build-tools 35.0.1 as a fallback for the template target. Signature verification, ZIP integrity, `zipalign -c -P 16 -v 4`, and 16 KiB ELF load-segment alignment pass. Game code, voice adapter, phone compatibility manifest and application configuration are present. Server/probe/check scripts and all private keys/admission files are excluded. Export/import logs have no script/engine errors. The packaged desktop entry point starts without a CLI script override.

`aapt2` reports an unused `themed_icon.xml` resource-table reference from the prebuilt template; that optional file is absent. The main launcher icon/adaptive icon and the app label are present. Android launcher/themed-icon behaviour is not physically verified. The build host's ADB daemon is unavailable; no connected-device installation was attempted.

The [combined evidence](milestones/evidence/friends-phone-2026-11-12.json) records 87 automated checks and APK metadata. None establishes actual microphone quality, Android installation, real Wi-Fi, Windows-specific behaviour, latency or thermals.

Install from the accompanying APK download (or extract the install ZIP), then follow the [PC server and phone guide](pc-server-and-phone.md). The signing certificate fingerprint is `9b7dd5ce7b1d41222675a9cd7ccbaa7f3dec5652169b58bc1b3e0bc08e5cae71`. A private debug-key continuity backup is retained outside the repository; do not use debug signing for a store release.

Rebuild on a configured host:

```bash
python tools/build_friends_android.py
python tools/build_friends_android.py --pack-only
```

Hosting on the PC needs neither the Android SDK nor export templates. Full setup is in the guide.
