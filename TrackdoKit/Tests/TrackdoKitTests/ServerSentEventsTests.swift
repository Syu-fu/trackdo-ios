import Testing
@testable import TrackdoKit

@Suite struct ServerSentEventsTests {
    func parse(_ chunks: String...) -> [ServerSentEvent] {
        var parser = SSEParser()
        return chunks.flatMap { parser.feed(Array($0.utf8)) }
    }

    @Test func parsesAnOpEvent() {
        let events = parse("id: log:1\nevent: op\ndata: {\"a\":1}\n\n")

        #expect(events == [ServerSentEvent(id: "log:1", event: "op", data: #"{"a":1}"#)])
    }

    @Test func joinsDataLines() {
        #expect(parse("data: a\ndata: b\n\n").map(\.data) == ["a\nb"])
    }

    @Test func stripsOneLeadingSpaceOnly() {
        #expect(parse("data:  a\ndata:b\n\n").map(\.data) == [" a\nb"])
    }

    @Test func defaultsTheEventTypeToMessage() {
        #expect(parse("data: a\n\n").map(\.event) == ["message"])
    }

    @Test func ignoresCommentsAndUnknownFields() {
        #expect(parse(":keepalive\n\nretry: 10\nfoo: bar\n\n").isEmpty)
    }

    @Test func waitsForTheBlankLine() {
        #expect(parse("data: a\n").isEmpty)
    }

    @Test func dropsEventsWithoutData() {
        #expect(parse("id: log:1\nevent: op\n\ndata: a\n\n").map(\.data) == ["a"])
    }

    @Test(arguments: ["\r\n", "\r"])
    func acceptsOtherLineEndings(newline: String) {
        let stream = ["id: 1", "data: a", "", "data: b", "", ""].joined(separator: newline)

        #expect(parse(stream) == [
            ServerSentEvent(id: "1", event: "message", data: "a"),
            ServerSentEvent(id: "1", event: "message", data: "b"),
        ])
    }

    @Test func splitsCRLFAcrossChunks() {
        #expect(parse("data: a\r", "\n\r", "\n").map(\.data) == ["a"])
    }

    @Test func keepsTheLastIdForLaterEvents() {
        #expect(parse("id: 1\ndata: a\n\ndata: b\n\n").map(\.id) == ["1", "1"])
    }

    @Test func ignoresIdsContainingNull() {
        #expect(parse("id: 1\ndata: a\n\nid: 2\u{0}\ndata: b\n\n").map(\.id) == ["1", "1"])
    }

    @Test func reassemblesLinesSplitAcrossChunks() {
        let events = parse("id: log", ":7\nda", "ta: 牛", "乳\n", "\n")

        #expect(events == [ServerSentEvent(id: "log:7", event: "message", data: "牛乳")])
    }

    @Test func reassemblesMultibyteCharactersSplitAcrossChunks() {
        let bytes = Array("data: 牛\n\n".utf8)
        var parser = SSEParser()

        let events = parser.feed(bytes[..<7]) + parser.feed(bytes[7...])

        #expect(events.map(\.data) == ["牛"])
    }

    @Test func readsEventsFromAByteStream() async throws {
        let (bytes, continuation) = AsyncStream<UInt8>.makeStream()
        for byte in "data: a\n\n:keepalive\n\ndata: b\n\n".utf8 {
            continuation.yield(byte)
        }
        continuation.finish()

        var received: [String] = []
        for try await event in ServerSentEvents(bytes) {
            received.append(event.data)
        }

        #expect(received == ["a", "b"])
    }
}
