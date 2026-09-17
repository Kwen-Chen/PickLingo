import XCTest
@testable import PickLingoCore

final class APIEndpointTests: XCTestCase {
    func testInternalHTTPGatewayPreservesItsPrefix() throws {
        XCTAssertEqual(try APIEndpoint.resolve("http://gateway.example.test/standard/v1/").absoluteString,
                       "http://gateway.example.test/standard/v1/chat/completions")
    }

    func testFullEndpointAndQueryArePreserved() throws {
        let url = "https://gateway.example.test/deployments/model/chat/completions?api-version=2026"
        XCTAssertEqual(try APIEndpoint.resolve(url).absoluteString, url)
    }

    func testDefaultAndLocalEndpoints() throws {
        XCTAssertEqual(try APIEndpoint.resolve(" https://api.example.test/ ").absoluteString, "https://api.example.test/v1/chat/completions")
        XCTAssertEqual(try APIEndpoint.resolve("http://localhost:8080/v1").absoluteString, "http://localhost:8080/v1/chat/completions")
    }

    func testInvalidSchemesAndEmbeddedCredentialsAreRejected() {
        for url in ["file:///etc/passwd", "ftp://example.test", "example.test", "https://", "https://user:password@example.test"] {
            XCTAssertThrowsError(try APIEndpoint.resolve(url))
        }
    }

    func testAppManifestAllowsUserConfiguredHTTPServices() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("PickLingo/Info.plist"))
        let plist = try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        let transport = try XCTUnwrap(plist["NSAppTransportSecurity"] as? [String: Any])
        XCTAssertEqual(transport["NSAllowsArbitraryLoads"] as? Bool, true)
    }
}
