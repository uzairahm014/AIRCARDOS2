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
    public func run(tool name: String, argument: String) async -> AIToolResult {
        guard let tool = find(name) else {
            let result = AIToolResult(tool: name, ok: false, summary: "No tool named \(name).")
            history.append((tool: name, argument: argument, result: result))
            return result
        }
        let result = await tool.run(argument: argument)
        history.append((tool: name, argument: argument, result: result))
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

    @MainActor
    public func run(argument: String) async -> AIToolResult {
        let device = UIDevice.current
        let report = AICapabilityReport()
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
        guard let result = Evaluator.evaluate(expr) else {
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
// MARK: - Arithmetic

/// A tiny recursive-descent evaluator for `+ - * / ( )` over numbers.
///
/// This replaces `NSExpression`, which is unavailable in current SDKs and is
/// unsafe to evaluate anyway: it can call Objective-C selectors. This parser
/// only ever produces a Double from digits and four operators, so a tool call
/// cannot do anything except arithmetic.
enum Evaluator {
    static func evaluate(_ input: String) -> Double? {
        let chars = Array(input)
        var pos = 0

        func peek() -> Character? { pos < chars.count ? chars[pos] : nil }

        func skipSpaces() {
            while pos < chars.count, chars[pos] == " " { pos += 1 }
        }

        func parseNumber() -> Double? {
            skipSpaces()
            let start = pos
            var seenDot = false
            while pos < chars.count, chars[pos].isNumber || chars[pos] == "." {
                if chars[pos] == "." {
                    if seenDot { return nil }
                    seenDot = true
                }
                pos += 1
            }
            guard pos > start else { return nil }
            return Double(String(chars[start..<pos]))
        }

        // expression := term (('+' | '-') term)*
        func parseExpression() -> Double? {
            guard var value = parseTerm() else { return nil }
            while true {
                skipSpaces()
                guard let op = peek(), op == "+" || op == "-" else { break }
                pos += 1
                guard let rhs = parseTerm() else { return nil }
                value = (op == "+") ? value + rhs : value - rhs
            }
            return value
        }

        // term := factor (('*' | '/') factor)*
        func parseTerm() -> Double? {
            guard var value = parseFactor() else { return nil }
            while true {
                skipSpaces()
                guard let op = peek(), op == "*" || op == "/" else { break }
                pos += 1
                guard let rhs = parseFactor() else { return nil }
                if op == "*" {
                    value *= rhs
                } else {
                    guard rhs != 0 else { return nil }  // no infinity, no crash
                    value /= rhs
                }
            }
            return value
        }

        // factor := '-' number | '(' expression ')' | number
        func parseFactor() -> Double? {
            skipSpaces()
            guard let c = peek() else { return nil }
            if c == "-" {
                pos += 1
                guard let n = parseFactor() else { return nil }
                return -n
            }
            if c == "+" {
                pos += 1
                return parseFactor()
            }
            if c == "(" {
                pos += 1
                guard let inner = parseExpression() else { return nil }
                skipSpaces()
                guard peek() == ")" else { return nil }
                pos += 1
                return inner
            }
            return parseNumber()
        }

        guard let result = parseExpression() else { return nil }
        skipSpaces()
        guard pos == chars.count else { return nil }   // trailing junk = invalid
        return result
    }
}
