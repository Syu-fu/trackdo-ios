import SwiftUI
import TrackdoKit

/// A tag as a small capsule in the tag's own color, so tags read apart at a
/// glance. The name stays as text; the color only helps.
struct TagChip: View {
    let tag: TagItem

    var body: some View {
        let color = tag.color
        Text(verbatim: tag.name)
            .lineLimit(1)
            .font(.caption)
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(color.opacity(0.12), in: .capsule)
    }
}

extension TagItem {
    /// Text colors that keep 4.5:1 on their own faint fill over white.
    private static let palette: [Color] = [
        Color(red: 0x00 / 255, green: 0x31 / 255, blue: 0xD8 / 255), // blue
        Color(red: 0x19 / 255, green: 0x7A / 255, blue: 0x4B / 255), // green
        Color(red: 0xB0 / 255, green: 0x3E / 255, blue: 0x00 / 255), // orange
        Color(red: 0x6B / 255, green: 0x2E / 255, blue: 0xC2 / 255), // purple
        Color(red: 0x00 / 255, green: 0x6E / 255, blue: 0x7A / 255), // teal
        Color(red: 0xB0 / 255, green: 0x00 / 255, blue: 0x6E / 255), // magenta
        Color(red: 0x7A / 255, green: 0x62 / 255, blue: 0x00 / 255), // olive
        Color(red: 0x8A / 255, green: 0x45 / 255, blue: 0x2C / 255), // brown
    ]

    var color: Color {
        Self.palette[colorIndex(among: Self.palette.count)]
    }
}
