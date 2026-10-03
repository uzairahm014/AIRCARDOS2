# How to use AirCard

There are **two separate programs**. They are not the same thing and they do
different jobs.

| | What it is | Where it runs | What it does |
|---|---|---|---|
| **AirCard (Windows)** | `aircard.exe` | Your PC | Controls your iPhone over USB. Applies tweaks, writes files, verifies them. **This is the one that works today.** |
| **AirCard-iOS (iPhone)** | an `.app` you build from source | Your iPhone | Runs the on-device AI (chat, voice, vision). **Requires a Mac to build.** |

---

## Part 1 — AirCard on Windows (works now)

### Run it

```bash
cd core-engine
cargo run --release --example probe_host   # is your phone visible?
```

Then run the GUI:

```bash
cargo run --release --manifest-path windows-engine/Cargo.toml
```

### Connect your phone

1. Plug in USB, **unlock the screen**, and tap **Trust** if prompted.
2. Close iTunes / Apple Devices on the PC — they hold the lockdown port and
   AirLift will fail if they win the race.
3. The window should show your device as `iPhone14,3 · iOS 27.0 (24A437)`.

### The one rule

**Every real write requires the canary to pass first.** The canary writes a
small file into `/var/mobile/Library/SpringBoard` and reads it back. If it
fails, no tweak will be applied. This is deliberate — it proves the transport
actually works before anything is modified.

If you see `keep screen unlocked` in the log, unlock the phone and leave it
awake. A locked iPhone will not complete the sync.

---

## Part 2 — Tweaks that are verified on your phone

### From the GUI

**Library** tab → pick a tweak → **DRY RUN** first (shows exactly which files
would be written and how big), then **APPLY**.

Only tweaks with an implementation show an APPLY button. Everything else shows
its reason for being unsupported. There are no decorative buttons.

### From the command line

```bash
# Change the carrier name shown in the status bar
cargo run --example run_tweak -- StatusBar.CustomCarrier \
    carrier_primary="AirCard" carrier_badge_primary="A"

# Undo it — SpringBoard deletes its own archive
cargo run --example run_tweak -- StatusBar.CustomCarrier reset=true

# Apply a passcode theme
cargo run --example run_tweak -- Passcode.CustomTheme \
    passthm_path=/path/to/theme.passthm

# Roll back everything from this session
cargo run --example run_tweak -- StatusBar.CustomCarrier --restore
```

### What each one needs to show up

| Tweak | After applying |
|---|---|
| Status bar carrier | **Reboot the phone.** `systemstatusd` caches overrides. |
| Passcode theme | Lock the screen and wake it. **Bold Text must be OFF** — iOS renders vector fonts instead of your artwork when it's on. |

---

## Part 3 — The PosterBoard wallpaper (partially working)

The files write successfully and verify byte-exact, but **the poster does not
appear in the wallpaper picker yet.** PosterBoard needs a registration step on
iOS 27 that this tool hasn't found. Treat this one as unfinished.

If you try it:

```bash
cargo run --example scan_container -- 150   # keep the Wallpaper app open!
```

That reads the app-container UUID off the device log. Then:

```bash
cargo run --example run_tweak -- PosterBoard.CustomWallpaper \
    tendies_path=/path/to/wallpaper.tendies \
    posterboard_container=/var/mobile/Containers/Data/Application/<UUID>
```

**Budget ~45 minutes.** AirLift handles one file per sync session at ~900 ms
per move, so ~135 files takes most of an hour.

---

## Part 4 — Building the iPhone app

The AI app is real source but has **never been compiled** — there's no macOS
here. Two routes, depending on whether you have a Mac.

### No Mac? Build in the cloud (works from Windows)

Xcode only runs on macOS. Codemagic rents you a macOS machine, and
`codemagic.yaml` is already in the zip:

1. Push the unzipped folder to a GitHub repo.
2. Sign in at [codemagic.io](https://codemagic.io) with GitHub → add the repo →
   it finds `codemagic.yaml` automatically.
3. Press **Start new build**.
4. Download `AirCard-iOS.ipa` from the artifacts.

Then install it **from Windows**:

- **[Sideloadly](https://sideloadly.io)** — drag the IPA in, enter your Apple
  ID, install. Works on Windows.
- **AltStore** — same idea, imports the IPA.

Both sign it with your Apple ID so iOS accepts it. A free Apple ID works; the
app then expires after 7 days and you re-install weekly.

### Got a Mac?

```bash
brew install xcodegen
cd AirCard-iOS

# The Rust core ships prebuilt as AirliftFFI.xcframework, so skip this unless
# you changed rust-core/:
./build-ios.sh Release

./build-ipa.sh --sign          # signed, installable
```

> ⚠️ `./build-ipa.sh` with **no** arguments builds an **unsigned** IPA. iOS
> will refuse to install it. Use `--sign`.

**Expect to fix compile errors on the first build**, cloud or local. None of
the Swift here has been through `swiftc`. That's normal, not a sign that
something is wrong.

### Once it runs

Open the **AI** tab. The header states exactly what your specific iPhone
supports. If Apple Intelligence is off, it says so — it will not fake a reply.

**The notch bar** sits in the notch band above the chat. Compact it shows the
live state; tap it to expand into a panel with mic and status controls.

---

## Things that will never work on this phone

Not bugs — hardware or platform limits:

| Feature | Why |
|---|---|
| Island **over other apps** | The notch bar works *inside* AirCard-iOS. Floating over SpringBoard needs code injection into Apple's processes, which this tool does not do. |
| Always-on background wake word | iOS won't let an app run unrestricted background audio for this. |
| Reading other apps' screens | Sandboxed, and needs code injection. |
| Private Messages content | Sandboxed by Apple. No legitimate route. |
| Bundled anime characters | Copyrighted. Art must be supplied by you. |
| System keyboard theme, sounds, animation speed | No file-level representation exists. |