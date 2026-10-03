// AirCard AI — speech: on-device recognition and synthesis.
//
// Both run locally through Apple's frameworks. Nothing is uploaded.
//
// BUILD STATUS: not compiled here (no macOS/Xcode). See docs/BUILD-BLOCKER.md.

import AVFoundation
import Foundation
import Observation
import Speech

/// Wraps `SFSpeechRecognizer` in on-device mode plus `AVSpeechSynthesizer`.
@Observable
@MainActor
public final class SpeechRuntime: NSObject, Sendable {
    public static let isRecognitionAvailable: Bool = {
        if #available(iOS 26, *) {
            // Prefer a recognizer that can work with no network at all.
            return SFSpeechRecognizer(locale: .current)?.supportsOnDeviceRecognition == true
        }
        return false
    }()

    public enum Mode: String, Sendable { case idle, listening, transcribing, speaking }

    public private(set) var mode: Mode = .idle
    public private(set) var transcript: String = ""
    public private(set) var authorization: SFSpeechRecognizerAuthorizationStatus = .notDetermined
    public private(set) var lastError: String?

    /// Record a failure from outside the runtime (for example when a caller's
    /// `catch` block learns why an operation failed).
    public func report(_ message: String?) { lastError = message }

    private let synthesizer = AVSpeechSynthesizer()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    public override init() {
        super.init()
        authorization = SFSpeechRecognizer.authorizationStatus()
        synthesizer.delegate = self
    }

    // MARK: - Authorization

    @discardableResult
    public func requestAuthorization() async -> Bool {
        let granted = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
        authorization = SFSpeechRecognizer.authorizationStatus()
        return granted
    }

    // MARK: - Recognition

    /// Stream microphone audio into an on-device recognizer, appending to `transcript`.
    public func startListening(locale: Locale = .current) async throws {
        if authorization != .authorized {
            let granted = await requestAuthorization()
            guard granted else {
                lastError = "Speech recognition permission was denied."
                throw AIRuntimeError.permissionDenied
            }
        }
        stop()

        guard let recognizer = SFSpeechRecognizer(locale: locale) else {
            lastError = "No speech recognizer for \(locale.identifier)."
            throw AIRuntimeError.unavailable
        }
        guard recognizer.supportsOnDeviceRecognition else {
            // We refuse to silently fall back to a network recognizer: the whole
            // point of this stack is that audio stays on the device.
            lastError = "This locale has no on-device recognizer, so audio would have to leave the phone. Not doing that."
            throw AIRuntimeError.requiresNetwork
        }

        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        // Keep audio on device even if the OS offers a server path.
        req.requiresOnDeviceRecognition = true
        request = req

        mode = .listening
        transcript = ""
        lastError = nil

        task = recognizer.recognitionTask(with: req) { [weak self] result, error in
            Task { @MainActor in
                guard let self else { return }
                if let result {
                    self.transcript = result.bestTranscription.formattedString
                    if result.isFinal {
                        self.mode = .idle
                        self.stop()
                    }
                }
                if let error {
                    // A cancelled task is the normal result of stop(); not an error.
                    if (error as NSError).code != 203 && (error as NSError).code != 216 {
                        self.lastError = error.localizedDescription
                    }
                    self.mode = .idle
                    self.stop()
                }
            }
        }
    }

    /// Append one buffer of captured audio. Call from the mic tap.
    public func append(_ buffer: AVAudioPCMBuffer) {
        request?.append(buffer)
    }

    public func stop() {
        request?.endAudio()
        request = nil
        task?.cancel()
        task = nil
        if mode != .speaking { mode = .idle }
    }

    // MARK: - Synthesis

    public func speak(_ text: String, voice: AVSpeechSynthesisVoice? = nil) async throws {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice ?? AVSpeechSynthesisVoice(language: Locale.current.identifier)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        mode = .speaking
        synthesizer.speak(utterance)
    }

    public func stopSpeaking() {
        synthesizer.stopSpeaking(at: .immediate)
        mode = .idle
    }

    /// List the on-device voices actually installed on this phone.
    public static var installedVoices: [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix(Locale.current.language.languageCode?.identifier ?? "en") }
    }
}

extension SpeechRuntime: AVSpeechSynthesizerDelegate {
    nonisolated public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.mode = .idle }
    }

    nonisolated public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in self.mode = .idle }
    }
}

public enum AIRuntimeError: LocalizedError {
    case permissionDenied
    case unavailable
    case requiresNetwork
    case modelUnavailable(String)

    public var errorDescription: String? {
        switch self {
        case .permissionDenied: return "Permission denied."
        case .unavailable: return "Not available on this device."
        case .requiresNetwork: return "This needs a network round trip, which AirCard AI will not do silently."
        case .modelUnavailable(let why): return why
        }
    }
}