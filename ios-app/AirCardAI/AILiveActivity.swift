// AirCard AI — Live Activity for the AI surface.
//
// IMPORTANT AND DELIBERATE: Live Activities render into the hardware Dynamic
// Island cutout. This device (iPhone14,3, iPhone 13 Pro Max) has a sensor
// NOTCH, not a cutout, so on this phone the activity appears on the Lock
// Screen and in the Notification Center only. There is no island to expand.
//
// This code is real ActivityKit and will compile against iOS 16.1+, but it
// cannot be verified on this machine because no signed app can be built here.
//
// BUILD STATUS: not compiled here (no macOS/Xcode). See docs/BUILD-BLOCKER.md.

import ActivityKit
import Foundation
import Observation

#if canImport(UIKit)
import UIKit
#endif

@available(iOS 16.1, *)
public struct AILiveActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        /// Mirrors `OrbPhase` so the widget renders the same state as the app.
        public var phase: String
        public var detail: String
        public var updatedAt: Date

        public init(phase: String, detail: String) {
            self.phase = phase
            self.detail = detail
            self.updatedAt = Date()
        }
    }

    public var title: String
    public init(title: String = "AirCard AI") { self.title = title }
}

@available(iOS 16.1, *)
public enum AILiveActivityController {
    /// Start an activity, reporting honestly if the OS refuses.
    public static func start(phase: OrbPhase, detail: String) async throws {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            throw AIRuntimeError.permissionDenied
        }
        let attributes = AILiveActivityAttributes()
        let state = AILiveActivityAttributes.ContentState(phase: phase.rawValue, detail: detail)
        // On a notched device this shows on the Lock Screen only. There is no
        // Dynamic Island presentation and this code does not pretend otherwise.
        _ = try Activity.request(
            attributes: attributes,
            content: .init(state: state, staleDate: nil),
            pushType: nil
        )
    }

    public static func end() async {
        for activity in Activity<AILiveActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    /// Push new state into the running activity, if there is one.
    ///
    /// Uses `Activity.update` rather than a push token: push updates need a
    /// server this app does not have, and a local update is enough to track
    /// one session.
    public static func update(phase: OrbPhase, detail: String) async {
        let state = AILiveActivityAttributes.ContentState(phase: phase.rawValue, detail: detail)
        for activity in Activity<AILiveActivityAttributes>.activities {
            await activity.update(.init(state: state, staleDate: nil))
        }
    }
}

/// Mirrors engine state into the Live Activity for as long as it is enabled.
///
/// One place decides when the activity starts, updates and stops, so the
/// Lock Screen never drifts out of sync with the app.
@MainActor
@Observable
public final class AILiveActivityCoordinator {
    public private(set) var isRunning = false
    public private(set) var lastError: String?
    public var isEnabled: Bool = false { didSet { Task { await sync() } } }

    private var currentPhase: OrbPhase = .idle
    private var currentDetail: String = ""

    public init() {}

    /// Call whenever the phase or detail changes.
    public func update(phase: OrbPhase, detail: String) async {
        currentPhase = phase
        currentDetail = detail
        guard isEnabled else { return }
        if isRunning {
            await AILiveActivityController.update(phase: phase, detail: detail)
        } else {
            await start()
        }
    }

    public func start() async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            lastError = "Live Activities are turned off for AirCard-iOS."
            isEnabled = false
            return
        }
        do {
            try await AILiveActivityController.start(phase: currentPhase, detail: currentDetail)
            isRunning = true
            lastError = nil
        } catch {
            lastError = error.localizedDescription
            isRunning = false
        }
    }

    public func stop() async {
        await AILiveActivityController.end()
        isRunning = false
        isEnabled = false
    }

    private func sync() async {
        if isEnabled {
            await start()
        } else {
            await AILiveActivityController.end()
            isRunning = false
        }
    }
}