# Android resource test builds 0.2.0

Built 2026-11-12 from resource commit b68e22d2471ed2de6adaf263e7722118a8d7cea3 using tools/build_android.py and Godot 4.7.2 stable.

## Variants
- Normal: Maldiven, com.areebh.maldiven, Mobile/Vulkan with 2x MSAA.
- Diagnostic: Maldiven GL Test, com.areebh.maldiven.compat, Compatibility/OpenGL with 2x MSAA. Can install beside the normal build.
- Both: version 0.2.0 (code 2), ARM64 only, no requested Android permissions, same test signing certificate as 0.1.0.

## Validation performed
- Resource import/collision tests and movement/multi-touch smoke tests pass.
- Both APK exports succeed from fresh temporary project copies.
- APK v2/v3 signatures, ZIP integrity, ZIP 16 KB alignment and native ELF 16 KB segment alignment pass.
- Packaged settings confirm the intended renderer, 2x MSAA and expanded screen aspect.
- Nine resource scenes are packaged; test/docs/preview resources are excluded.
- Physical installation, graphical appearance, removal of horizontal bands, touch comfort and sustained performance remain unverified on the user's phone.

## Phone check
Install the normal APK over 0.1.0. It uses the same package ID and signing certificate, with a higher version code. Check the new models, movement, simultaneous look/jump and pause/background recovery. If the horizontal bands remain, install GL Test separately and compare the same view. Report which build shows the issue, preferably with a screenshot.

## Rebuild

```bash
python3 tools/build_android.py --godot /path/to/godot --renderer mobile
python3 tools/build_android.py --godot /path/to/godot --renderer compatibility
```

## Artifact checksums

- maldiven-0.2.0-arm64.apk
  - 28535323 bytes
  - SHA256: bf0cf726109141b972ca0b2fc85be34b610dd7425a8114f8be868a4069d915d4

- maldiven-0.2.0-gl-test-arm64.apk
  - 28535323 bytes
  - SHA256: 0a9a82a04d90ee350c42fd97ce7ccc41e81b75361d7d38fc8276ce862a11e9ba
