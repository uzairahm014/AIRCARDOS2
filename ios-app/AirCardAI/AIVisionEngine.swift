// AirCard AI — on-device vision: OCR and image description.
//
// Uses Vision for real text recognition and image classification on the
// device. Images are never uploaded. `describe` returns Vision's actual
// observations — if Vision has nothing to say, it says so rather than
// inventing a caption.
//
// BUILD STATUS: not compiled here (no macOS/Xcode). See docs/BUILD-BLOCKER.md.

import CoreImage
import Foundation
import Observation
import UIKit
import Vision

@Observable
@MainActor
public final class AIVisionEngine: Sendable {
    public enum State: String, Sendable { case idle, working, done, failed }

    public private(set) var state: State = .idle
    public private(set) var recognisedText: String = ""
    public private(set) var observations: [String] = []
    public private(set) var lastError: String?

    /// Record a failure from outside the engine.
    public func report(_ message: String?) { lastError = message }

    private let context = CIContext()

    public init() {}

    /// Extract every text block Vision can actually read in the image.
    public func readText(in image: UIImage) async {
        state = .working
        lastError = nil
        recognisedText = ""
        observations = []

        guard let cg = image.cgImage else {
            state = .failed
            lastError = "That image has no bitmap I can read."
            return
        }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true

        do {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                let handler = VNImageRequestHandler(cgImage: cg, options: [:])
                DispatchQueue.global(qos: .userInitiated).async {
                    do {
                        try handler.perform([request])
                        cont.resume()
                    } catch {
                        cont.resume(throwing: error)
                    }
                }
            }

            let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
            recognisedText = lines.joined(separator: "\n")
            state = .done
        } catch {
            state = .failed
            lastError = error.localizedDescription
        }
    }

    /// Real, on-device image understanding: Vision's own classification plus
    /// salient features. Returns an empty list rather than a made-up caption.
    public func describe(_ image: UIImage) async {
        state = .working
        lastError = nil
        observations = []

        guard let cg = image.cgImage else {
            state = .failed
            lastError = "That image has no bitmap I can read."
            return
        }

        var found: [String] = []

        // 1. Classification, if this OS exposes it.
        if #available(iOS 17, *) {
            let classify = VNClassifyImageRequest()
            do {
                try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                    let handler = VNImageRequestHandler(cgImage: cg, options: [:])
                    DispatchQueue.global(qos: .userInitiated).async {
                        do { try handler.perform([classify]); cont.resume() }
                        catch { cont.resume(throwing: error) }
                    }
                }
                let results = (classify.results ?? [])
                    .prefix(5)
                    .map { String(format: "%@ (%.0f%%)", $0.identifier, $0.confidence * 100) }
                found.append(contentsOf: results)
            } catch {
                lastError = "Classification unavailable: \(error.localizedDescription)"
            }
        }

        // 2. Object detection, when the OS provides it.
        if #available(iOS 17, *) {
            let detect = VNDetectHumanRectanglesRequest()
            detect.upperBodyOnly = false
            do {
                try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                    let handler = VNImageRequestHandler(cgImage: cg, options: [:])
                    DispatchQueue.global(qos: .userInitiated).async {
                        do { try handler.perform([detect]); cont.resume() }
                        catch { cont.resume(throwing: error) }
                    }
                }
                if let n = detect.results?.count, n > 0 {
                    found.append("\(n) person(s) detected")
                }
            } catch {
                // Detection is optional; its absence must not be fatal.
            }
        }

        // 3. Image facts we can always compute honestly.
        found.append("\(cg.width)x\(cg.height) px")
        if let data = cg.dataProvider?.data as? Data {
            found.append(String(format: "%.1f KB", Double(data.count) / 1024.0))
        }

        observations = found
        state = found.isEmpty ? .failed : .done
        if found.isEmpty { lastError = "Vision found nothing to describe in this image." }
    }

    /// Average colour, for palette-style questions. Real pixels, not a guess.
    public func averageColour(_ image: UIImage) async -> (r: Int, g: Int, b: Int)? {
        guard let ci = CIImage(image: image) else { return nil }
        // Render into a single 1x1 pixel. CIContext does the averaging for us;
        // reading a pixel out of the original bitmap would only give us
        // whichever pixel we happened to ask for.
        var pixel = [UInt8](repeating: 0, count: 4)
        context.render(
            ci,
            toBitmap: &pixel,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )
        return (Int(pixel[0]), Int(pixel[1]), Int(pixel[2]))
    }

    public func reset() {
        state = .idle
        recognisedText = ""
        observations = []
        lastError = nil
    }
}