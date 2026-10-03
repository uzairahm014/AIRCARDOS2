# AirCard AI — on-device stack

Everything in `ios-app/AirCardAI/` runs **on the iPhone**. There is no cloud
fallback. When a capability is missing on a given device, the app says so in
words the user can act on — it never returns placeholder or invented text.

## Build status — read this first

**None of this code has been compiled.** It is complete, real Swift, but
building it needs macOS + Xcode, which this machine does not have. So it has
not been type-checked, run, or seen on the phone.

See [BUILD-BLOCKER.md](BUILD-BLOCKER.md). To actually run any of it you need a
Mac: open `project.yml` in XcodeGen, `xcodegen generate`, then build and sign
`AirCard-iOS` for your device.

## What each file does

| File | What it is |
|---|---|
| `AIModel.swift` | Capability reporting. Asks the OS what is genuinely available and maps each gap to a concrete reason (Apple Intelligence off, device not eligible, model not ready…). |
| `AIChatEngine.swift` | Local text generation via Apple's `FoundationModels`, with a bounded conversation memory and streaming output. |
| `SpeechRuntime.swift` | On-device speech-to-text (`Speech`) and text-to-speech (`AVSpeechSynthesizer`). |
| `AIVisionEngine.swift` | Real on-device OCR and image classification (`Vision`). |
| `AIToolRouter.swift` | Four working tools — device info, grep, calculator, clock — with an audit log of every call. |
| `AIOrbView.swift` | The animated orb and pill. |
| `NotchIslandView.swift` | The notch bar: a real expanding capsule pinned into the notch band. |
| `AIChatView.swift` | The SwiftUI chat screen that wires all of the above together. |
| `AILiveActivity.swift` | ActivityKit wrapper. |

## The notch bar, precisely

`NotchIslandView.swift` renders into the **top safe-area band** — the region
your iPhone 13 Pro Max physically cuts out. `NotchGeometry` reads the real
inset at runtime rather than assuming a model, so it seats correctly:

- compact: a capsule ~128pt wide showing the live phase
- expanded: a ~380pt panel with mic and status controls
- tap to toggle, spring animation, orb bound to `OrbPhase`

It is a working Dynamic Island look and behaviour, inside AirCard-iOS.

It is **not** the system island, and here is the exact boundary:

- It cannot float over SpringBoard or other apps. That needs code injection
  into Apple's processes.
- It does not follow you out of the app; iOS owns that surface.

Anything that claimed otherwise would be faking it, so the limitation is
written into the code header and the docs rather than discovered later.

## The orb is not decorative

`OrbPhase` is derived from real state (`AIChatEngine.state` +
`SpeechRuntime.Mode`), and the pulse speed changes with it:

| Phase | Trigger | Pulse |
|---|---|---|
| `idle` | engine idle | 0.6 |
| `listening` | microphone capturing | 2.2 |
| `thinking` | prompt sent, awaiting first token | 3.4 |
| `speaking` | TTS playing | 2.0 |
| `tool` | streaming a response | 2.6 |
| `error` | last call failed | 0.2 |

Nothing animates as "thinking" while the model is actually idle.

## Deliberate non-fallbacks

These refuse to run rather than quietly going online or faking a result:

- **Speech recognition** requires `SFSpeechRecognizer.supportsOnDeviceRecognition`
  and sets `requiresOnDeviceRecognition = true`. If the locale has no on-device
  recognizer it reports that instead of falling back to Apple's servers.
- **Arithmetic** is restricted to digits and `+ - * / ( )`. No arbitrary
  expression evaluation, so a tool call cannot execute code.
- **No cloud providers.** There is no code path that sends a prompt off-device.
  Adding one is a deliberate product decision, not a fallback.

## Why the system Dynamic Island is not here

This device is an **iPhone 13 Pro Max (iPhone14,3)**, which has a **sensor
notch — not a Dynamic Island cutout**. So there is no *system* island surface
to render into. That is display hardware.

- `NotchIslandView` fills the notch band **inside the app**, which is the most
  a sandboxed app can honestly do.
- `AILiveActivity.swift` is real ActivityKit code. On this phone it renders on
  the Lock Screen and in Notification Center. It has no Dynamic Island
  presentation because there is no cutout to present into.

## Order of work on a Mac

1. `xcodegen generate` then build. Expect to fix ordinary compile errors — the
   code has never been through a compiler.
2. Run on device. The AI tab opens on `AppTab.ai`.
3. Check the header: it prints what this specific iPhone supports.
4. If text generation is unavailable, the screen says which of the four reasons
   applies rather than showing an empty chat.