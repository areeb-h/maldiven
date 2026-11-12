# ADR 0024: Recoverable invite entry and private document import

Date: 2026-11-12. Status: Accepted for Friends Lab 0.3.1; physical Android validation pending.

## Context and decision

The owner reports that invite pasting does not work on Android. The initial paste callback overwrote the field even when the clipboard returned an empty string, and parsing rejected whitespace inserted while transferring a long invite. The report does not establish a specific Android clipboard/root cause.

Focus the input before reading the clipboard on a deferred callback, preserve entered text when the clipboard is unavailable, and explain the failure. Normalize bounded text for wrapping/BOM/zero-width formatting, code-fence wrappers and omitted trailing base64 padding. Retain exact payload keys, bounded JSON and existing certificate/session validation. Show ready/incomplete status and keep actions above the field.

Add an explicit native FileDialog using filesystem access, opening one user-selected plain-text invite with a 24,000-byte limit. No broad storage or camera permission is requested. Do not auto-connect on selection. The PC launcher creates individual private crew invite.txt files (0600 in a 0700 directory on POSIX, inherited restricted state ACLs on Windows) and download links in the local invite page. Files contain existing single-use tickets and retain their original expiry. They must not enter Git, logs or public file hosting.

## Validation and consequences

Godot checks cover empty-clipboard preservation, wrapped/zero-width input, missing padding, file loading, error recovery and no microphone/network activity before connect. Python tests check exported file content against the invite envelope. Existing real DTLS/movement/voice and public-advertisement checks are retained. Packaged startup and a rendered join-screen inspection pass. Neither desktop dummy tests nor UI screenshots establish physical Android clipboard/document-provider operation.

The same Android package/certificate is used with versionCode 4, permitting an update over the shipped 0.3.0 debug build. No network protocol, ticket lifetime or endpoint changes are required.

Primary reference: https://docs.godotengine.org/en/4.7/classes/class_filedialog.html
