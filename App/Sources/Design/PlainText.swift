import SwiftUI

extension Text {
    /// `resource` without the links Markdown parsing adds to URLs in it:
    /// only link text may look like a link (foundations/link-text).
    init(plain resource: LocalizedStringResource) {
        var text = AttributedString(localized: resource)
        text.link = nil
        self.init(text)
    }
}
