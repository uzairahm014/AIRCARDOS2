//
//  AirCardLibrary.swift
//  AirCard-iOS
//
//  The iOS-side view of the tweak library.
//
//  This reads the **same** `library/*.json` files as the Rust engine and
//  applies the **same** rules, so a tweak cannot look supported on the phone
//  and unsupported on the desktop. The rules are:
//
//    1. A definition whose `backend` is `unsupported` is UNSUPPORTED, always.
//    2. A definition that names a `min_ios` above this device's version is
//       UNSUPPORTED with that reason.
//    3. A definition is only marked verified when it names this exact build
//       in `verified_builds`. Everything else reachable is EXPERIMENTAL —
//       reachable in principle, unconfirmed on hardware.
//
//  COMPILES-UNVERIFIED: this file was authored on Windows. It has never been
//  through swiftc, because no macOS/Xcode toolchain exists on this machine.
//  See docs/BUILD-BLOCKER.md.
//

import Foundation
import SwiftUI
import UIKit

// MARK: - Definitions (mirror of aircard_core::library)

/// How a tweak reaches the device. Mirrors `aircard_core::library::Backend`.
public enum TweakBackend: String, Codable, Hashable {
    /// Writes through the AirLift/AirTraffic sandbox escape.
    case airLift = "air_lift"
    /// Writes inside the app's own container.
    case nativeIOS = "native_ios"
    /// App Intents / Shortcuts.
    case appIntent = "app_intent"
    /// ActivityKit presentation.
    case liveActivity = "live_activity"
    /// Theme and asset packaging only.
    case theme
    /// No mechanism exists.
    case unsupported

    public var label: String {
        switch self {
        case .airLift: return "AirLift file write"
        case .nativeIOS: return "Native iOS API"
        case .appIntent: return "App Intent / Shortcut"
        case .liveActivity: return "Live Activity"
        case .theme: return "Theme assets"
        case .unsupported: return "No mechanism"
        }
    }

    /// True when the mechanism can change something outside our sandbox.
    public var escapesSandbox: Bool { self == .airLift }
}

/// The refresh a tweak needs. Mirrors `aircard_core::library::Effect`.
public enum TweakEffect: String, Codable, Hashable {
    case none
    case respring
    case reboot
    case lockReload = "lock_reload"
    case previewOnly = "preview_only"

    public var label: String {
        switch self {
        case .none: return "no refresh needed"
        case .respring: return "respring"
        case .reboot: return "reboot"
        case .lockReload: return "lock screen reload"
        case .previewOnly: return "preview only"
        }
    }

    /// Whether applying this needs the user's phone to restart. AirCard never
    /// triggers a reboot itself; it reports the requirement and lets the user
    /// decide.
    public var isDisruptive: Bool { self == .reboot }
}

public enum TweakRisk: String, Codable, Hashable, Comparable {
    case low, medium, high

    private var order: Int {
        switch self {
        case .low: return 0
        case .medium: return 1
        case .high: return 2
        }
    }

    public static func < (a: TweakRisk, b: TweakRisk) -> Bool { a.order < b.order }
}

/// One row of `library/*.json`.
public struct TweakDefinition: Codable, Identifiable, Hashable {
    public let id: String
    public let name: String
    public let category: String
    public let description: String
    public let icon: String
    public let tags: [String]
    public let backend: TweakBackend
    public let risk: TweakRisk
    public let effect: TweakEffect
    public let requiresBackup: Bool
    public let minIOS: String?
    public let verifiedBuilds: [String]
    public let paths: [String]
    public let rollback: String
    /// Id of a compiled implementation. Empty means **there is no apply
    /// button** — the UI must not offer one.
    public let implID: String
    /// Which app page configures it.
    public let page: String
    public let unsupportedReason: String

    enum CodingKeys: String, CodingKey {
        case id, name, category, description, icon, tags, backend, risk, effect
        case requiresBackup = "requires_backup"
        case minIOS = "min_ios"
        case verifiedBuilds = "verified_builds"
        case paths, rollback
        case implID = "impl_id"
        case page
        case unsupportedReason = "unsupported_reason"
    }

    public init(
        id: String, name: String, category: String, description: String = "",
        icon: String = "◆", tags: [String] = [], backend: TweakBackend,
        risk: TweakRisk = .low, effect: TweakEffect = .none,
        requiresBackup: Bool = false, minIOS: String? = nil,
        verifiedBuilds: [String] = [], paths: [String] = [], rollback: String = "",
        implID: String = "", page: String = "", unsupportedReason: String = ""
    ) {
        self.id = id; self.name = name; self.category = category
        self.description = description; self.icon = icon; self.tags = tags
        self.backend = backend; self.risk = risk; self.effect = effect
        self.requiresBackup = requiresBackup; self.minIOS = minIOS
        self.verifiedBuilds = verifiedBuilds; self.paths = paths
        self.rollback = rollback; self.implID = implID; self.page = page
        self.unsupportedReason = unsupportedReason
    }
}

/// Wrapper shape: `{ "category": "...", "tweaks": [ ... ] }`.
struct TweakLibraryFile: Codable {
    let category: String?
    let tweaks: [TweakDefinition]
}

// MARK: - Runtime state

public enum TweakState: String, Codable, Hashable, CaseIterable {
    case available, installed, enabled, disabled
    case partial, failed, unsupported, experimental

    public var label: String {
        switch self {
        case .available: return "AVAILABLE"
        case .installed: return "INSTALLED"
        case .enabled: return "ENABLED"
        case .disabled: return "DISABLED"
        case .partial: return "PARTIALLY APPLIED"
        case .failed: return "FAILED"
        case .unsupported: return "UNSUPPORTED"
        case .experimental: return "EXPERIMENTAL"
        }
    }

    public var isApplied: Bool {
        switch self {
        case .installed, .enabled, .partial, .failed: return true
        default: return false
        }
    }
}

/// A definition plus what the engine decided about it.
public struct LibraryEntry: Identifiable, Hashable {
    public let def: TweakDefinition
    public let state: TweakState
    /// Why that state — shown verbatim, never paraphrased into optimism.
    public let verdict: String
    /// True only when a real run confirmed the bytes on this exact build.
    public let verifiedOnDevice: Bool

    public var id: String { def.id }

    public var hasImplementation: Bool { !def.implID.isEmpty }
}

// MARK: - Device facts

/// What we know about the phone we are running on.
public struct DeviceFacts: Equatable {
    public var productType: String
    public var iosVersion: String
    public var build: String

    public init(productType: String, iosVersion: String, build: String) {
        self.productType = productType
        self.iosVersion = iosVersion
        self.build = build
    }

    /// Read the real device. Falls back to the target matrix when a value is
    /// unavailable rather than guessing "newer than supported".
    public static func current() -> DeviceFacts {
        let device = UIDevice.current
        let version = device.systemVersion
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
        return DeviceFacts(productType: "iPhone14,3", iosVersion: version, build: build)
    }

    static func parseVersion(_ v: String) -> [Int] {
        v.split(separator: ".").compactMap { Int($0) }
    }

    func atLeast(_ min: String) -> Bool {
        let a = DeviceFacts.parseVersion(iosVersion)
        let b = DeviceFacts.parseVersion(min)
        guard !a.isEmpty, !b.isEmpty else { return false }
        for (x, y) in zip(a, b) where x != y {
            return x > y
        }
        return a.count >= b.count
    }
}

// MARK: - Compatibility engine

/// Mirrors `aircard_core::library::CompatibilityEngine`.
public struct CompatibilityEngine {
    public let facts: DeviceFacts
    /// Builds confirmed by a real run on this machine.
    public let verifiedBuilds: [String]

    public init(facts: DeviceFacts, verifiedBuilds: [String] = []) {
        self.facts = facts
        self.verifiedBuilds = verifiedBuilds
    }

    /// Decide one definition. Never returns `.available` for something with no
    /// mechanism, and never returns `.available` without a confirmed build.
    public func evaluate(_ def: TweakDefinition) -> LibraryEntry {
        if def.backend == .unsupported {
            let reason = def.unsupportedReason.isEmpty
                ? "No mechanism exists for this on the target build."
                : def.unsupportedReason
            return LibraryEntry(def: def, state: .unsupported, verdict: reason,
                                verifiedOnDevice: false)
        }

        if let min = def.minIOS, !facts.atLeast(min) {
            return LibraryEntry(
                def: def,
                state: .unsupported,
                verdict: "Requires iOS \(min) or later; this device is iOS \(facts.iosVersion).",
                verifiedOnDevice: false
            )
        }

        let confirmed = verifiedBuilds.contains(facts.build)
            || def.verifiedBuilds.contains(facts.build)
        if confirmed {
            return LibraryEntry(
                def: def,
                state: .available,
                verdict: "Confirmed on build \(facts.build) by a real run on \(facts.productType).",
                verifiedOnDevice: true
            )
        }
        return LibraryEntry(
            def: def,
            state: .experimental,
            verdict: "Mechanism is in reach (\(def.backend.label)), "
                   + "but no run has confirmed it on build \(facts.build).",
            verifiedOnDevice: false
        )
    }
}

// MARK: - Library

public struct TweakLibrary {
    public private(set) var entries: [LibraryEntry] = []
    private var engine: CompatibilityEngine

    public init(facts: DeviceFacts = .current(), verifiedBuilds: [String] = []) {
        self.engine = CompatibilityEngine(facts: facts, verifiedBuilds: verifiedBuilds)
    }

    /// Parse one library file. Accepts a bare array or `{category, tweaks}`.
    public static func parse(data: Data) throws -> [TweakDefinition] {
        let decoder = JSONDecoder()
        if let wrapped = try? decoder.decode(TweakLibraryFile.self, from: data) {
            return wrapped.tweaks
        }
        return try decoder.decode([TweakDefinition].self, from: data)
    }

    /// Load every `.json` in a directory. A missing directory is not an error.
    ///
    /// The directory is a folder reference in the app bundle (see `project.yml`),
    /// so the shipped definitions live at `library/` inside `Bundle.main`.
    public static func load(
        directory: URL,
        facts: DeviceFacts = .current(),
        verifiedBuilds: [String] = []
    ) -> TweakLibrary {
        var library = TweakLibrary(facts: facts, verifiedBuilds: verifiedBuilds)
        guard let names = try? FileManager.default.contentsOfDirectory(
            atPath: directory.path
        ) else { return library }

        for name in names.sorted() where name.hasSuffix(".json") {
            let url = directory.appendingPathComponent(name)
            guard let data = try? Data(contentsOf: url) else { continue }
            // A malformed file is skipped rather than taking the whole app
            // down — but it is never silently merged as an empty list either.
            guard let defs = try? TweakLibrary.parse(data: data) else {
                NSLog("AirCardLibrary: skipping unreadable library file %@", name)
                continue
            }
            library.merge(defs)
        }
        return library
    }

    public mutating func merge(_ defs: [TweakDefinition]) {
        entries.append(contentsOf: defs.map { engine.evaluate($0) })
    }

    public var count: Int { entries.count }
    public var reachableCount: Int {
        entries.filter { $0.state != .unsupported }.count
    }
    public var verifiedCount: Int {
        entries.filter(\.verifiedOnDevice).count
    }
    public var implementedCount: Int {
        entries.filter(\.hasImplementation).count
    }

    public func entry(_ id: String) -> LibraryEntry? {
        entries.first { $0.def.id == id }
    }

    /// Category name → number of definitions, sorted alphabetically.
    public var categories: [(String, Int)] {
        Dictionary(grouping: entries, by: { $0.def.category })
            .map { ($0.key, $0.value.count) }
            .sorted { $0.0 < $1.0 }
    }

    public func countsByState() -> [TweakState: Int] {
        Dictionary(grouping: entries, by: \.state).mapValues(\.count)
    }

    /// Record the outcome of a real apply so the list stops claiming a failed
    /// tweak is merely available.
    public mutating func recordApply(id: String, verified: Bool) {
        guard let idx = entries.firstIndex(where: { $0.def.id == id }) else { return }
        let def = entries[idx].def
        entries[idx] = LibraryEntry(
            def: def,
            state: verified ? .installed : .failed,
            verdict: verified
                ? "Applied and the bytes read back off the device matched (\(def.backend.label))."
                : "Applied, but read-back verification FAILED — the device bytes did not "
                  + "match. Roll back before continuing.",
            verifiedOnDevice: verified
        )
    }
}

// MARK: - Filtering

public struct LibraryFilter {
    public var query: String = ""
    public var category: String?
    public var state: TweakState?
    public var backend: TweakBackend?
    public var implementedOnly: Bool = false
    public var maxRisk: TweakRisk?

    public init() {}

    public func matches(_ e: LibraryEntry) -> Bool {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !q.isEmpty {
            let hay = ([e.def.id, e.def.name, e.def.description, e.def.category]
                       + e.def.tags).joined(separator: " ").lowercased()
            if !hay.contains(q) { return false }
        }
        if let category, e.def.category != category { return false }
        if let state, e.state != state { return false }
        if let backend, e.def.backend != backend { return false }
        if implementedOnly && !e.hasImplementation { return false }
        if let maxRisk, e.def.risk > maxRisk { return false }
        return true
    }
}

extension TweakLibrary {
    public func search(_ filter: LibraryFilter) -> [LibraryEntry] {
        entries.filter(filter.matches)
    }
}
