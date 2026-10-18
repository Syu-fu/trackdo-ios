import SwiftUI

/// Colors of the Digital Agency design system (DADS), from
/// `@digital-go-jp/design-tokens` 2.0.1. Only the tokens this app uses are
/// listed. The key color is blue, as in the DADS examples.
enum DadsColor {
    static let white = Color(hex: 0xFFFFFF)
    static let black = Color(hex: 0x000000)

    static let gray50 = Color(hex: 0xF2F2F2)
    static let gray300 = Color(hex: 0xB3B3B3)
    static let gray420 = Color(hex: 0x949494)
    static let gray536 = Color(hex: 0x767676)
    static let gray600 = Color(hex: 0x666666)
    static let gray800 = Color(hex: 0x333333)
    static let gray900 = Color(hex: 0x1A1A1A)

    static let key50 = Color(hex: 0xE8F1FE)
    static let key100 = Color(hex: 0xD9E6FF)
    static let key200 = Color(hex: 0xC5D7FB)
    static let key300 = Color(hex: 0x9DB7F9)
    static let key900 = Color(hex: 0x0017C1)
    static let key1000 = Color(hex: 0x00118F)
    static let key1200 = Color(hex: 0x000060)

    static let yellow300 = Color(hex: 0xFFD43D)

    /// Green-800.
    static let success2 = Color(hex: 0x197A4B)
    /// Red-800.
    static let error1 = Color(hex: 0xEC0000)
    /// Red-1000, the hover color of erroneous fields.
    static let red1000 = Color(hex: 0xA90000)
    /// Yellow-900.
    static let warningYellow2 = Color(hex: 0x927200)
}

private extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
