//
//  AirCardLibraryTests.swift
//  AirCard-iOS tests
//
//  These tests pin the same honesty contract the Rust engine's tests pin:
//  no mechanism means UNSUPPORTED, an unverified build means EXPERIMENTAL, and
//  a failed apply must stop reading as AVAILABLE.
//
//  COMPILES-UNVERIFIED: authored on Windows. Never through xcodebuild.
//  See docs/BUILD-BLOCKER.md.
//

import XCTest
@testable import AirCard_iOS

final class AirCardLibraryTests: XCTestCase {

    private func def(
        id: String = "x",
        backend: TweakBackend,
        minIOS: String? = nil,
        verifiedBuilds: [String] = [],
        implID: String = ""
    ) -> TweakDefinition {
        TweakDefinition(
            id: id, name: id, category: "Test", backend: backend,
            minIOS: minIOS, verifiedBuilds: verifiedBuilds, implID: implID,
            unsupportedReason: backend == .unsupported ? "no mechanism" : ""
        )
    }

    private var targetFacts: DeviceFacts {
        DeviceFacts(productType: "iPhone14,3", iosVersion: "27.0", build: "24A437")
    }

    func testUnsupportedBackendIsNeverAvailable() {
        let entry = CompatibilityEngine(facts: targetFacts)
            .evaluate(def(backend: .unsupported))
        XCTAssertEqual(entry.state, .unsupported)
        XCTAssertFalse(entry.verdict.isEmpty)
    }

    func testUnverifiedBuildIsExperimentalNotAvailable() {
        let entry = CompatibilityEngine(facts: targetFacts).evaluate(def(backend: .airLift))
        XCTAssertEqual(entry.state, .experimental)
        XCTAssertTrue(entry.verdict.contains("24A437"))
    }

    func testConfirmedBuildBecomesAvailable() {
        let engine = CompatibilityEngine(facts: targetFacts, verifiedBuilds: ["24A437"])
        let entry = engine.evaluate(def(backend: .airLift))
        XCTAssertEqual(entry.state, .available)
        XCTAssertTrue(entry.verifiedOnDevice)
    }

    func testDefinitionCanAlsoConfirmItsOwnBuild() {
        let entry = CompatibilityEngine(facts: targetFacts)
            .evaluate(def(backend: .airLift, verifiedBuilds: ["24A437"]))
        XCTAssertEqual(entry.state, .available)
    }

    func testMinIOSGatesByVersion() {
        let entry = CompatibilityEngine(facts: targetFacts)
            .evaluate(def(backend: .airLift, minIOS: "30.0"))
        XCTAssertEqual(entry.state, .unsupported)
        XCTAssertTrue(entry.verdict.contains("iOS 30.0"))
    }

    func testOlderDeviceIsGated() {
        let old = DeviceFacts(productType: "iPhone14,3", iosVersion: "16.0", build: "20A362")
        let entry = CompatibilityEngine(facts: old)
            .evaluate(def(backend: .airLift, minIOS: "27.0"))
        XCTAssertEqual(entry.state, .unsupported)
    }

    func testFailedApplyStopsReadingAsAvailable() {
        var library = TweakLibrary(facts: targetFacts)
        library.merge([def(id: "a", backend: .airLift, implID: "Passcode.CustomTheme")])
        library.recordApply(id: "a", verified: false)
        let entry = library.entry("a")
        XCTAssertEqual(entry?.state, .failed)
        XCTAssertFalse(entry?.verifiedOnDevice ?? true)
        XCTAssertTrue(entry?.verdict.contains("FAILED") ?? false)
    }

    func testVerifiedApplyBecomesInstalled() {
        var library = TweakLibrary(facts: targetFacts)
        library.merge([def(id: "a", backend: .airLift, implID: "Passcode.CustomTheme")])
        library.recordApply(id: "a", verified: true)
        XCTAssertEqual(library.entry("a")?.state, .installed)
    }

    func testEntriesWithoutImplementationCannotApply() {
        var library = TweakLibrary(facts: targetFacts)
        library.merge([
            def(id: "a", backend: .airLift, implID: "Passcode.CustomTheme"),
            def(id: "b", backend: .airLift),
        ])
        let filter = LibraryFilter()
        filter.implementedOnly = true
        XCTAssertEqual(library.search(filter).map(\.def.id), ["a"])
    }

    func testBridgeRefusesAnUnknownImplementation() {
        let result = MainActor.assumeIsolated {
            AirCardSystemBridge.shared.apply("Something.NotReal")
        }
        XCTAssertFalse(result.succeeded)
        XCTAssertTrue(result.detail.contains("no compiled implementation"))
    }

    func testEveryKnownOperationMapsBackToItsLibraryID() {
        for op in TweakOperation.allCases {
            XCTAssertEqual(AirCardSystemBridge.operation(forImplID: op.rawValue), op)
        }
        XCTAssertNil(AirCardSystemBridge.operation(forImplID: ""))
    }

    func testParsesBothWrappedAndBareJSON() throws {
        let wrapped = Data("""
        {"category":"Test","tweaks":[
          {"id":"a","name":"A","category":"Test","backend":"air_lift","risk":"low"}
        ]}
        """.utf8)
        let bare = Data("""
        [{"id":"b","name":"B","category":"Test","backend":"native_ios","risk":"high"}]
        """.utf8)
        XCTAssertEqual(try TweakLibrary.parse(data: wrapped).count, 1)
        let parsed = try TweakLibrary.parse(data: bare)
        XCTAssertEqual(parsed[0].backend, .nativeIOS)
        XCTAssertEqual(parsed[0].risk, .high)
    }

    func testSearchFiltersByTextCategoryAndRisk() {
        var library = TweakLibrary(facts: targetFacts)
        var dock = def(id: "home.dock", backend: .airLift)
        dock.name = "Hide the dock"
        dock.tags = ["home screen"]
        var power = def(id: "batt", backend: .airLift)
        power.name = "Battery percentage"
        power.category = "Battery"
        power.risk = .high
        library.merge([dock, power])

        var f = LibraryFilter(); f.query = "dock"
        XCTAssertEqual(library.search(f).count, 1)
        var g = LibraryFilter(); g.category = "Battery"
        XCTAssertEqual(library.search(g).count, 1)
        var h = LibraryFilter(); h.maxRisk = .low
        XCTAssertEqual(library.search(h).map(\.def.id), ["home.dock"])
        var i = LibraryFilter(); i.query = "nothing matches this"
        XCTAssertTrue(library.search(i).isEmpty)
    }

    /// The shipped JSON must satisfy the same contract the Rust tests enforce.
    func testShippedLibraryIsInternallyConsistent() throws {
        guard let url = Bundle(for: Self.self).url(
            forResource: "statusbar", withExtension: "json"
        ) else {
            throw XCTSkip("library resources are not in the test bundle yet")
        }
        let defs = try TweakLibrary.parse(data: try Data(contentsOf: url))
        XCTAssertFalse(defs.isEmpty)
        let library = TweakLibrary(facts: targetFacts, verifiedBuilds: ["24A437"])
        var merged = library
        merged.merge(defs)
        for entry in merged.entries {
            if entry.state == .unsupported {
                XCTAssertFalse(
                    entry.def.unsupportedReason.trimmingCharacters(in: .whitespaces).isEmpty,
                    "\(entry.def.id) is unsupported with no reason"
                )
            }
            if entry.verifiedOnDevice {
                XCTAssertTrue(
                    entry.def.verifiedBuilds.contains("24A437"),
                    "\(entry.def.id) claims verification without naming the build"
                )
            }
        }
    }
}
