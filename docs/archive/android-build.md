# Android test build 0.1.0

Built on 2026-11-12 from movement prototype commit 6d4f592 with the committed Android export preset. This is a debug-signed test build, not a Play Store release.

## Build toolchain
- Godot 4.7.2 stable Standard and matching official Android debug export template.
- Godot template archive SHA256: f298490b8d44d934be425a5a65a51bf15f422428b229a06a6e11d9ffea248011 (verified against official release metadata).
- Android SDK Build Tools 35.0.1; Platform Tools 37.0.1.
- OpenJDK 21.0.13 (supported by Godot; documentation recommends 17).
- Prebuilt APK export, without custom Gradle build, NDK or CMake compilation.

Configure Godot Editor Settings > Export > Android with the local Java and Android SDK paths. Install matching export templates. Godot's normal debug keystore must exist; signing keys stay outside the repository.

```bash
mkdir -p builds
godot --headless --path . --editor --import
godot --headless --path . --script res://tests/movement_smoke.gd
godot --headless --path . --export-debug Android builds/maldiven-0.1.0-arm64.apk
```

## Package
- Application: Maldiven
- ID: com.areebh.maldiven
- Version: 0.1.0 (code 1)
- ABI: arm64-v8a only
- Landscape, immersive view; Mobile/Vulkan renderer.
- Template manifest min SDK 24, target SDK 36. The Mobile renderer additionally requires compatible Vulkan hardware/drivers and a supported Android version; this package is intended for a modern Android phone.
- No requested Android permissions, accounts or network service dependency.

## Verification
- Godot import, movement smoke tests and Android export completed successfully.
- apksigner verification passes v2 and v3 signature checks.
- zipalign -c -P 16 4 passes.
- APK ZIP integrity passes; game resources are present and tests/documentation are excluded.
- Native library ELF alignment checked separately in the build workflow.
- Godot warns that SDK 35.0.1 build-tools differ from target SDK 36. The prebuilt template exports and signs successfully. Older aapt badging reports an attribute-type warning for injected Vulkan features; raw manifest inspection confirms those optional feature entries. Physical installation is still required to validate package behaviour.

## Phone test
1. Download the APK, open it and allow installation from the downloading app if prompted.
2. Open Maldiven in landscape.
3. Move with the left stick; drag on the right to rotate the camera; use the bottom-right jump control.
4. Try moving, rotating and jumping together; test the ramp, stairs and camera-obstruction wall.
5. Pause/resume and background/reopen the app. Check for stuck input or camera clipping.
6. Play for ten minutes and report crashes, heat, stutter or uncomfortable controls.

The scene uses placeholder geometry and a capsule character. Saves, sound, detailed art and animated character visuals are not implemented. No physical-device or emulator installation was performed in this environment.

## Artifact
APK SHA256: cb8349d11ac82954a5dfec659a5ffa8a5396194218a6b813671f8bcb5c4d6907
Size: 28259175 bytes.
