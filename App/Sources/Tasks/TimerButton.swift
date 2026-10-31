import SwiftUI

/// Starts or stops a task's timer. A ring as light as the checkbox while
/// idle, so it does not outweigh the title; filled with the key color while
/// running, the one state worth catching the eye. The target is 44 pt.
struct TimerButton: View {
    let isRunning: Bool
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: isRunning ? "stop.circle.fill" : "play.circle")
                .foregroundStyle(isRunning ? DadsColor.key900 : DadsColor.gray600)
        }
        .buttonStyle(Style())
        .accessibilityLabel(isRunning ? Text("Stop timer for \(title)") : Text("Start timer for \(title)"))
    }

    private struct Style: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .font(.system(size: 26, weight: .light))
                .frame(width: 44, height: 44)
                .contentShape(.rect)
                .opacity(configuration.isPressed ? 0.5 : 1)
        }
    }
}
