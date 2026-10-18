import SwiftUI

/// DADS input text (components/input-text), medium size: item label with an
/// optional "※Required" label, support text above the field and error text
/// starting with "＊" below it. No placeholder; conditions go in the support
/// text. The error is not announced while typing, only read with the field.
struct DadsInputText<Field: View>: View {
    let label: LocalizedStringResource
    var isRequired = false
    var support: LocalizedStringResource?
    var error: LocalizedStringResource?
    let isFocused: Bool
    @ViewBuilder let field: () -> Field

    private static var radius: CGFloat { 8 }

    var body: some View {
        DadsFormField(label: label, isRequired: isRequired, support: support, error: error) {
            field()
                .dadsFont(.std16N170)
                .foregroundStyle(DadsColor.gray900)
                .tint(DadsColor.key900)
                .padding(.horizontal, 16)
                .frame(minHeight: 48)
                .background(DadsColor.white, in: .rect(cornerRadius: Self.radius))
                .overlay {
                    RoundedRectangle(cornerRadius: Self.radius)
                        .strokeBorder(error == nil ? DadsColor.gray600 : DadsColor.error1, lineWidth: 1)
                }
                .dadsFocusRing(isFocused, cornerRadius: Self.radius)
        }
    }
}

/// The parts every DADS form control shares: item label, "※Required",
/// support text above the control and "＊" error text below it. The control
/// is read with the label, then the support and error text as its hint,
/// like `aria-describedby`.
struct DadsFormField<Control: View>: View {
    let label: LocalizedStringResource
    var isRequired = false
    var support: LocalizedStringResource?
    var error: LocalizedStringResource?
    @ViewBuilder let control: () -> Control

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(label)
                    .dadsFont(.std17B170)
                    .foregroundStyle(DadsColor.gray800)
                if isRequired {
                    Text("※Required")
                        .dadsFont(.std16N170)
                        .foregroundStyle(DadsColor.error1)
                }
            }
            .accessibilityHidden(true)
            if let support {
                Text(plain: support)
                    .dadsFont(.std16N170)
                    .fixedSize(horizontal: false, vertical: true)
                    .foregroundStyle(DadsColor.gray600)
                    .accessibilityHidden(true)
            }
            control()
                .accessibilityLabel(Text(label))
                .accessibilityHint(hint)
            if let error {
                Text(plain: "＊\(error)")
                    .dadsFont(.dns16N130)
                    .fixedSize(horizontal: false, vertical: true)
                    .foregroundStyle(DadsColor.error1)
                    .accessibilityHidden(true)
            }
        }
    }

    private var hint: String {
        let required: LocalizedStringResource? = isRequired ? "Required" : nil
        return [required, support, error].compactMap { $0.map { String(localized: $0) } }.joined(separator: ". ")
    }
}
