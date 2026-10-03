# AirCard-iOS — source for building an IPA

This is the complete iPhone app source. On a Mac it builds into a signed,
installable `.ipa`.

## Before you start: the honest status

**No file in `ios-app/` has ever been compiled.** There was no macOS or Xcode
available while this was written, so the Swift has not been through `swiftc`.
It is complete and real, but **expect to fix ordinary compile errors on your
first build.** That is normal, not a sign of a broken package.

The Rust engine and the Windows app *were* built, tested, and run against a
real iPhone 13 Pro Max (iOS 27.0). See `docs/DEVICE-TEST-REPORT.md` for what
was actually verified there.

## What works today

Two tweaks are verified working on real hardware:

| Tweak | Requirement to see it |
|---|---|
| Status bar carrier name | Reboot after applying |
| Passcode theme (.passthm) | Lock + wake; **Bold Text must be OFF** |

The PosterBoard wallpaper writes and verifies but does not yet appear in the
wallpaper picker — it is **PARTIAL**, not done.

## Build it

You need **macOS with Xcode**. That is the hard requirement; everything else is
included.

```bash
brew install xcodegen
cd AirCard-iOS
./build-ipa.sh --sign
```

Output: `build/AirCard-iOS.ipa`, signed.

### The signing flag matters

```bash
./build-ipa.sh            # unsigned — iOS will REFUSE to install this
./build-ipa.sh --sign     # signed — actually installable
```

A free Apple ID works via Xcode (Run to device); the app then expires after 7
days. A paid account lets you use `--sign` and sideload with AltStore or
Sideloadly.

## No Mac? Build it in the cloud

`codemagic.yaml` is included, so you can produce the IPA from **Windows**,
without ever installing Xcode. Xcode only runs on macOS; Codemagic rents you a
macOS machine.

1. Push this folder to a GitHub repo.
2. Sign in at **codemagic.io** with GitHub, add the repo, let it find
   `codemagic.yaml`.
3. Press **Start new build**.
4. Download `AirCard-iOS.ipa` from the artifacts.

Then install it **from Windows** with a sideloader — [Sideloadly](https://sideloadly.io)
or AltStore. Both run on Windows and will sign the IPA with your Apple ID so
iOS accepts it.

```
Codemagic (cloud Mac)  →  unsigned .ipa  →  Sideloadly on Windows  →  iPhone
```

Full walkthrough with screenshots-to-follow in `docs/CLOUD-BUILD.md`.

Not verified: this config has never been executed here, for the same reason
the local build has not. First run will likely surface compile errors.

## There is no IPA in this zip, and no tool can make one on Windows

This zip is **source code** — 247 files, no `.ipa`, no `.app`. An IPA is
compiled ARM64 code linked against Apple's iOS SDK, and Apple only ships that
toolchain for macOS. No Windows converter exists; any site claiming otherwise
is either a scam or is uploading your files elsewhere. The cloud build above is
the route.

## You probably do not need Rust

`AirliftFFI.xcframework` ships prebuilt with arm64 device and simulator slices,
so `xcodegen` + `xcodebuild` is all that's required.

Only if you change `rust-core/` do you need to rebuild it first:

```bash
./build-ios.sh Release    # needs rustup with the iOS targets
```

## Layout

```
ios-app/            Swift sources
  AirCardLibrary/   tweak library UI (mirrors the Rust engine)
  AirCardAI/        on-device AI: chat, speech, vision, tools, orb
core-engine/library/  101 tweak definitions (JSON, shared with Windows)
AirliftFFI.xcframework/ prebuilt Rust FFI, arm64
rust-core/          Rust FFI source (only needed if you rebuild it)
project.yml         XcodeGen spec
build-ios.sh        rebuild the xcframework
build-ipa.sh        build + sign + package the IPA
docs/               compatibility, device test report, AI stack
```

## About the AI stack

Everything runs **on the phone** — no cloud fallback, by design. If a
capability is missing, the app states the reason rather than inventing output.
Speech recognition deliberately refuses to fall back to Apple's servers.

### The notch bar ("Dynamic Island")

`ios-app/AirCardAI/NotchIslandView.swift` renders a real, expanding capsule
pinned into the **notch band** — the top safe-area region your iPhone 13 Pro Max
cuts out. It behaves like the Dynamic Island: compact pill showing live state,
tap to expand into a panel, spring animation, orb bound to the real engine
state.

What it is: a working Dynamic Island look and behaviour, inside AirCard-iOS.

What it is not: it cannot float over SpringBoard or other apps, and it does not
follow you out of the app. Those need code injection into other processes or
ownership of the system surface, neither of which this tool does. Claiming
otherwise would be faking it.

See `docs/AI-STACK.md`.

## Where to look when something fails

1. `docs/HOW-TO-USE.md` — running either program, per-tweak requirements
2. `docs/BUILD-BLOCKER.md` — exactly what could not be verified, and why
3. `docs/DEVICE-TEST-REPORT.md` — measured results on real hardware
4. `COMPATIBILITY.md` — per-feature support on iOS 27