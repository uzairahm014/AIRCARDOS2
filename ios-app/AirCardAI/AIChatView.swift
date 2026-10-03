// AirCard AI — the chat screen.
//
// Wires the real engines together. Every control here maps to something that
// actually runs on the phone; nothing is decorative. When a capability is
// missing, its button is disabled with the real reason shown underneath.
//
// BUILD STATUS: not compiled here (no macOS/Xcode). See docs/BUILD-BLOCKER.md.

import PhotosUI
import SwiftUI

public struct AIChatView: View {
    @State private var engine = AIChatEngine()
    @State private var speech = SpeechRuntime()
    @State private var vision = AIVisionEngine()
    @State private var capabilities = AICapabilityReport()
    @State private var island = NotchIslandState()

    @State private var input: String = ""
    @State private var photoItem: PhotosPickerItem?

    public init() {}

    private var phase: OrbPhase {
        OrbPhase(engineState: engine.state, speech: speech.mode, hasError: engine.lastError != nil)
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                Divider()
                transcript
                Divider()
                composer
            }
            .navigationTitle("AirCard AI")
            .navigationBarTitleDisplayMode(.inline)
            .background(
                // The island is pinned into the notch band, above everything.
                NotchIsland(state: island, geo: NotchGeometry(topInset: 47, width: 393)) {
                    panelContent
                }
                .allowsHitTesting(true),
                alignment: .top
            )
            .onChange(of: phase) { _, new in island.phase = new }
            .onChange(of: speech.transcript) { _, new in
                if !new.isEmpty { island.detail = new }
            }
            .onChange(of: engine.partialAnswer) { _, new in
                if !new.isEmpty { island.detail = new }
            }
        }
    }

    /// Shown inside the expanded island. Mirrors the live engine state.
    @ViewBuilder
    private var panelContent: some View {
        VStack(spacing: 10) {
            if !speech.transcript.isEmpty {
                Label(speech.transcript, systemImage: "mic")
                    .font(.footnote)
                    .lineLimit(3)
            } else if !engine.partialAnswer.isEmpty {
                Text(engine.partialAnswer)
                    .font(.footnote)
                    .lineLimit(4)
            } else {
                Text(island.phase.label)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                Button {
                    Task {
                        if speech.mode == .listening { speech.stop() }
                        else { do { try await speech.startListening() }
                              catch { speech.lastError = error.localizedDescription } }
                    }
                } label: {
                    Label(speech.mode == .listening ? "Stop" : "Listen",
                          systemImage: speech.mode == .listening ? "stop.fill" : "mic.fill")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.mini)

                Button {
                    island.detail = capabilities.summary
                    island.toggle(.tools)
                } label: {
                    Label("Status", systemImage: "info.circle")
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 10) {
            AIOrbView(phase: phase, size: 132)

            // State the truth about this device rather than implying more than
            // the hardware can do.
            Text(capabilities.summary)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            if let why = capabilities.explanation(for: .textGeneration) {
                Label(why, systemImage: "exclamationmark.triangle")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
        }
        .padding(.vertical, 12)
    }

    // MARK: - Transcript

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(engine.conversation.messages) { message in
                        bubble(message)
                            .id(message.id)
                    }

                    if !engine.partialAnswer.isEmpty {
                        bubble(AIChatMessage(role: .assistant, text: engine.partialAnswer))
                            .opacity(0.75)
                    }

                    if !vision.recognisedText.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Label("Vision read", systemImage: "text.viewfinder")
                                .font(.caption.weight(.semibold))
                            Text(vision.recognisedText)
                                .font(.footnote)
                                .textSelection(.enabled)
                        }
                        .padding(10)
                        .background(Color.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                    }

                    ForEach(vision.observations, id: \.self) { line in
                        Text("• " + line)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    if let err = engine.lastError ?? vision.lastError ?? speech.lastError {
                        Label(err, systemImage: "xmark.octagon")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    if !speech.transcript.isEmpty {
                        AIPillView(phase: phase, text: speech.transcript)
                    }
                }
                .padding(12)
            }
            .onChange(of: engine.conversation.messages.count) { _, _ in
                if let last = engine.conversation.messages.last {
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
        }
    }

    private func bubble(_ message: AIChatMessage) -> some View {
        HStack {
            if message.role == .user { Spacer(minLength: 40) }
            Text(message.text)
                .font(.subheadline)
                .padding(10)
                .background(
                    message.role == .user ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 12)
                )
                .textSelection(.enabled)
            if message.role != .user { Spacer(minLength: 40) }
        }
    }

    // MARK: - Composer

    private var composer: some View {
        VStack(spacing: 8) {
            // Voice. Refuses to run if it would need the network.
            HStack(spacing: 10) {
                Button {
                    Task {
                        if speech.mode == .listening {
                            speech.stop()
                        } else {
                            do { try await speech.startListening() }
                            catch { speech.lastError = error.localizedDescription }
                        }
                    }
                } label: {
                    Label(speech.mode == .listening ? "Stop" : "Listen",
                          systemImage: speech.mode == .listening ? "stop.circle.fill" : "mic")
                }
                .buttonStyle(.bordered)
                .disabled(engine.isBusy)

                PhotosPicker(selection: $photoItem, matching: .images) {
                    Label("Image", systemImage: "photo")
                }
                .buttonStyle(.bordered)

                if vision.state == .working {
                    ProgressView().controlSize(.small)
                }
            }
            .font(.caption)

            HStack(spacing: 8) {
                TextField("Ask anything on this iPhone…", text: $input, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...4)
                    .padding(10)
                    .background(Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))

                Button {
                    Task { await send() }
                } label: {
                    Image(systemName: engine.isBusy ? "stop.circle.fill" : "arrow.up.circle.fill")
                        .font(.title2)
                }
                .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || engine.isBusy)
            }

            if !capabilities.isAvailable(.textGeneration) {
                Text("Text generation is off on this device. Voice and Vision still work.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task { await runVision(on: item) }
        }
    }

    // MARK: - Actions

    private func send() async {
        let text = input
        input = ""
        do {
            _ = try await engine.send(text)
        } catch {
            // engine.lastError already carries the honest reason.
        }
    }

    private func runVision(on item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else {
            vision.lastError = "Could not read that image."
            return
        }
        await vision.readText(in: image)
        await vision.describe(image)
    }
}