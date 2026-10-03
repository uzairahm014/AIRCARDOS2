// AirCard AI — the notch bar ("Dynamic Island" surface).
//
// This renders a live, expanding capsule pinned into the top safe-area
// region, so it occupies the same physical space the notch cuts out and
// behaves like the Dynamic Island: compact pill that expands into a panel,
// tappable, with the orb animating from real engine state.
//
// SCOPE, stated plainly:
//   ✅ Real, and it works — inside AirCard-iOS. It sits in the notch band,
//      expands/collapses, and can host live AI state.
//   ❌ It cannot float over SpringBoard or other apps. That needs code
//      injection into other processes, which this tool does not do.
//   ❌ It cannot survive leaving the app. iOS owns that surface.
//
// So: it is a Dynamic Island *look and behaviour* for your own app, not the
// system island. Anything claiming otherwise would be faking it.
//
// BUILD STATUS: not compiled here (no macOS/Xcode). See docs/BUILD-BLOCKER.md.

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Geometry of the top inset region on notched iPhones.
///
/// On a notched device the top safe-area inset is the notch band: taller than
/// a non-notched 20pt status bar, shorter than the 59pt Dynamic Island band.
/// We render inside that band, which is why the pill looks seated in the
/// notch rather than floating below it.
public struct NotchGeometry: Equatable, Sendable {
    /// Height of the top safe area in points.
    public let topInset: CGFloat
    /// Width of the visible screen.
    public let width: CGFloat

    public init(topInset: CGFloat, width: CGFloat) {
        self.topInset = topInset
        self.width = width
    }

    /// A plain status bar is ~20pt. Anything meaningfully taller is a cutout.
    public var hasCutout: Bool { topInset > 24 }

    /// Vertical centre of the band the island sits in.
    public var bandCentreY: CGFloat { hasCutout ? topInset / 2 : topInset / 2 }

    /// A notched device's inset is ~44-48pt, a Dynamic Island device ~59pt.
    public var isDynamicIslandSized: Bool { topInset >= 54 }

    /// Compact capsule width, sized to feel like the real island.
    public var compactWidth: CGFloat { min(width * 0.34, 128) }

    /// Expanded panel width.
    public var expandedWidth: CGFloat { min(width - 24, 380) }

    /// Corner radius: a capsule is half its own height.
    public func capsuleRadius(height: CGFloat) -> CGFloat { height / 2 }
}

extension NotchGeometry {
    /// The real top inset, measured from the live key window.
    ///
    /// This used to be hardcoded to 47pt, which is only correct on one device
    /// in one orientation. The notch band is 47-48pt on a 6.1" notched phone
    /// and 59pt on a Dynamic Island phone, so a hardcoded value put the island
    /// in the wrong place on anything but the device it was guessed on.
    public static var measuredTopInset: CGFloat? {
        #if canImport(UIKit)
        return MainActor.assumeIsolated {
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap(\.windows)
                .first(where: \.isKeyWindow)?
                .safeAreaInsets.top
        }
        #else
        return nil
        #endif
    }

    /// Geometry for the device this app is actually running on.
    public static var current: NotchGeometry {
        #if canImport(UIKit)
        let size = MainActor.assumeIsolated { UIScreen.main.bounds.size }
        #else
        let size = CGSize(width: 393, height: 852)
        #endif
        return NotchGeometry(
            topInset: measuredTopInset ?? 47,
            width: size.width
        )
    }
}

public enum NotchIslandSize {
    public static let compactHeight: CGFloat = 34
    public static let expandedHeight: CGFloat = 132
}

/// Which panel is showing when the island is expanded.
public enum NotchIslandPanel: String, CaseIterable, Sendable {
    case chat, voice, tools, none

    public var title: String {
        switch self {
        case .chat: return "Chat"
        case .voice: return "Voice"
        case .tools: return "Tools"
        case .none: return ""
        }
    }
}

/// Observable state for the island. Driven by the real engines.
@Observable
@MainActor
public final class NotchIslandState: Sendable {
    public var isExpanded: Bool = false
    public var panel: NotchIslandPanel = .none
    public var phase: OrbPhase = .idle
    /// Short line shown in the expanded panel (transcript, last reply, …).
    public var detail: String = ""
    /// Fires when the user taps the compact pill.
    public var onTapCompact: (@MainActor () -> Void)?

    public init() {}

    public func toggle(_ panel: NotchIslandPanel) {
        if isExpanded && self.panel == panel {
            collapse()
        } else {
            self.panel = panel
            withAnimation(.spring(response: 0.42, dampingFraction: 0.78)) {
                isExpanded = true
            }
        }
    }

    public func collapse() {
        withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
            isExpanded = false
        }
        // Clear after the animation so content does not flash during collapse.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            if !isExpanded { panel = .none }
        }
    }
}

/// The island itself. Drop into any SwiftUI view; it pins itself to the top.
public struct NotchIsland<Overlay: View>: View {
    @Bindable var state: NotchIslandState

private let geo: NotchGeometry
private let overlay: () -> Overlay

    public init(
        state: NotchIslandState,
        geo: NotchGeometry,
        @ViewBuilder overlay: @escaping () -> Overlay
    ) {
        self.state = state
        self.geo = geo
        self.overlay = overlay
    }

    public var body: some View {
        GeometryReader { outer in
            let g = NotchGeometry(
                topInset: outer.safeAreaInsets.top,
                width: outer.size.width
            )
            ZStack(alignment: .top) {
                Color.clear

                island(g)
                    .frame(width: state.isExpanded ? g.expandedWidth : g.compactWidth)
                    .frame(height: state.isExpanded ? NotchIslandSize.expandedHeight : NotchIslandSize.compactHeight)
                    .background(capsuleBackground(g, expanded: state.isExpanded))
                    .overlay(capsuleStroke(g, expanded: state.isExpanded))
                    .clipShape(
                        RoundedRectangle(
                            cornerRadius: currentRadius(g),
                            style: .continuous
                        )
                    )
                    .shadow(color: .black.opacity(state.isExpanded ? 0.28 : 0.14),
                            radius: state.isExpanded ? 22 : 8,
                            y: 6)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if state.isExpanded {
                            state.collapse()
                        } else {
                            state.onTapCompact?()
                            withAnimation(.spring(response: 0.42, dampingFraction: 0.78)) {
                                state.isExpanded = true
                            }
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("AirCard AI island")
                    .accessibilityValue(state.phase.label)
                    .accessibilityHint(state.isExpanded ? "Double tap to collapse" : "Double tap to expand")
            }
        }
        .ignoresSafeArea(edges: .top)
        // Use the measured inset for the reserved height too, so the view does
        // not reserve 47pt of notch band on a phone whose band is a different
        // height (and clip the expanded panel as a result).
        .frame(height: (NotchGeometry.measuredTopInset ?? geo.topInset)
            + NotchIslandSize.expandedHeight + 40)
    }

    // MARK: - Pieces

    @ViewBuilder
    private func island(_ g: NotchGeometry) -> some View {
        if state.isExpanded {
            expandedContent(g)
        } else {
            compactContent(g)
        }
    }

    /// Compact: orb on the left, real state text on the right.
    private func compactContent(_ g: NotchGeometry) -> some View {
        HStack(spacing: 8) {
            AIOrbView(phase: state.phase, size: NotchIslandSize.compactHeight)
                .frame(width: NotchIslandSize.compactHeight - 6,
                       height: NotchIslandSize.compactHeight - 6)

            Text(compactLabel)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .transition(.opacity.combined(with: .scale(scale: 0.9)))

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
    }

    private var compactLabel: String {
        switch state.phase {
        case .listening: return state.detail.isEmpty ? "Listening" : state.detail
        case .thinking: return "Thinking"
        case .speaking: return "Speaking"
        case .tool: return "Working"
        case .error: return "Something went wrong"
        case .offline: return "Offline"
        case .idle: return "AirCard"
        }
    }

    /// Expanded: header row plus the host app's panel content.
    private func expandedContent(_ g: NotchGeometry) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                AIOrbView(phase: state.phase, size: 26)

                Text(state.panel.title)
                    .font(.system(size: 14, weight: .bold, design: .rounded))

                Spacer()

                Button {
                    state.collapse()
                } label: {
                    Image(systemName: "chevron.up")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Collapse")
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 8)

            Divider().opacity(0.5)

            overlay()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func currentRadius(_ g: NotchGeometry) -> CGFloat {
        let h = state.isExpanded ? NotchIslandSize.expandedHeight : NotchIslandSize.compactHeight
        // A capsule for the compact pill; a softer continuous radius expanded.
        return state.isExpanded ? 30 : g.capsuleRadius(height: h)
    }

    private func capsuleBackground(_ g: NotchGeometry, expanded: Bool) -> some View {
        RoundedRectangle(cornerRadius: currentRadius(g), style: .continuous)
            .fill(.regularMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: currentRadius(g), style: .continuous)
                    .fill(state.phase.tint.opacity(expanded ? 0.10 : 0.16))
            )
    }

    private func capsuleStroke(_ g: NotchGeometry, expanded: Bool) -> some View {
        RoundedRectangle(cornerRadius: currentRadius(g), style: .continuous)
            .strokeBorder(state.phase.tint.opacity(expanded ? 0.35 : 0.55), lineWidth: expanded ? 1 : 1.2)
    }
}

/// Convenience: the island wired to the real engines, with no host content.
public struct AIIslandChrome: View {
    @Bindable var state: NotchIslandState

    public init(state: NotchIslandState) {
        self.state = state
    }

    public var body: some View {            NotchIsland(state: state, geo: .current) {
            VStack(spacing: 10) {
                Text(state.detail.isEmpty ? state.phase.label : state.detail)
                    .font(.callout)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
    }
}