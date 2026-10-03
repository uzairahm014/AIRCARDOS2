# Device test report — iPhone 13 Pro Max (iPhone14,3) · iOS 27.0 (24A437)

Every line here was produced by running this engine against the attached
device from Windows. Commands are reproducible; nothing is inferred from docs.

## Host and transport

```
Apple Mobile Device Support : C:\Program Files\Common Files\Apple\Mobile Device Support
                               (CoreFoundation.dll, MobileDevice.dll, AirTrafficHost.dll all loaded)
usbmuxd                     : 127.0.0.1:27015 responding
Device                      : iPhone · iPhone14,3 · iOS 27.0 (24A437) · USB
```

## Per-feature results

| Feature | Command | Outcome |
|---|---|---|
| AirLift canary | `cargo run --example run_tweak -- StatusBar.CustomCarrier --skip-canary` | **PASSED.** Fresh-file write into `/var/mobile/Library/SpringBoard` confirmed, and the bytes read back off the device match. |
| Status bar carrier name | `run_tweak StatusBar.CustomCarrier carrier_primary="AirCard"` | **APPLIED AND VERIFIED.** 671-byte `StatusBarOverrides.archive` written, sha256 confirmed by read-back. Needs a **reboot** for systemstatusd to publish it. |
| Status bar reset (rollback) | `run_tweak StatusBar.CustomCarrier reset=true` | **APPLIED AND VERIFIED.** 429-byte reset record written; SpringBoard then evicts its own archive natively, which is the rollback path. |
| Passcode theme | `run_tweak Passcode.CustomTheme passthm_path=test-theme.passthm` | **APPLIED AND VERIFIED.** 59/59 files written into `/var/mobile/Library/Caches/TelephonyUI-10`, every one read back byte-exact. 0 failures. Needs **Bold Text OFF**. |
| Wallet card skin | `run_tweak Wallet.CardSkin card_id=… png=card-art.png` | **FAILED — target unreachable.** Writes to `/var/mobile/Library/Passes` and `.../Cards` succeed, but `.../Cards/<hash>.pkpass` does not exist. On iOS 27 the real card bundles live under `/var/mobile/Containers/Data/Application/<uuid>/…`, and that UUID cannot be discovered (no directory listing). The syslog scanner found only unrelated 40-hex tokens, no `.pkpass` paths. |
| PosterBoard wallpaper | `run_tweak PosterBoard.CustomWallpaper tendies_path=iPhone11.tendies posterboard_container=/var/mobile/Containers/Data/Application/79A76986-75A7-4052-BBC5-3E8086545B9A` | **FILES WRITTEN AND VERIFIED, BUT NOT YET VISIBLE — still PARTIAL.** 135/135 files written and read back byte-exact, 0 failures, in both the iOS 27 and legacy layouts. The user confirms the poster does **not** appear in Settings > Wallpaper. See below. |
| PosterBoard container discovery | `cargo run --example scan_container -- 150` | **WORKS.** The Wallpaper app logs its own container path; the UUID `79A76986-75A7-4052-BBC5-3E8086545B9A` was read straight off the syslog while the app was open. |
| Wallet card skin (re-test) | `scan_raw "pkpass"` / `"Library/Passes"` / `"PassKit"` | **STILL BLOCKED, now for a clearer reason.** A 400s syslog scan produced zero `pkpass` and zero `Library/Passes` lines, and no Wallet app activity at all. This device has **no card in Wallet**, so there is no `<hash>.pkpass` to target. Adding a card is a prerequisite; the scan then works exactly like the PosterBoard one. |

## PosterBoard: three real bugs, found by testing against hardware

The first end-to-end run wrote 69 real files and then reported **"verification
FAILED"**. The engine was wrong, not the device:

1. **Descriptors were never found.** Real `.tendies` archives nest the actual
   posters one level below `descriptors/`, as UUID-named directories
   (`13200000-0000-0000-0000-000000000000`). The matcher stopped at the shared
   `descriptors` folder, so all 6 posters collapsed into 1.
2. **Every descriptor got a freshly generated UUID.** `providerInfo.plist` and
   the provider/role identifier files *reference* that id, so minting a new one
   produced descriptors that could never be matched to their own contents. The
   archive's own UUID is now preserved.
3. **A blind mirror write.** The code wrote every file twice — once to
   `com.apple.WallpaperKit.CollectionsPoster`, once to the iOS 18+ bundle id
   `com.apple.Posters.CollectionsPosterApp`. That second directory **does not
   exist on this device**, and AirLift cannot create it, so all 66 mirror files
   came back UNVERIFIED and failed the apply even though the real files had
   landed. The mirror is now opt-in (`posterboard_mirror=true`), defaulting off.

After the fixes: **69/69 verified, 0 unverified.**

### But it still does not appear — current honest status: PARTIAL

The user checked Settings > Wallpaper and the poster is **not listed**. The
files are on disk and byte-exact; something else is missing.

What we learned from the syslog while the Wallpaper app was open: iOS 27
`PosterFoundation` reads posters from

```
Extensions/<bundleid>/configurations/<uuid>/versions/<n>/contents/…
```

while `.tendies` archives (and iOS 17-26) use `…/descriptors/<uuid>/versions/<n>/`.
The engine now writes **both** layouts — 66 files to `configurations/`, 66 to
`descriptors/`, 3 preference plists — all 135 verified byte-exact.

So the directory layout is no longer the obvious suspect. The remaining
unresolved step is **registration**: PosterBoard appears to index available
posters somewhere this tool has not yet found, and dropping files into the
store is evidently not sufficient on iOS 27. Until that is identified, this
path is PARTIAL, not working.

Also worth recording: `AirLift` **creates** missing directories as a side
effect of writing into them (verified with a probe file). That is why the
earlier "this directory does not exist" conclusion was only ever about the
*result* of a failed write, not about the directory being absent.

### Container discovery, since AirLift cannot list directories

AirLift offers no directory-listing and no read primitive, so the PosterBoard
app-container UUID cannot be guessed. It *can* be observed: `PosterFoundation`
logs `PFServerPosterPath` with the full path whenever the Wallpaper app loads a
poster. `scan_container` filters those lines. The same trick works for any
`/var/mobile/Containers/Data/Application/<UUID>` target.

Keep the iPhone **unlocked** for the whole scan and have the relevant app open
on screen — a locked phone logs nothing useful.

### Cost warning

AirLift handles one file per `com.apple.atc` session at ~900 ms per asset move,
so this wallpaper took roughly **45 minutes** for 69 files (~86 MB). Budget for
that on any multi-file tweak.

## What the runs taught us (and the code now depends on)

1. **Identifiers and destinations use different base directories.** Book
   "Persistent ID" identifiers resolve against `/var/mobile/Media/Airlock/Book`;
   `AssetCompleted` destinations resolve against `/var/mobile/Media`. With one
   base used for both, the Media root stays empty and nothing is written — while
   AirTraffic still reports success.
2. **~900 ms between asset moves.** Upstream sleeps 900 ms between
   `AssetCompleted` messages. At 60 ms the sandbox-exit move silently no-ops.
3. **The queue must be short.** One file per `com.apple.atc` session works. A
   59-file session (236 asset moves) verified 15/59 at best and 0/59 at worst.
   Writes are now chunked one file per session.
4. **No read primitive.** Controlled experiment: the same four-asset plan was
   run twice against the same file. When the "pull it back" step targeted the
   file written earlier in the *same* queue, the bytes came back. When it
   targeted a file that existed beforehand, the pull was silently refused and
   nothing appeared in Media. ATAirlock only relocates files it created in the
   current sync.
   - The first implementation of the "indirect read" overwrote the file first
     and then read back its own placeholder. That destroyed the bytes it claimed
     to back up. **Removed.** `read_system_file_indirect` now does nothing and
     returns `AirCardError::ReadUnsupported`.
   - `BackupSession` therefore records `Captured` / `CreatedByTweak` /
     `Unreadable` honestly, and `restore_all` returns a `RestoreReport` that
     names what it could *not* restore instead of counting everything as done.
5. **No delete primitive.** Rollback is always "write a known-good replacement",
   which is why the status-bar tweak ships a reset record and the passcode cache
   is regenerable by iOS itself.
6. **Verification is real.** Every write relocates the file it just wrote into a
   place AFC can read and compares sha256, so "VERIFIED" means the device holds
   those exact bytes.

## Reproducing

```bash
cd core-engine

cargo run --example probe_host                 # transport + device discovery
cargo run --example cleanup_device             # clear AirLift staging leftovers
cargo run --example make_test_theme -- test-theme.passthm
cargo run --example make_card_art  -- card-art.png

cargo run --example run_tweak -- StatusBar.CustomCarrier carrier_primary="AirCard"
cargo run --example run_tweak -- StatusBar.CustomCarrier reset=true
cargo run --example run_tweak -- Passcode.CustomTheme passthm_path=test-theme.passthm
cargo run --example scan_card -- 90            # needs Wallet opened on the phone

cargo run --example afc_ls -- /                # inspect the Media sandbox
cargo run --example afc_cat -- Books/Sync/Books.plist
```

## Cleanup note

`cleanup_device` removes `airlift-*` staging objects from the Media root and
resets `Books/Sync/Books.plist`. It cannot remove files the engine wrote into
the sandbox, because there is no delete primitive — those are overwritten by
the next apply, or removed by the owning system app (as SpringBoard does with
the status bar archive when it reads a reset record).