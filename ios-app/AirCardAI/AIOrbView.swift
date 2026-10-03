// AirCard AI — the orb, and the "AI surface".
//
// The orb animates from the engine's REAL state. There is no random idle
// motion pretending to be thinking: colour, pulse and scale are all bound to
// `AIChatEngine.state` and `SpeechRuntime.mode`.
//
// On a device WITHOUT a Dynamic Island (an iPhone 13 Pro Max has a sensor
// notch) this renders as a normal view inside the app. It cannot overlay
// SpringBoard or other apps — that would need code injection, which AirCard
// does not do.
//
// BUILD STATUS: not compiled here (no macOS/Xcode). See docs/BUILD-BLOCKER.md.

import SwiftUI

/// Visual state of the orb, derived from the real runtime.
public enum OrbPhase: String, Sendable {
    case offline, idle, listening, thinking, speaking, tool, error

    public init(engineState: AIChatEngine.State, speech: SpeechRuntime.Mode, hasError: Bool) {
        if hasError { self = .error; return }
        switch speech {
        case .listening, .transcribing: self = .listening; return
        case .speaking: self = .speaking; return
        case .idle: break
        }
        switch engineState {
        case .thinking, .preparing: self = .thinking
        case .streaming: self = .tool
        case .failed: self = .error
        case .idle: self = .idle
        }
    }

    var tint: Color {
        switch self {
        case .offline: return .gray
        case .idle: return .cyan
        case .listening: return .green
        case .thinking: return .orange
        case .speaking: return .purple
        case .tool: return .blue
        case .error: return .red
        }
    }

    var label: String {
        switch self {
        case .offline: return "offline"
        case .idle: return "ready"
        case .listening: return "listening"
        case .thinking: return "thinking"
        case .speaking: return "speaking"
        case .tool: return "working"
        case .error: return "error"
        }
    }

    /// How fast the orb breathes. Real work moves faster than idle.
    var pulseSpeed: Double {
        switch self {
        case .offline, .idle: return 0.6
        case .listening: return 2.2
        case .thinking: return 3.4
        case .speaking: return 2.0
        case .tool: return 2.6
        case .error: return 0.2
        }
    }
}

public struct AIOrbView: View {
    public let phase: OrbPhase
    public var size: CGFloat = 168

    @State private var t: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(phase: OrbPhase, size: CGFloat = 168) {
        self.phase = phase
        self.size = size
    }

    public var body: some View {
        ZStack {
            // Soft outer glow.
            Circle()
                .fill(
                    RadialGradient(
                        colors: [phase.tint.opacity(0.55), phase.tint.opacity(0.0)],
                        center: .center,
                        startRadius: size * 0.28,
                        endRadius: size * 0.62
                    )
                )
                .frame(width: size, height: size)

            // The core, breathing at the phase's real speed.
            Circle()
                .fill(
                    RadialGradient(
                        colors: [phase.tint, phase.tint.opacity(0.35)],
                        center: .center,
                        startRadius: 0,
                        endRadius: size * 0.34
                    )
                )
                .frame(width: size * (reduceMotion ? 0.62 : 0.62 + 0.03 * sin(t)), height: size * (reduceMotion ? 0.62 : 0.62 + 0.03 * sin(t)))
                .shadow(color: phase.tint.opacity(0.6), radius: 18)

            // A ring while work is happening.
            if phase == .thinking || phase == .listening || phase == .tool {
                Circle()
                    .stroke(phase.tint.opacity(0.8), lineWidth: 2)
                    .frame(width: size * 0.82, height: size * 0.82)
                    .scaleEffect(reduceMotion ? 1 : 1.08)
                    .opacity(reduceMotion ? 1 : 0.35)
            }

            VStack(spacing: 2) {
                Text(phase.label)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
        .animation(.easeInOut(duration: 0.25), value: phase)
        .onAppear { startAnimating() }
        .onChange(of: phase) { _, _ in startAnimating() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("AirCard AI orb")
        .accessibilityValue(phase.label)
    }

    private func startAnimating() {
        guard !reduceMotion else { return }
        t = 0
        withAnimation(.linear(duration: Double.max(0.1, 2.0 / phase.pulseSpeed)).repeatForever(autoreverses: true)) {
            t = .pi * 2
        }
    }
}

/// A horizontal capsule mirroring the Dynamic Island layout, for devices that
/// have no hardware cutout. This is an in-app view, not the system island.
public struct AIPillView: View {
    public let phase: OrbPhase
    public var text: String = ""

    public init(phase: OrbPhase, text: String = "") {
        self.phase = phase
        self.text = text
    }

    public var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(phase.tint)
                .frame(width: 10, height: 10)
                .shadow(color: phase.tint, radius: 6)
            Text(text.isEmpty ? phase.label : text)
                .font(.footnote.weight(.medium))
                .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(phase.tint.opacity(0.35), lineWidth: 1))
        .animation(.easeInOut(duration: 0.2), value: phase)
    }
}