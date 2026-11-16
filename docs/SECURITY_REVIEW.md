# Publication security and privacy review

Reviewed November 15, 2026, for the initial public source publication.

## Scope and findings

- Read all application source and headers, the icon generator, build script, both app property lists, Xcode project, entitlements, and privacy manifest.
- Traced audio capture, local device/process inspection, panel preferences, menus, device selection, and resource cleanup. No networking, telemetry, credentials, saved audio files, dynamic code download, shell execution from app input, third-party runtime dependency, or privileged helper was found.
- The app examines local Core Audio process/device properties to detect input activity. It does not send or persist that inventory. Global mouse monitoring is limited to dismissing an open menu; it does not register a keyboard logger.
- The App Store target requests App Sandbox and audio-input access. It has no network, user-file, automation, or temporary-exception entitlement. The existing local build is not sandboxed.
- Added checked audio-buffer size arithmetic before multiplication and allocation. Added explicit clearing of the app-owned microphone sample buffer after peak measurement and before freeing it. Output audio buffers remain owned by Core Audio and are not retained by the app.
- The privacy manifest declares app-only UserDefaults (CA92.1) and elapsed-time measurement (35F9.1). No collected data or tracking is declared.
- Public files are selected from an allowlist. Signing configuration, profiles, certificates, archives, binaries, test audio, device snapshots, and local logs are excluded. Icon metadata contains only color-space and pixel dimensions; no personal or location metadata was found.

## Validation

- Universal arm64/x86_64 archive compiled and signed with sandbox entitlements.
- Buffer boundary cases passed, including zero/invalid channels, maximal frame counts, overflow limits, and null output pointers. UndefinedBehaviorSanitizer completed without diagnostics.
- Xcode static analysis completed for both the original and final hardened source without analyzer warnings.
- A sandboxed build measured a synthetic output tone at -32 dBFS. Output switching to a second device and restoration worked. Microphone activity appeared while another application used the selected input and cleared when that application closed; no recording was saved.

## Limits

This review is not an independent penetration test or proof of absence of vulnerabilities. AddressSanitizer stalled at startup on the validation host and is not counted as a passing check. Intel hardware, macOS 14.2, all third-party audio drivers, physical microphone peak response, disconnect/wake recovery, and every display/accessibility configuration were not fully validated. Avoid publishing personal device names or desktop captures in issue reports or screenshots.
