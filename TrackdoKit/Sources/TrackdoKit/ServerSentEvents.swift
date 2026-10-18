/// One event of a `text/event-stream`.
public struct ServerSentEvent: Sendable, Equatable {
    /// The last id the stream set, which carries over to later events.
    public let id: String?
    public let event: String
    public let data: String
}

/// Splits a `text/event-stream` into events as the HTML standard specifies.
///
/// Reads bytes rather than lines because `URLSession.AsyncBytes.lines` drops
/// the blank lines that end events.
public struct SSEParser: Sendable {
    private static let lineFeed = UInt8(ascii: "\n")
    private static let carriageReturn = UInt8(ascii: "\r")

    private var line: [UInt8] = []
    private var afterCarriageReturn = false
    private var data: [String] = []
    private var eventType = ""
    private var lastId: String?

    public init() {}

    /// The events that `bytes` complete. Partial lines and events are kept
    /// for the next call.
    public mutating func feed(_ bytes: some Sequence<UInt8>) -> [ServerSentEvent] {
        var events: [ServerSentEvent] = []
        for byte in bytes {
            if afterCarriageReturn {
                afterCarriageReturn = false
                if byte == Self.lineFeed {
                    continue
                }
            }
            switch byte {
            case Self.carriageReturn, Self.lineFeed:
                afterCarriageReturn = byte == Self.carriageReturn
                if let event = endLine() {
                    events.append(event)
                }
            default:
                line.append(byte)
            }
        }
        return events
    }

    private mutating func endLine() -> ServerSentEvent? {
        let text = String(decoding: line, as: UTF8.self)
        line.removeAll(keepingCapacity: true)
        if text.isEmpty {
            return dispatch()
        }
        if text.hasPrefix(":") {
            return nil
        }
        let (field, value) = Self.split(text)
        switch field {
        case "data":
            data.append(value)
        case "event":
            eventType = value
        case "id" where !value.contains("\u{0}"):
            lastId = value
        default:
            break
        }
        return nil
    }

    private mutating func dispatch() -> ServerSentEvent? {
        defer {
            data.removeAll()
            eventType = ""
        }
        guard !data.isEmpty else {
            return nil
        }
        return ServerSentEvent(
            id: lastId,
            event: eventType.isEmpty ? "message" : eventType,
            data: data.joined(separator: "\n")
        )
    }

    /// `field: value`, dropping one space after the colon. A line without a
    /// colon is a field with an empty value.
    private static func split(_ line: String) -> (field: Substring, value: String) {
        guard let colon = line.firstIndex(of: ":") else {
            return (line[...], "")
        }
        var value = line[line.index(after: colon)...]
        if value.first == " " {
            value.removeFirst()
        }
        return (line[..<colon], String(value))
    }
}

/// The events of a byte stream such as the body of `GET /events`.
public struct ServerSentEvents<Base: AsyncSequence>: AsyncSequence where Base.Element == UInt8 {
    public typealias Element = ServerSentEvent

    private let base: Base

    public init(_ base: Base) {
        self.base = base
    }

    public func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(bytes: base.makeAsyncIterator())
    }

    public struct AsyncIterator: AsyncIteratorProtocol {
        var bytes: Base.AsyncIterator
        var parser = SSEParser()
        var ready: [ServerSentEvent] = []

        public mutating func next() async throws -> ServerSentEvent? {
            while ready.isEmpty {
                guard let byte = try await bytes.next() else {
                    return nil
                }
                ready = parser.feed(CollectionOfOne(byte))
            }
            return ready.removeFirst()
        }
    }
}

extension ServerSentEvents: Sendable where Base: Sendable {}
