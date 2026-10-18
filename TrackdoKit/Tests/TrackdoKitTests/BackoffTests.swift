import Testing
@testable import TrackdoKit

@Suite struct BackoffTests {
    @Test func ceilingDoublesUpToTheCap() {
        var backoff = Backoff()

        let delays = (0..<9).map { _ in backoff.nextDelay(jitter: 1) }

        #expect(delays == [1, 2, 4, 8, 16, 32, 60, 60, 60].map { Duration.seconds($0) })
    }

    @Test func fullJitterSpreadsBelowTheCeiling() {
        var backoff = Backoff()
        _ = backoff.nextDelay(jitter: 1)

        #expect(backoff.nextDelay(jitter: 0.25) == .milliseconds(500))
        #expect(backoff.nextDelay(jitter: 0) == .zero)
    }

    @Test func jitterOutsideTheUnitRangeIsClamped() {
        var backoff = Backoff()

        #expect(backoff.nextDelay(jitter: 3) == .seconds(1))
        #expect(backoff.nextDelay(jitter: -1) == .zero)
    }

    @Test func resetStartsOverAfterSuccess() {
        var backoff = Backoff()
        for _ in 0..<5 {
            _ = backoff.nextDelay(jitter: 1)
        }

        backoff.reset()

        #expect(backoff.nextDelay(jitter: 1) == .seconds(1))
    }

    @Test func manyFailuresStayAtTheCap() {
        var backoff = Backoff()
        for _ in 0..<10_000 {
            _ = backoff.nextDelay(jitter: 1)
        }

        #expect(backoff.nextDelay(jitter: 1) == .seconds(60))
    }

    @Test func randomDelaysStayWithinTheCeiling() {
        var backoff = Backoff(base: .milliseconds(100), cap: .seconds(1))

        let delays = (0..<100).map { _ in backoff.nextDelay() }

        #expect(delays.allSatisfy { $0 >= .zero && $0 <= .seconds(1) })
    }
}
