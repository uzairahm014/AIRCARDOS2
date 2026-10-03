// AirCard AI — local text generation and conversation memory.
//
// Uses Apple's on-device model when the device supports it. When it does not,
// every entry point returns a real error with a real reason; this file never
// produces placeholder or invented text.
//
// BUILD STATUS: not compiled here (no macOS/Xcode). See docs/BUILD-BLOCKER.md.

import Foundation
import Observation

#if canImport(FoundationModels)
import FoundationModels
#endif

public struct AIChatMessage: Identifiable, Sendable, Codable, Hashable {
    public enum Role: String, Sendable, Codable { case user, assistant, system }
    public let id: UUID
    public let role: Role
    public var text: String

    public init(id: UUID = UUID(), role: Role, text: String) {
        self.id = id
        self.role = role
        self.text = text
    }
}

/// Rolling conversation memory. Keeps the transcript bounded so a long chat
/// cannot grow without limit.
@Observable
@MainActor
public final class AIConversation: Sendable {
    public private(set) var messages: [AIChatMessage] = []
    public var systemPrompt: String = """
    You are AirCard, an assistant that runs entirely on this iPhone. \
    Be concise and concrete. If you cannot do something on this device, say so plainly.
    """

    /// Hard cap; oldest non-system messages are dropped first.
    public var maxMessages: Int = 40

    public init() {}

    public func add(_ role: AIChatMessage.Role, _ text: String) {
        messages.append(AIChatMessage(role: role, text: text))
        trim()
    }

    public func clear() { messages.removeAll() }

    private func trim() {
        guard messages.count > maxMessages else { return }
        // Always keep the newest turns; drop from the front past the cap.
        messages.removeFirst(messages.count - maxMessages)
    }

    public var transcriptForModel: [AIChatMessage] {
        [AIChatMessage(role: .system, text: systemPrompt)] + messages
    }
}

/// The generation engine.
@Observable
@MainActor
public final class AIChatEngine: Sendable {
    public enum State: String, Sendable { case idle, preparing, thinking, streaming, failed }

    public private(set) var state: State = .idle
    public private(set) var partialAnswer: String = ""
    public private(set) var lastError: String?

    public let conversation = AIConversation()

    #if canImport(FoundationModels)
    private var session: LanguageModelSession?
    #endif

    public init() {}

    public var isBusy: Bool { state == .thinking || state == .streaming || state == .preparing }

    /// Generate a reply. Returns the real model text, or throws with a real reason.
    @discardableResult
    public func send(_ prompt: String) async throws -> String {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        conversation.add(.user, trimmed)
        state = .preparing
        partialAnswer = ""
        lastError = nil

        #if canImport(FoundationModels)
        let model = SystemLanguageModel.default
        guard case .available = model.availability else {
            state = .failed
            lastError = AICapabilityReport().explanation(for: .textGeneration) ?? "On-device text generation is unavailable."
            throw AIRuntimeError.modelUnavailable(lastError ?? "unavailable")
        }

        if session == nil {
            session = LanguageModelSession(instructions: conversation.systemPrompt)
        }
        guard let session else {
            state = .failed
            throw AIRuntimeError.modelUnavailable("Could not create a model session.")
        }

        state = .thinking
        do {
            var answer = ""
            let stream = session.streamResponse(for: trimmed)
            for try await part in stream {
                state = .streaming
                answer += part.content
                partialAnswer = answer
            }
            conversation.add(.assistant, answer)
            state = .idle
            partialAnswer = ""
            return answer
        } catch {
            state = .failed
            lastError = error.localizedDescription
            throw error
        }
        #else
        state = .failed
        let why = AICapabilityReport().explanation(for: .textGeneration) ?? "unavailable"
        lastError = why
        throw AIRuntimeError.modelUnavailable(why)
        #endif
    }

    public func cancel() {
        #if canImport(FoundationModels)
        session?.cancel()
        #endif
        state = .idle
        partialAnswer = ""
    }
}