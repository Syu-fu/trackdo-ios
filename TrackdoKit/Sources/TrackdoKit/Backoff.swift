/// Exponential backoff with full jitter: each delay is random between zero
/// and a ceiling that doubles per failure, up to `cap`. Randomizing the whole
/// delay keeps devices that failed together from retrying together.
public struct Backoff: Sendable {
    public static let defaultBase: Duration = .seconds(1)
    public static let defaultCap: Duration = .seconds(60)

    private let base: Duration
    private let cap: Duration
    private var ceiling: Duration

    public init(base: Duration = defaultBase, cap: Duration = defaultCap) {
        self.base = base
        self.cap = cap
        ceiling = min(base, cap)
    }

    /// The delay before the next attempt.
    public mutating func nextDelay() -> Duration {
        nextDelay(jitter: .random(in: 0...1))
    }

    /// The delay for a `jitter` between 0 and 1, which picks where it falls
    /// below the ceiling.
    public mutating func nextDelay(jitter: Double) -> Duration {
        let delay = ceiling * min(max(jitter, 0), 1)
        ceiling = min(ceiling * 2, cap)
        return delay
    }

    /// Call after a success so the next failure retries quickly again.
    public mutating func reset() {
        ceiling = min(base, cap)
    }
}
