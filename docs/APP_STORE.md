# Twinwave App Store release

Status: signed universal archive prepared; not yet uploaded, submitted, approved, or released.

- Title: Twinwave
- Subtitle: Your Mac audio at a glance
- Category: Utilities
- Bundle ID: com.cheeseapps.twinwave (registered)
- Version/build: 1.3.2 (16)
- Minimum macOS: 14.2
- Architectures: Apple silicon and Intel (runtime testing on Apple silicon only)
- Sandbox: audio input; no network or file access entitlement
- Data collection: none in the inspected source
- Price/regions: US$0.99 base price, worldwide availability

## Build

Copy Configuration/Local.xcconfig.example to Configuration/Local.xcconfig and set the enrolled developer team. Archive the shared Twinwave App Store scheme with Xcode. Keep certificates, provisioning profiles and team-local configuration out of source control. The original build.sh remains the local nonsandboxed build.

## Listing draft

See your Mac’s input and output levels in a small, native audio panel. Expand Twinwave to check device names, then choose a microphone or output directly from its menus.

- Follow your selected input and output with compact peak meters.
- See when another app is using the selected microphone.
- Switch system audio devices without opening Sound settings.
- Keep the panel in a bottom corner or drag it where you need it.
- Work entirely on your Mac. No accounts, uploads, ads, or subscriptions.

Microphone and system-audio permission are required for metering. The microphone meter measures while another audio client is using the selected input. Twinwave shows levels; it does not save recordings or enhance audio.

## Required verification

- Build and archive with App Sandbox and distribution signing.
- Verify system-output metering, microphone activity and peaks, and device switching in the sandboxed build; restore original devices afterward.
- Verify permission denial/retry, quit/relaunch, panel dragging, menus, and placement persistence.
- Complete public support/privacy URLs, screenshots, age rating, privacy declaration, pricing, review contact, and tester validation before submission.
