import Testing
@testable import TrackdoKit

@Suite struct ServerURLTests {
    @Test(arguments: [
        ("https://sync.example.com", "https://sync.example.com"),
        ("https://sync.example.com/", "https://sync.example.com"),
        ("  https://sync.example.com:8443/trackdo/ \n", "https://sync.example.com:8443/trackdo"),
        ("HTTPS://Sync.Example.com", "https://sync.example.com"),
    ])
    func acceptsHTTPS(input: String, expected: String) throws {
        #expect(try ServerURL(input).url.absoluteString == expected)
    }

    @Test(arguments: [
        "http://localhost:8080",
        "http://127.0.0.1:8080",
        "http://10.0.0.2",
        "http://172.16.5.4",
        "http://172.31.255.255",
        "http://192.168.1.10:8080",
        "http://169.254.10.1",
        "http://macbook.local:8080",
        "http://[::1]:8080",
        "http://[fe80::1]",
        "http://[fd12:3456::1]",
    ])
    func acceptsHTTPOnTheLocalNetwork(input: String) throws {
        #expect(try ServerURL(input).url.scheme == "http")
    }

    @Test(arguments: [
        "http://sync.example.com",
        "http://8.8.8.8",
        "http://172.32.0.1",
        "http://192.169.0.1",
        "http://[2001:db8::1]",
    ])
    func refusesHTTPElsewhere(input: String) {
        #expect(throws: ServerURLError.insecureRemoteHost) { try ServerURL(input) }
    }

    @Test(arguments: [
        ("", ServerURLError.malformed),
        ("sync.example.com", .malformed),
        ("https://", .malformed),
        ("ftp://sync.example.com", .unsupportedScheme),
        ("https://sync.example.com/?a=1", .hasQueryOrFragment),
        ("https://sync.example.com/#top", .hasQueryOrFragment),
        ("https://me:secret@sync.example.com", .hasCredentials),
    ])
    func refusesOtherURLs(input: String, error: ServerURLError) {
        #expect(throws: error) { try ServerURL(input) }
    }

    @Test func endpointsHangOffThePath() throws {
        let server = try ServerURL("https://sync.example.com/trackdo/")

        #expect(server.endpoint("ops").absoluteString == "https://sync.example.com/trackdo/ops")
    }
}
