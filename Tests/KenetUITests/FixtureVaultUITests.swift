import XCTest

/// A fixture vault the UI tests need but cannot find: CI fails the test, a local run skips it.
/// No app is launched; the lookup is measured with an explicit environment.
final class FixtureVaultUITests: XCTestCase {
    private let missing = "no-such-vault-\(UUID().uuidString)"

    func testMissingFixtureSkipsLocally() {
        XCTAssertThrowsError(try UITestSupport.prepareFixtureVault(named: missing, environment: [:])) { error in
            XCTAssertTrue(error is XCTSkip, "Expected a skip, got \(error)")
        }
    }

    func testMissingFixtureFailsOnCI() {
        var thrown: Error?
        let options = XCTExpectedFailure.Options()
        options.isStrict = true
        XCTExpectFailure("A missing fixture records a failure on CI", options: options) {
            thrown = Self.error { try UITestSupport.prepareFixtureVault(named: missing, environment: ["CI": "true"]) }
        }
        XCTAssertNotNil(thrown)
        XCTAssertFalse(thrown is XCTSkip, "CI must not skip a missing fixture")
    }

    func testPresentFixtureIsCopiedOnCI() throws {
        let copy = try UITestSupport.prepareFixtureVault(named: "sample", environment: ["CI": "true"])
        defer { try? FileManager.default.removeItem(at: copy) }
        XCTAssertTrue(FileManager.default.fileExists(atPath: copy.appendingPathComponent("journal").path))
    }

    func testOnlyASetCIValueCountsAsCI() {
        XCTAssertTrue(UITestSupport.isCI(["CI": "true"]))
        XCTAssertTrue(UITestSupport.isCI(["CI": "1"]))
        XCTAssertFalse(UITestSupport.isCI([:]))
        XCTAssertFalse(UITestSupport.isCI(["CI": ""]))
        XCTAssertFalse(UITestSupport.isCI(["CI": "false"]))
        XCTAssertFalse(UITestSupport.isCI(["CI": "0"]))
    }

    private static func error(_ body: () throws -> URL) -> Error? {
        do {
            _ = try body()
            return nil
        } catch {
            return error
        }
    }
}
