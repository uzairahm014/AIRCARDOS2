// AirCard AI — tool router.
//
// Tools are real, local, side-effecting operations. Each one reports exactly
// what it did. A tool that cannot run says why instead of returning a fake
// result, and nothing here silently touches the network.
//
// BUILD STATUS: not compiled here (no macOS/Xcode). See docs/BUILD-BLOCKER.md.

import Foundation
import Observation
import UIKit

public struct AIToolResult: Sendable {
    public let tool: String
    public let ok: Bool
    public let summary: String
    public let detail: String?

    public init(tool: String, ok: Bool, summary: String, detail: String? = nil) {
        self.tool = tool
        self.ok = ok
        self.summary = summary
        self.detail = detail
    }
}

public protocol AITool: Sendable {
    var name: String { get }
    var description: String { get }
    /// Shown to the model so it knows when to pick this tool.
    var usageHint: String { get }
    func run(argument: String) async -> AIToolResult
}

@Observable
@MainActor
public final class AIToolRouter: Sendable {
    public private(set) var tools: [AITool] = []
    /// Every invocation this session, so the user can audit what was done.
    public private(set) var history: [(tool: String, argument: String, result: AIToolResult)] = []

    public init(register defaults: Bool = true) {
        guard defaults else { return }
        register(DeviceInfoTool())
        register(SearchTool())
        register(MathTool())
        register(DateTimeTool())
    }

    public func register(_ tool: AITool) {
        tools.removeAll { $0.name == tool.name }
        tools.append(tool)
    }

    /// Brief catalogue handed to the model so it can choose a tool.
    public var catalogue: String {
        tools.map { "- \($0.name): \($0.usageHint)" }.joined(separator: "\n")
    }

    public func find(_ name: String) -> AITool? {
        tools.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }

    @discardableResult
    public func run(tool: String, argument: String) async -> AIToolResult {
        guard let tool = find(tool) else {
            let result = AIToolResult(tool: tool, ok: false, summary: "No tool named \(tool).")
            history.append((tool, argument, result))
            return result
        }
        let result = await tool.run(argument: argument)
        history.append((tool, argument, result))
        return result
    }
}

// MARK: - Built-in tools

/// Real device facts, read from UIDevice at call time.
public struct DeviceInfoTool: AITool {
    public init() {}
    public var name: String { "device_info" }
    public var description: String { "Reports this iPhone's model, iOS version and AI capability status." }
    public var usageHint: String { "use when the user asks what device this is or what the AI can do" }

    public func run(argument: String) async -> AIToolResult {
        let device = UIDevice.current
        let report = await MainActor.run { AICapabilityReport() }
        let summary = "\(device.model) on iOS \(device.systemVersion). \(report.summary)"
        return AIToolResult(tool: name, ok: true, summary: summary, detail: report.reasons.map { "\($0.key.rawValue): \($0.value.explanation)" }.joined(separator: "; "))
    }
}

/// Local search across text the user supplies, plus simple arithmetic.
public struct SearchTool: AITool {
    public init() {}
    public var name: String { "grep" }
    public var description: String { "Finds lines containing a substring in the text supplied as the argument, formatted as 'needle|||text'." }
    public var usageHint: String { "use when the user gives you a block of text and asks to find something in it" }

    public func run(argument: String) async -> AIToolResult {
        let parts = argument.split(separator: "|", maxSplits: 2, omittingEmptySubsequences: true)
        guard parts.count == 2 else {
            return AIToolResult(tool: name, ok: false, summary: "Expected 'needle|||text'.")
        }
        let needle = String(parts[0])
        let body = String(parts[1])
        let hits = body.split(separator: "\n").filter { $0.localizedCaseInsensitiveContains(needle) }
        guard !hits.isEmpty else {
            return AIToolResult(tool: name, ok: true, summary: "No match for '\(needle)'.")
        }
        return AIToolResult(tool: name, ok: true, summary: "\(hits.count) match(es) for '\(needle)':", detail: hits.prefix(20).joined(separator: "\n"))
    }
}

/// Arithmetic via NSExpression, so the model does not do maths in its head.
public struct MathTool: AITool {
    public init() {}
    public var name: String { "calculate" }
    public var description: String { "Evaluates an arithmetic expression." }
    public var usageHint: String { "use for any arithmetic instead of guessing the answer" }

    public func run(argument: String) async -> AIToolResult {
        let expr = argument.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !expr.isEmpty else {
            return AIToolResult(tool: name, ok: false, summary: "Empty expression.")
        }
        // Only digits and arithmetic operators — never evaluate arbitrary code.
        let allowed = CharacterSet(charactersIn: "0123456789+-*/(). ")
        guard expr.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
            return AIToolResult(tool: name, ok: false, summary: "Only digits and + - * / ( ) are allowed.")
        }
        guard let result = (expr as NSExpression).value(for: nil, with: nil, context: nil) as? Double else {
            return AIToolResult(tool: name, ok: false, summary: "Could not evaluate '\(expr)'.")
        }
        return AIToolResult(tool: name, ok: true, summary: "\(expr) = \(result)")
    }
}

public struct DateTimeTool: AITool {
    public init() {}
    public var name: String { "current_time" }
    public var description: String { "Reports the current date and time on this device." }
    public var usageHint: String { "use when the user asks what time or date it is" }

    public func run(argument: String) async -> AIToolResult {
        let f = DateFormatter()
        f.dateStyle = .full
        f.timeStyle = .medium
        return AIToolResult(tool: name, ok: true, summary: f.string(from: Date()))
    }
}

import UIKit