# COMPATIBILITY.md — iOS 27.0 / 24A437 / iPhone 13 Pro Max (iPhone14,3)

Every row is justified. **"VERIFIED ON DEVICE"** means this engine wrote to a
physical iPhone14,3 running iOS 27.0 (24A437) and read the exact bytes back off
the device. "SUPPORTED" means the mechanism is delivered by this engine's real
primitives and verified by upstream projects. "UNSUPPORTED" means there is **no**
non-jailbreak write path on this build — the reason is stated, not guessed.

Last hardware run: see [docs/DEVICE-TEST-REPORT.md](docs/DEVICE-TEST-REPORT.md) for the
reproducible log of every run.

## Master matrix

| Feature | Status on 24A437 | Tested on device? | Mechanism / Reason |
|---|---|---|---|
| **Passcode themes** (`.passthm`) | ✅ SUPPORTED | ✅ **VERIFIED ON DEVICE** — 59/59 files written and read back byte-exact | Keypad PNGs (`en\|ru\|uk\|ja\|…-N-sub--white[-bold].png` + `_big`) into `/var/mobile/Library/Caches/TelephonyUI-10`. Requires **Bold Text OFF**. |
| **Status bar — carrier name** | ✅ SUPPORTED | ✅ **VERIFIED ON DEVICE** — 671-byte NSKeyedArchiver record written and read back byte-exact | `StatusBarOverrides.archive` (`_SBSystemStatusStatusBarOverridesArchiveRecord` → `STStatusBarData` → cellular entries). SpringBoard unarchives it at launch. Mechanism verified end-to-end on physical iOS 27 hardware by GoldenNugget 9.5.x. |
| **Status bar — reset to native carrier** | ✅ SUPPORTED | ✅ **VERIFIED ON DEVICE** — 429-byte reset record written and read back byte-exact | The reset record makes SpringBoard delete its own archive (native eviction), after which a new record can be written. This is the rollback path. |
| **Wallet card skins** | ✅ SUPPORTED | ⚠️ **Write path verified; card targeting untested** | Write `cardBackgroundCombined@3x.png`, `@2x.png`, `.pdf` into `/var/mobile/Library/Passes/Cards/<hash>.pkpass`; invalidate `FrontFace`/`PlaceHolder`/`Preview` caches. Requires a real card hash, discovered by streaming the syslog while Wallet is opened (`scan_card`). See the report for what happened on this device. |
| **PosterBoard wallpapers** (`.tendies`) | ◐ PARTIAL | ⚠️ **Write path verified; container path required** | Descriptors go to `<container>/Library/Application Support/PRBPosterExtensionDataStore/61/Extensions/<bundle>/descriptors/<uuid>/…` plus a `com.apple.PosterBoard.unprotectedUserDefaults.plist` cache refresh. The container path is **not** discoverable: it lives in `/var/mobile/Containers/Data/Application/<uuid>`, and AirLift cannot list or read directories. The user must supply it. |
| Home Screen icons (image swaps) | ◐ PARTIAL | ❌ not tested | Icon image swaps via SpringBoard icon caches under `/var/mobile/Library/SpringBoard`. |
| System sounds | ◐ PARTIAL | ❌ not tested | Files can be placed under `/var/mobile/Media`; wholesale replacement needs paths outside scope. |
| Lock Screen wallpapers | ✅ (via PosterBoard) | ⚠️ see PosterBoard | Wallpaper layer via PosterBoard descriptors. |
| Status bar — icons/bars/time/battery | ❌ UNSUPPORTED | — | iOS 27's SystemStatusUI archive record has no representation for these; the legacy `statusBarOverrides` engine is gated off by a FeatureFlags store (`/var/preferences/FeatureFlags/Settings.plist`) that no non-jailbreak path can write (13 documented upstream attempts). |
| Lock Screen clock/widget styling | ❌ UNSUPPORTED | — | No writable user-domain store exposes clock font/size/color on iOS 27; needs SpringBoard code hooks (jailbreak-tier). |
| SpringBoard tweaks (Managed Preferences) | ❌ UNSUPPORTED | — | GoldenNugget's keys (`SBDontLockAfterCrash`, `SBHideLowPowerAlerts`, …) live in `/var/Managed Preferences/mobile/com.apple.springboard.plist` — outside AirLift's verified scope. |
| Liquid Glass parameters | ❌ UNSUPPORTED | — | Solarium/Calistoga keys live in Managed Preferences — outside scope. |
| Dynamic Island (genuine) | ❌ UNSUPPORTED | — | iPhone14,3 has a notch, not a cutout. Cannot be created in software. No software claim is made. |
| Control Center / Notifications appearance | ❌ UNSUPPORTED | — | No user-domain override files on iOS 27. |
| Animation speed scaling | ❌ UNSUPPORTED | — | Not exposed in any writable preference store on iOS 27. |
| Charging / boot / shutdown UI | ❌ UNSUPPORTED | — | Charging HUD and boot graphics live in the sealed root filesystem (SSV). Deliberately not touched to avoid bootloops. |
| Keyboard | ❌ UNSUPPORTED | — | Keyboard caches outside verified scope. |
| Lock Screen footnote | ❌ UNSUPPORTED | — | `SharedDeviceConfiguration.plist` is under `/var/containers/Shared/SystemGroup/...` — outside scope; needs MDM or a backup-restore pipeline. |
| MobileGestalt | ❌ UNSUPPORTED | — | TCC-protected on iOS 17+; the AirLift README states plainly it does not work on the MobileGestalt plist. |
| Daemons (`disabled.plist`) | ❌ UNSUPPORTED | — | `/var/db/com.apple.xpc.launchd/disabled.plist` is outside `/var/mobile`. |

## What was measured on real hardware (iPhone14,3 · iOS 27.0 · 24A437)

These are findings from running this engine, not from reading docs. They are
encoded in `core-engine/src/ops.rs` and `airtraffic.rs`.

1. **Identifiers and destinations use different bases.** Book "Persistent ID"
   asset identifiers resolve against `/var/mobile/Media/Airlock/Book`; the
   AssetCompleted destinations resolve against `/var/mobile/Media`. Getting this
   wrong silently produces an empty Media root and no writes at all.
2. **Consecutive asset moves need ~900 ms.** Upstream sleeps 900 ms between
   `AssetCompleted` messages. A shorter gap makes the sandbox-exit move silently
   no-op.
3. **The asset queue must be short.** One file per `com.apple.atc` session (four
   asset moves) is reliable. A 59-file session moves almost nothing. Every write
   is therefore chunked to a single file per session.
4. **There is no read primitive.** ATAirlock will only relocate a file it created
   *in the current sync*; a pull targeting a pre-existing file is silently
   refused. Verified with a controlled experiment: the identical plan succeeds
   when the pull targets the file just written and fails when it targets an older
   one. Consequences, all surfaced to the user rather than papered over:
   - Backups of pre-existing files are impossible. `BackupSession` records
     `Unreadable` and the UI says the original bytes cannot be restored.
   - There is no delete primitive either, so a file this engine creates stays on
     the device until something else removes it.
   - **Rollback is "write a known-good replacement", not "delete what I wrote".**
     Every built-in tweak therefore ships a reset/default record.
5. **Verification is real.** Each write relocates the file it just wrote into a
   place AFC can read and compares sha256. "Applied" means the device holds those
   bytes, not that AirTraffic reported success.

## The write-scope contract

AirLift's verified scope (upstream README, fresh-file writes confirmed):

```
/var/mobile
/var/mobile/Documents
/var/mobile/Library
/var/mobile/Library/Preferences
/var/mobile/Library/Caches
/var/mobile/Library/SpringBoard
/var/mobile/Library/SMS
/var/mobile/Library/Safari
/var/mobile/Containers
/var/mobile/Containers/Data/Application
/var/mobile/Containers/Shared/AppGroup
/var/tmp
```

Not covered: MobileGestalt plist, `/var/preferences`, `/var/Managed Preferences`,
`/var/containers/Shared/SystemGroup`, `/var/db`, system volume.

## Known operational constraints

1. **Books app** — the AirTraffic sync requires the Apple Books app installed and
   opened at least once on the device.
2. **Screen state** — the device must be unlocked with the screen on during sync.
3. **iTunes closed** — Apple Devices/iTunes on the PC must not hold a session.
4. **Bold Text OFF** — required for passcode themes; iOS renders vector fonts
   instead when it is on.
5. **Reboot for the status bar** — systemstatusd caches overrides in memory, so
   the carrier name only appears after a reboot.
6. **ATAirlock overwrite behaviour** — overwriting an existing file does work
   (verified on device: writing the same leaf twice both verified), but each
   write is still a full replace with no backup of the original.

## Devices

The engine targets iPhone14,3, but the mechanisms are path-based and apply to any
device running iOS 27.x inside AirLift's scope. PosterBoard structure versions
differ by release (59 ≤ iOS 16, 61 = iOS 17–27 observed); the engine targets 61.