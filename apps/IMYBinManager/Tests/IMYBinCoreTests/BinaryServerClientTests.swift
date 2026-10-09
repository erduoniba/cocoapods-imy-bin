import Foundation
import Testing
@testable import IMYBinCore

@Test func binaryServerBuildsFrameworksURL() throws {
    #expect(try BinaryServerClient.frameworksURL(from: "http://localhost:8080").absoluteString == "http://localhost:8080/frameworks")
    #expect(try BinaryServerClient.frameworksURL(from: "https://example.com/api/").absoluteString == "https://example.com/api/frameworks")
    #expect(try BinaryServerClient.frameworksURL(from: "https://example.com/frameworks").absoluteString == "https://example.com/frameworks")
}

@Test func binaryServerRejectsUnsafeAddress() {
    #expect(throws: BinaryServerClientError.self) {
        try BinaryServerClient.frameworksURL(from: "localhost:8080")
    }
    #expect(throws: BinaryServerClientError.self) {
        try BinaryServerClient.frameworksURL(from: "file:///tmp/binary-server")
    }
}

@Test func binaryServerDecodesAndSortsComponentVersions() throws {
    let data = Data(#"{"PodB":["1.0.0"],"PodA":["1.2.0","1.10.0"]}"#.utf8)
    let components = try BinaryServerClient.decodeComponents(from: data)

    #expect(components.map(\.name) == ["PodA", "PodB"])
    #expect(components[0].versions == ["1.10.0", "1.2.0"])
}

@Test func binaryServerRejectsUnexpectedPayload() {
    #expect(throws: BinaryServerClientError.self) {
        try BinaryServerClient.decodeComponents(from: Data(#"[{"name":"PodA"}]"#.utf8))
    }
}
