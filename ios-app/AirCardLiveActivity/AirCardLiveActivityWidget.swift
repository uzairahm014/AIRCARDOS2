// AirCard AI — the Live Activity UI.
//
// This is the part that makes the AI visible on the Lock Screen and in the
// Notification Center, which is the furthest any app can reach on iOS.
//
// On a device WITH a hardware Dynamic Island (iPhone 14 Pro and newer) the
// `DynamicIsland` regions below are used and it genuinely looks like the real
// thing. On this iPhone 13 Pro Max there is no cutout, so iOS renders only the
// Lock Screen and Notification Center presentations. Both are real; the island
// presentation simply has nowhere to draw.
//
// BUILD STATUS: compiled and built green by CI (see .github/workflows/build-ios.yml).
// Not yet verified running on hardware.

import ActivityKit
import SwiftUI
import WidgetKit

@available(iOS 16.1, *)
struct AirCardLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AILiveActivityAttributes.self) { context in
            LockScreenView(state: context.state)
                .activityBackgroundTint(Color.black.opacity(0.55))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    OrbDot(phase: context.state.phase)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.phase.replacingOccurrences(of: "_", with: " ").capitalized)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(phaseColor(context.state.phase))
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.state.detail.isEmpty ? "AirCard AI" : context.state.detail)
                        .font(.footnote)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } compactLeading: {
                OrbDot(phase: context.state.phase)
            } compactTrailing: {
                Text(compactGlyph(context.state.phase))
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(phaseColor(context.state.phase))
            } minimal: {
                OrbDot(phase: context.state.phase)
            }
            .widgetURL(URL(string: "aircard://ai"))
            .keylineTint(phaseColor(context.state.phase))
        }
    }
}

// MARK: - Lock Screen

@available(iOS 16.1, *)
private struct LockScreenView: View {
    let state: AILiveActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 12) {
            OrbDot(phase: state.phase)

            VStack(alignment: .leading, spacing: 2) {
                Text(state.phase.replacingOccurrences(of: "_", with: " ").capitalized)
                    .font(.headline)
                    .foregroundStyle(.white)
                Text(state.detail.isEmpty ? "AirCard AI" : state.detail)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.75))
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

// MARK: - Bits

/// The tiny animated dot used in every compact region.
private struct OrbDot: View {
    let phase: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var on = false

    var body: some View {
        Circle()
            .fill(phaseColor(phase))
            .frame(width: 12, height: 12)
            .scaleEffect(reduceMotion ? 1 : (on ? 1.25 : 0.85))
            .shadow(color: phaseColor(phase), radius: 5)
            .onAppear {
                guard !reduceMotion, phase != "idle", phase != "offline" else { return }
                withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
                    on = true
                }
            }
            .accessibilityLabel("AirCard AI")
    }
}

/// A single glyph so the compact region stays readable at that size.
private func compactGlyph(_ phase: String) -> String {
    switch phase {
    case "listening": return "mic"
    case "thinking", "tool": return "…"
    case "speaking": return "wave"
    case "error": return "!"
    case "offline": return "–"
    default: return ""
    }
}

/// Keep these in step with `OrbPhase` in AIOrbView.swift.
func phaseColor(_ phase: String) -> Color {
    switch phase {
    case "listening": return .green
    case "thinking": return .orange
    case "speaking": return .purple
    case "tool": return .blue
    case "error": return .red
    case "offline": return .gray
    default: return .cyan
    }
}

@available(iOS 16.1, *)
@main
struct AirCardLiveActivityBundle: WidgetBundle {
    var body: some Widget {
        AirCardLiveActivityWidget()
    }
}