import SwiftUI
import TrackdoKit

/// A round checkbox tinted by the task's priority, as Todoist draws it, so
/// the row shows priority without spending words on it. An open task is a
/// ring over a faint fill of its color; pressing it previews the check; a
/// done task is a filled disc with a check.
struct PriorityCheckbox: View {
    let priority: TaskPriority
    let isDone: Bool
    var isPressed = false

    private static let diameter: CGFloat = 22

    var body: some View {
        let color = priority.color
        ZStack {
            if isDone {
                Circle().fill(color)
                check.foregroundStyle(DadsColor.white)
            } else {
                Circle().fill(color.opacity(priority == .none ? 0 : 0.12))
                Circle().strokeBorder(color, lineWidth: priority == .none ? 1.5 : 2)
                if isPressed {
                    check.foregroundStyle(color)
                }
            }
        }
        .frame(width: Self.diameter, height: Self.diameter)
    }

    private var check: some View {
        Image(systemName: "checkmark")
            .font(.system(size: 11, weight: .bold))
    }
}

extension TaskPriority {
    /// Each clears 3:1 against white, as a graphic that carries meaning must.
    var color: Color {
        switch self {
        case .none: DadsColor.gray536
        case .low: DadsColor.blue800
        case .medium: Color(red: 0xC7 / 255, green: 0x47 / 255, blue: 0)
        case .high: DadsColor.red900
        }
    }
}

/// The checkbox as a button with a 44 pt target, previewing the check
/// while pressed.
struct CheckboxButton: View {
    let priority: TaskPriority
    let isDone: Bool
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            EmptyView()
        }
        .buttonStyle(Style(priority: priority, isDone: isDone))
        .accessibilityLabel(isDone ? Text("Reopen \(title)") : Text("Complete \(title)"))
    }

    private struct Style: ButtonStyle {
        let priority: TaskPriority
        let isDone: Bool

        func makeBody(configuration: Configuration) -> some View {
            PriorityCheckbox(priority: priority, isDone: isDone, isPressed: configuration.isPressed)
                .frame(width: 44, height: 44)
                .contentShape(.rect)
        }
    }
}
