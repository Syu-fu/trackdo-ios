import Foundation
import Testing
@testable import TrackdoKit

@Suite struct ElapsedTimeTests {
    let english = Locale(identifier: "en_US")

    @Test(arguments: [
        (0, "0:00:00"),
        (999, "0:00:00"),
        (61_000, "0:01:01"),
        (3_723_000, "1:02:03"),
        (360_000_000, "100:00:00"),
    ] as [(UInt64, String)])
    func clockShowsHoursMinutesAndSeconds(ms: UInt64, expected: String) {
        #expect(ElapsedTime.clock(ms, locale: english) == expected)
    }

    @Test(arguments: [
        (0, "0 seconds"),
        (61_000, "1 minute, 1 second"),
        (3_723_000, "1 hour, 2 minutes, 3 seconds"),
    ] as [(UInt64, String)])
    func spokenNamesTheUnits(ms: UInt64, expected: String) {
        #expect(ElapsedTime.spoken(ms, locale: english) == expected)
    }
}
