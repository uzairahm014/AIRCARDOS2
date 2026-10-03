//
//  AirCardSystemBridge.swift
//  AirCard-iOS
//
//  One place where a library entry turns into a real device write.
//
//  The AI layer and the Tweak Library talk to this bridge; the bridge talks to
//  AirliftFFI. Nothing in the AI stack touches the exploit path directly, so a
//  tweak cannot quietly grow a second, unverified write route.
//
//  Two rules hold here, and they are the reason this file exists:
//
//    1. `apply(_:)` only accepts ids it can map to a concrete staged write.
//       Anything else fails with a reason. There is no "best effort" branch.
//
//    2. A successful return code means the FFI call succeeded. It does **not**
//       mean the tweak is verified. The caller decides what to do with that,
//       and the library records the difference.
//
//  COMPILES-UNVERIFIED: authored on Windows. Never through swiftc.
//  See docs/BUILD-BLOCKER.md.
//

import Foundation
import AirliftFFI

/// Result of an apply attempt. `verified` is deliberately separate from
/// `succeeded`: the FFI returning 0 is not verification.
public struct ApplyResult {
    public let succeeded: Bool
    public let verified: Bool
    public let detail: String
    /// Paths that were actually written, for the log.
    public let written: [String]

    public static func failure(_ detail: String) -> ApplyResult {
        ApplyResult(succeeded: false, verified: false, detail: detail, written: [])
    }
}

/// Every operation the library can actually reach on this build.
public enum TweakOperation: String, CaseIterable {
    case flashPasscode   = "Passcode.CustomTheme"
    case flashWallet     = "Wallet.CardSkin"
    case flashPosterBoard = "PosterBoard.CustomWallpaper"
    case setCarrier      = "StatusBar.CustomCarrier"

    public var displayName: String {
        switch self {
        case .flashPasscode: return "Passcode theme"
        case .flashWallet: return "Wallet card skin"
        case .flashPosterBoard: return "PosterBoard wallpaper"
        case .setCarrier: return "Status bar carrier"
        }
    }
}

@MainActor
public final class AirCardSystemBridge {
    public static let shared = AirCardSystemBridge()

    /// Rolling log shown in Developer mode.
    public private(set) var log: [String] = []

    private init() {}

    /// Map a library `impl_id` onto an operation, or nil when there is no
    /// compiled implementation. Nil here is the reason the UI shows no button.
    public static func operation(forImplID id: String) -> TweakOperation? {
        TweakOperation(rawValue: id)
    }

    /// Apply an operation.
    ///
    /// This does **not** stage any assets itself — each operation routes to the
    /// existing, already-working flash path in `AppViewModel`, which owns the
    /// asset staging and the locale/weight variants. The bridge exists to give
    /// one honest entry point and one log, not to duplicate that code.
    public func apply(_ implID: String) -> ApplyResult {
        guard let op = AirCardSystemBridge.operation(forImplID: implID) else {
            let result = ApplyResult.failure(
                "No compiled implementation is registered for '\(implID)'."
            )
            append("✖ \(implID): no implementation")
            return result
        }

        let model = AppViewModel.shared
        guard let model, model.hasPairingFile else {
            let result = ApplyResult.failure(
                "No pairing file. Import your AirCard pairing file before applying."
            )
            append("✖ \(op.displayName): no pairing file")
            return result
        }

        append("→ \(op.displayName) starting")
        switch op {
        case .flashPasscode:
            guard model.canFlashPassthm else {
                append("✖ Passcode: nothing ready to flash")
                return ApplyResult.failure(
                    "No passcode artwork is loaded. Open a .passthm or add a key first."
                )
            }
            model.flashPassthm()

        case .flashWallet:
            guard model.canFlashCards else {
                append("✖ Wallet: nothing selected to flash")
                return ApplyResult.failure(
                    "No Wallet card has artwork attached, or a flash is already running."
                )
            }
            model.flashCards()

        case .flashPosterBoard:
            let selected = model.tendieItems.filter(\.isSelected)
            guard !selected.isEmpty else {
                append("✖ PosterBoard: no wallpaper selected")
                return ApplyResult.failure(
                    "No .tendies wallpaper is selected. Load a pack and tick an item."
                )
            }
            guard !model.posterBoardContainer.trimmingCharacters(
                in: .whitespacesAndNewlines
            ).isEmpty else {
                append("✖ PosterBoard: container path unknown")
                return ApplyResult.failure(
                    "The PosterBoard container path is not set. AirLift has no directory \
                     listing, so it cannot be discovered — paste it in first."
                )
            }
            Task { await model.flashSelectedTendies() }

        case .setCarrier:
            // The iOS build has no carrier editor yet; the write itself is
            // verified on the desktop engine. Rather than stub this, the bridge
            // refuses and says where the real path is.
            append("✖ Status bar: no carrier editor in the iOS build")
            return ApplyResult.failure(
                "The carrier override is configured in the Windows AirCard app. This iOS \
                 build has no carrier editor yet, so there is nothing to send."
            )
        }

        // The FFI call was made. That is all this can honestly claim — the
        // on-device read-back verification lives in the flash paths themselves
        // and is reported by their phase callbacks.
        append("✓ \(op.displayName) write issued")
        return ApplyResult(
            succeeded: true,
            verified: false,
            detail: "Write issued through AirLift. "
                  + "Verification is reported by the flash log as each asset is read back.",
            written: []
        )
    }

    /// Requests a respring. Never called automatically: AirCard reports the
    /// requirement and the user decides, because a respring drops what the
    /// phone is doing.
    public func requestRespring(reason: String) -> Bool {
        let pairing = PairingController.pairingFilePath()
        append("↻ respring requested: \(reason)")
        var outError: UnsafeMutablePointer<CChar>?
        let rc = pairing.withCString { p in
            al_device_respring(p, { _, msg in
                guard let msg = msg else { return }
                Task { @MainActor [weak self] in
                    self?.append("    \(String(cString: msg))")
                }
            }, nil, nil, &outError)
        }
        if let e = outError {
            append("✖ respring failed: \(String(validatingUTF8: e))")
            al_string_free(e)
        }
        return rc == 0
    }

    /// Whether a respring could even be attempted right now.
    public var canRespring: Bool {
        AppViewModel.shared?.hasPairingFile ?? false
    }

    private func append(_ line: String) {
        log.append(line)
        if log.count > 500 { log.removeFirst(log.count - 500) }
    }

    public func clearLog() { log.removeAll() }
}
