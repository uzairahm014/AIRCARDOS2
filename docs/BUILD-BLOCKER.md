# Build blocker: no macOS toolchain on this machine

**This is the one thing in the specification that cannot be delivered from here,
and it is stated plainly rather than worked around.**

## What is missing

`AirCard-Ultimate.ipa` and `AirCard-AI.ipa` cannot be produced, signed, or
verified on this machine, because it has no macOS and therefore no:

- `xcodebuild` / Xcode / Swift toolchain
- iOS SDK (the app targets iOS 18+ deployment with arm64)
- Apple code-signing certificate, provisioning profile, or `.xcframework` build host
- iOS Simulator or device runtime for verification

The repo already contains `build-ios.sh` and `build-ipa.sh`, which are real and
were carried over from the upstream project. They will work on a Mac with Xcode
installed. They were **not** run here, and nothing in this repository should be
read as evidence that they succeed.

## What that means for the iOS-side files

Every Swift file added in this session is marked `COMPILES-UNVERIFIED` in its
header comment:

- `ios-app/AirCardLibrary/AirCardLibrary.swift`
- `ios-app/AirCardLibrary/TweakLibraryView.swift`
- `ios-app/AirCardLibrary/AirCardSystemBridge.swift`
- `tests/AirCardLibraryTests.swift`

They were written against the real `AirliftFFI.xcframework` header
(`al_exploit_write_dir`, `al_device_respring`, `al_string_free`, …) and the real
`AppViewModel` API, and their logic is pinned by tests that mirror the Rust
engine's own tests. But **they have never been through `swiftc`.** Expect to fix
compile errors on first build. They are not claims; they are a starting point.

## What *is* verified

The Rust core engine and the Windows app are built, run and tested on this
machine:

| Claim | Status | Evidence |
| --- | --- | --- |
| Passcode theme (`.passthm` → `TelephonyUI-10`), 59/59 files byte-exact | **VERIFIED ON DEVICE** | `docs/DEVICE-TEST-REPORT.md` |
| Status bar carrier override (`StatusBarOverrides.archive`) | **VERIFIED ON DEVICE** | same |
| Status bar reset record | **VERIFIED ON DEVICE** | same |
| AirLift canary (sandbox escape works) | **VERIFIED ON DEVICE** | same |
| Tweak library parsing, compatibility, search, packs | **TESTED** | 63 Rust tests, green |
| Windows app (egui), real transport + mock | **WORKS ON DEVICE** | `windows-engine/target/release/aircard.exe`, `docs/preview-*.png` |
| Everything else, including all iOS Swift | **NOT VERIFIED** | no toolchain |

Measured device for all of the above: **iPhone14,3 / iOS 27.0 / 24A437**.

## What to do on a Mac

```bash
# 1. Build the Rust FFI into the xcframework
./build-ios.sh Release

# 2. Regenerate the Xcode project (project.yml now includes ios-app/AirCardLibrary)
xcodegen generate

# 3. Build and run the tests
xcodebuild -project AirCard-iOS.xcodeproj -scheme AirCard-iOS \
  -destination 'platform=iOS Simulator,name=iPhone 15' test

# 4. Package the IPA
./build-ipa.sh Release
```

Then fix whatever `swiftc` reports in the four files above, run the test suite,
and only then attach a real iPhone to verify the AI layer. Nothing in the AI
stack has been run on hardware yet, and the AI layer is where the honest gaps
are largest: a local LLM, vision model and TTS engine all need real measurement
on an A15 before any speed or memory claim can be made.
