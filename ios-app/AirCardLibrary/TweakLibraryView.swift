//
//  TweakLibraryView.swift
//  AirCard-iOS
//
//  The Tweak Library screen. Same contract as the desktop engine: every
//  definition is listed, every state is explained, and an APPLY button only
//  appears when a compiled implementation exists behind the entry.
//
//  COMPILES-UNVERIFIED: authored on Windows, never run through swiftc.
//  See docs/BUILD-BLOCKER.md.
//

import SwiftUI

@available(iOS 17.0, *)
public struct TweakLibraryView: View {
    @StateObject private var model: TweakLibraryModel

    public init() {
        _model = StateObject(wrappedValue: TweakLibraryModel())
    }

    public var body: some View {
        NavigationStack {
            List {
                summarySection
                filterSection
                ForEach(model.visible) { entry in
                    NavigationLink {
                        TweakDetailView(entry: entry, model: model)
                    } label: {
                        TweakRow(entry: entry)
                    }
                }
            }
            .navigationTitle("Tweak Library")
            .searchable(
                text: $model.filter.query,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "dynamic island, anime, battery…"
            )
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("Category", selection: $model.filter.category) {
                            Text("All categories").tag(String?.none)
                            ForEach(model.library.categories, id: \.0) { cat, n in
                                Text("\(cat) (\(n))").tag(String?.some(cat))
                            }
                        }
                        Picker("State", selection: $model.filter.state) {
                            Text("Any state").tag(TweakState?.none)
                            ForEach(TweakState.allCases, id: \.self) { s in
                                Text(s.label).tag(TweakState?.some(s))
                            }
                        }
                        Toggle("Implemented only", isOn: $model.filter.implementedOnly)
                    } label: {
                        Label("Filter", systemImage: "line.3.horizontal.decrease.circle")
                    }
                }
            }
        }
    }

    private var summarySection: some View {
        Section {
            HStack(spacing: 12) {
                stat("\(model.library.count)", "definitions")
                stat("\(model.library.reachableCount)", "reachable")
                stat("\(model.library.verifiedCount)", "verified")
                stat("\(model.library.implementedCount)", "can apply")
            }
            .padding(.vertical, 4)
            DisclosureGroup("What these numbers mean") {
                Text("""
                Reachable means the mechanism exists. Verified means a real run on \
                \(model.facts.productType) / iOS \(model.facts.iosVersion) \
                (build \(model.facts.build)) read the written bytes back off the device \
                and compared them. Only those with a compiled implementation get an \
                APPLY button; the rest are documentation of what was considered and \
                why it fails on this build.
                """)
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            .font(.footnote)
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.title3.monospacedDigit().bold())
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var filterSection: some View {
        if model.visible.isEmpty {
            Section {
                Text("No definitions match this filter.")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Row

struct TweakRow: View {
    let entry: LibraryEntry

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(stateColor.opacity(0.18))
                    .frame(width: 34, height: 34)
                // SF Symbols, not the JSON glyph — the JSON icon field is kept
                // for parity with the desktop library but Apple ships no glyph
                // coverage for arbitrary unicode shapes.
                Image(systemName: symbol)
                    .foregroundStyle(stateColor)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.def.name).font(.headline)
                Text(entry.def.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 4)
            StateBadge(state: entry.state, verified: entry.verifiedOnDevice)
        }
        .padding(.vertical, 2)
    }

    private var stateColor: Color {
        switch entry.state {
        case .unsupported: return .red
        case .experimental: return .orange
        case .failed: return .red
        case .installed, .enabled: return .green
        default: return .blue
        }
    }

    private var symbol: String {
        switch entry.def.backend {
        case .airLift: return "externaldrive.connected.to.line.below"
        case .nativeIOS: return "iphone"
        case .appIntent: return "wand.and.stars"
        case .liveActivity: return "bolt.badge.clock"
        case .theme: return "paintpalette"
        case .unsupported: return "nosign"
        }
    }
}

struct StateBadge: View {
    let state: TweakState
    let verified: Bool

    var body: some View {
        let text = verified ? "VERIFIED" : state.label
        Text(text)
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.18), in: Capsule())
            .foregroundStyle(color)
    }

    private var color: Color {
        switch state {
        case .unsupported: return .red
        case .experimental: return .orange
        case .failed: return .red
        case .installed, .enabled: return .green
        default: return .blue
        }
    }
}

// MARK: - Detail

struct TweakDetailView: View {
    let entry: LibraryEntry
    @ObservedObject var model: TweakLibraryModel
    @State private var confirmation: Confirmation?

    var body: some View {
        List {
            Section {
                StateBadge(state: entry.state, verified: entry.verifiedOnDevice)
                Text(entry.verdict)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Why this status")
            }

            if entry.state == .unsupported {
                Section {
                    Label(entry.def.unsupportedReason, systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                    Text("""
                    This is listed so you know it was considered. There is no button \
                    here on purpose — a toggle that cannot do anything is worse than \
                    an honest gap.
                    """)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }

            Section("Requirements") {
                row("Backend", entry.def.backend.label)
                row("Risk", entry.def.risk.rawValue.capitalized)
                row("Effect", entry.def.effect.label)
                row("Backup first", entry.def.requiresBackup ? "Yes" : "No")
                if let min = entry.def.minIOS { row("Minimum iOS", min) }
                if !entry.def.verifiedBuilds.isEmpty {
                    row("Verified builds", entry.def.verifiedBuilds.joined(separator: ", "))
                }
            }

            if !entry.def.paths.isEmpty {
                Section("Paths written") {
                    ForEach(entry.def.paths, id: \.self) { p in
                        Text(p).font(.caption.monospaced())
                    }
                }
            }

            if !entry.def.rollback.isEmpty {
                Section("Rollback") {
                    Text(entry.def.rollback).font(.footnote)
                }
            }

            if entry.hasImplementation {
                Section {
                    Button {
                        confirmation = Confirmation(
                            id: entry.def.id,
                            title: "Apply \(entry.def.name)?",
                            body: """
                            This writes \(entry.def.paths.count) file(s) to your device \
                            and reads the bytes back to verify them.

                            Effect: \(entry.def.effect.label).
                            """
                        )
                    } label: {
                        Label("Apply", systemImage: "arrow.down.doc")
                    }
                    .disabled(entry.def.effect.isDisruptive && !model.confirmDisruptive)
                } header: {
                    Text("Apply")
                } footer: {
                    if entry.def.effect.isDisruptive {
                        Text("""
                        This needs a \(entry.def.effect.label). AirCard will not restart \
                        your phone for you — apply the change, then reboot when you are ready.
                        """)
                    }
                }
            }

            Section("Tags") {
                Text(entry.def.tags.map { "#\($0)" }.joined(separator: "  "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(entry.def.name)
        .confirmationDialog(
            confirmation?.title ?? "",
            isPresented: Binding(
                get: { confirmation != nil },
                set: { if !$0 { confirmation = nil } }
            ),
            titleVisibility: .visible,
            presenting: confirmation
        ) { c in
            Button("Apply", role: .destructive) {
                model.apply(id: c.id)
                confirmation = nil
            }
            Button("Cancel", role: .cancel) { confirmation = nil }
        } message: { c in
            Text(c.body)
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).multilineTextAlignment(.trailing)
        }
        .font(.footnote)
    }
}

struct Confirmation: Identifiable {
    let id: String
    let title: String
    let body: String
}

// MARK: - View model

@available(iOS 17.0, *)
public final class TweakLibraryModel: @MainActor ObservableObject {
    @Published public var library: TweakLibrary
    @Published public var filter = LibraryFilter()
    /// Off by default: AirCard never reboots a phone without explicit consent.
    @Published public var confirmDisruptive = false

    public let facts: DeviceFacts

    public init(facts: DeviceFacts = .current(), verifiedBuilds: [String] = []) {
        self.facts = facts
        self.library = TweakLibrary(
            facts: facts,
            verifiedBuilds: verifiedBuilds
        )
    }

    public var visible: [LibraryEntry] { library.search(filter) }

    /// Apply an entry through the AirLift bridge.
    ///
    /// This only ever runs for entries that name a compiled implementation. The
    /// result — including a failed verification — is written back into the
    /// library so the list stops claiming the tweak is merely available.
    public func apply(id: String) {
        guard let entry = library.entry(id), entry.hasImplementation else {
            NSLog("AirCardLibrary: refused apply for %@ (no implementation)", id)
            return
        }
        let result = AirCardSystemBridge.shared.apply(entry.def.implID)
        if !result.succeeded {
            NSLog("AirCardLibrary: apply failed for %@: %@", id, result.detail)
        }
        // Record what actually happened: a write that was issued but not
        // read back is not the same as a verified apply.
        library.recordApply(id: id, verified: result.verified)
    }
}
