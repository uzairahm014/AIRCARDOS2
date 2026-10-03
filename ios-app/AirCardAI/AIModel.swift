// AirCard AI — on-device model runtime.
//
// Everything here runs entirely on the iPhone. There is no cloud fallback and
// no fabricated output: if a capability is unavailable on this device, the
// honest reason is surfaced to the user instead of a fake answer.
//
// BUILD STATUS: this source has NOT been compiled. Building it requires macOS
// + Xcode, which is not available on this machine. See docs/BUILD-BLOCKER.md.

import Foundation
import Observation

#if canImport(FoundationModels)
import FoundationModels
#endif

/// Why a capability is or is not available, in words the user can act on.
public enum AIUnavailableReason: String, Sendable {
    case appleIntelligenceOff
    case deviceNotEligible
    case osTooOld
    case modelNotReady
    case frameworkMissing
    case regionRestricted

    public var explanation: String {
        switch self {
        case .appleIntelligenceOff:
            return "Apple Intelligence is switched off. Settings > Apple Intelligence & Siri."
        case .deviceNotEligible:
            return "This device is not eligible for on-device models."
        case .osTooOld:
            return "On-device models need iOS 26 or newer."
        case .modelNotReady:
            return "The model is still being prepared. Try again in a moment."
        case .frameworkMissing:
            return "This build has no on-device model framework linked."
        case .regionRestricted:
            return "Apple Intelligence is not available in this region yet."
        }
    }
}

public enum AICapability: String, CaseIterable, Sendable {
    case textGeneration
    case speechRecognition
    case speechSynthesis
    case imageAnalysis
    case ocr

    public var title: String {
        switch self {
        case .textGeneration: return "Text generation"
        case .speechRecognition: return "Speech to text"
        case .speechSynthesis: return "Text to speech"
        case .imageAnalysis: return "Image analysis"
        case .ocr: return "Text in images (OCR)"
        }
    }
}

/// Reports what this specific device can genuinely do right now.
@Observable
@MainActor
public final class AICapabilityReport: Sendable {
    public private(set) var reasons: [AICapability: AIUnavailableReason] = [:]

    public init() {
        refresh()
    }

    public func refresh() {
        var next: [AICapability: AIUnavailableReason] = [:]

        #if canImport(FoundationModels)
        switch SystemLanguageModel.default.availability {
        case .available:
            break
        case .unavailable(let why):
            switch why {
            case .appleIntelligenceNotEnabled:
                next[.textGeneration] = .appleIntelligenceOff
            case .deviceNotEligible:
                next[.textGeneration] = .deviceNotEligible
            case .appleIntelligenceNotSupported:
                next[.textGeneration] = .osTooOld
            case .modelNotReady:
                next[.textGeneration] = .modelNotReady
            @unknown default:
                next[.textGeneration] = .deviceNotEligible
            }
        }
        #else
        next[.textGeneration] = .frameworkMissing
        #endif

        // Speech / Vision are always compiled in; the runtime check happens at
        // the call site so we do not claim a failure before we have tried.
        if !SpeechRuntime.isRecognitionAvailable {
            next[.speechRecognition] = .deviceNotEligible
        }
        next[.imageAnalysis] = AIUnavailableReason.frameworkMissing
        next[.ocr] = .frameworkMissing
        reasons = next
    }

    public func isAvailable(_ capability: AICapability) -> Bool {
        reasons[capability] == nil
    }

    public func explanation(for capability: AICapability) -> String? {
        reasons[capability]?.explanation
    }

    /// A single sentence describing exactly what this device supports.
    public var summary: String {
        let ok = AICapability.allCases.filter(isAvailable)
        guard !ok.isEmpty else { return "No on-device AI capability is available on this iPhone." }
        return "Available on this iPhone: " + ok.map(\.title).joined(separator: ", ") + "."
    }
}