import SwiftUI

extension View {
    /// A banner as a list row: inset like the rows, with no separator.
    func bannerRow() -> some View {
        listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            .listRowBackground(DadsColor.white)
    }
}
