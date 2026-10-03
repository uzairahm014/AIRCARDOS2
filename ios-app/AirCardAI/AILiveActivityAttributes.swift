// AirCard AI — Live Activity attributes.
//
// This file is compiled into BOTH the app and the Live Activity extension, so
// it must not reference anything from the app: no OrbPhase, no engine types.
// The phase travels as a String precisely so the two targets can share it.

import ActivityKit
import Foundation

@available(iOS 16.1, *)
public struct AILiveActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        /// `OrbPhase` raw value, carried as a String so the widget extension
        /// does not need to compile the app's orb view.
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
