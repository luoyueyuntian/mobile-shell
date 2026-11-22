import Foundation
import XCTest
@testable import MobileShell

final class MoshPreparationParserTests: XCTestCase {
    func testParseLaunchResultExtractsPortAndKeyFromOfficialOutput() throws {
        let output = """
        MOSH CONNECT 60004 4NeCCgvZFe2RnPgrcU1PQw

        mosh-server (mosh 1.1.3)
        [mosh-server detached, pid = 30261]
        """

        let result = try MoshPreparationParser.parse(output)

        XCTAssertEqual(result.port, 60004)
        XCTAssertEqual(result.key, "4NeCCgvZFe2RnPgrcU1PQw")
        XCTAssertNil(result.remoteIPAddress)
        XCTAssertEqual(result.serverOutput, output)
    }

    func testParseLaunchResultExtractsRemoteIPAddressFromExperimentalOutput() throws {
        let output = """
        MOSH SSH_CONNECTION 203.0.113.10 54321 10.0.0.4 22
        MOSH CONNECT 60004 4NeCCgvZFe2RnPgrcU1PQw
        """

        let result = try MoshPreparationParser.parse(output)

        XCTAssertEqual(result.port, 60004)
        XCTAssertEqual(result.key, "4NeCCgvZFe2RnPgrcU1PQw")
        XCTAssertEqual(result.remoteIPAddress, "203.0.113.10")
    }

    func testParseLaunchResultMapsMissingServerMessage() {
        let output = "bash: mosh-server: command not found"

        XCTAssertThrowsError(try MoshPreparationParser.parse(output)) { error in
            XCTAssertEqual(error as? MoshPreparationError, .moshServerMissing)
        }
    }

    func testParseLaunchResultMapsMalformedHandshake() {
        let output = "MOSH CONNECT garbage"

        XCTAssertThrowsError(try MoshPreparationParser.parse(output)) { error in
            XCTAssertEqual(error as? MoshPreparationError, .moshHandshakeParseFailed)
        }
    }

    func testParseLaunchResultMapsGenericLaunchFailure() {
        let output = "mosh-server: failed to bind"

        XCTAssertThrowsError(try MoshPreparationParser.parse(output)) { error in
            XCTAssertEqual(error as? MoshPreparationError, .moshServerLaunchFailed(output))
        }
    }
}
