import Foundation

/// How measured time is written: as a clock for the eye, and with unit
/// names for VoiceOver, which reads "1:02:03" as a time of day.
public enum ElapsedTime {
    /// "1:02:03"; hours keep growing past 24.
    public static func clock(_ ms: UInt64, locale: Locale = .current) -> String {
        duration(ms).formatted(.time(pattern: .hourMinuteSecond).locale(locale))
    }

    /// "1 hour, 2 minutes, 3 seconds", leaving out zero units.
    public static func spoken(_ ms: UInt64, locale: Locale = .current) -> String {
        duration(ms).formatted(
            .units(allowed: [.hours, .minutes, .seconds], width: .wide, zeroValueUnits: .hide)
                .locale(locale)
        )
    }

    private static func duration(_ ms: UInt64) -> Duration {
        .seconds(ms / 1000)
    }
}
