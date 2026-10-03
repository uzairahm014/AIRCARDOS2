// AirCard AI — Live Activity control.
//
// App target only. The widget extension cannot use these: they touch OrbPhase
// and AIRuntimeError, which live in the app and pull in far more than an
// extension is allowed to compile.

import ActivityKit
import Foundation
import Observation

/// The single place that starts, updates and stops the Live Activity, so the
/// Lock Screen never drifts out of sync with the running engine.
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
            await updateRunning()
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
            let state = AILiveActivityAttributes.ContentState(
                phase: currentPhase.rawValue, detail: currentDetail)
            _ = try Activity.request(
                attributes: AILiveActivityAttributes(),
                content: .init(state: state, staleDate: nil),
                pushType: nil
            )
            isRunning = true
            lastError = nil
        } catch {
            lastError = error.localizedDescription
            isRunning = false
        }
    }

    public func stop() async {
        for activity in Activity<AILiveActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        isRunning = false
        isEnabled = false
    }

    /// Local update rather than a push token: push updates need a server this
    /// app does not have, and one session does not need one.
    private func updateRunning() async {
        let state = AILiveActivityAttributes.ContentState(
            phase: currentPhase.rawValue, detail: currentDetail)
        for activity in Activity<AILiveActivityAttributes>.activities {
            await activity.update(.init(state: state, staleDate: nil))
        }
    }

    private func sync() async {
        if isEnabled { await start() } else { await stopSilently() }
    }

    private func stopSilently() async {
        for activity in Activity<AILiveActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        isRunning = false
    }
}
