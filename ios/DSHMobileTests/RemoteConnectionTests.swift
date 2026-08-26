import XCTest
@testable import DSHMobile

final class RemoteConnectionTests: XCTestCase {
    func testParsesDesktopPairingURL() throws {
        let url = try XCTUnwrap(URL(string: "http://192.168.1.8:3081/__remote/pair?token=0123456789abcdef"))
        let connection = try XCTUnwrap(RemoteConnection.from(pairingURL: url))

        XCTAssertEqual(connection.baseURL.absoluteString, "http://192.168.1.8:3081/")
        XCTAssertEqual(connection.statusURL.path, "/__remote/api/status")
        XCTAssertEqual(connection.actionURL.path, "/__remote/api/action")
        XCTAssertEqual(connection.token, "0123456789abcdef")
    }

    func testRejectsShortTokenAndUnexpectedPath() {
        XCTAssertNil(RemoteConnection.from(pairingURL: URL(string: "http://mac.local:3081/__remote/pair?token=short")!))
        XCTAssertNil(RemoteConnection.from(pairingURL: URL(string: "http://mac.local:3081/not-pairing?token=0123456789abcdef")!))
    }

    func testStatusCapabilities() {
        XCTAssertTrue(RemoteStatus(state: "running", label: "运行中", detail: nil, controllable: true).isReady)
        XCTAssertFalse(RemoteStatus(state: "stopped", label: "已停止", detail: nil, controllable: false).isReady)
    }
}
