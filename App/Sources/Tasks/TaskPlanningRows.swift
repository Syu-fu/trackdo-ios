import SwiftUI
import TrackdoKit

/// A task's planning on its detail screen, one row each: priority, due
/// date, schedule, tags and note. Every change is saved as it is made; the note
/// is saved when editing leaves it. Fields left empty take one tap to add.
struct TaskPlanningRows: View {
    let model: TaskDetailModel
    let task: TaskItem
    let onEditTags: () -> Void

    @State private var note: String
    @State private var noteIssue: NoteIssue?
    @FocusState private var isEditingNote: Bool

    init(model: TaskDetailModel, task: TaskItem, onEditTags: @escaping () -> Void) {
        self.model = model
        self.task = task
        self.onEditTags = onEditTags
        _note = State(initialValue: task.note ?? "")
    }

    var body: some View {
        Group {
            priorityRow
            dueRow
            scheduleRow
            tagsRow
            noteRow
        }
        // Each row's 44 pt targets carry their own space.
        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 10))
        .listRowBackground(DadsColor.white)
        .listRowSeparatorTint(DadsColor.gray420)
        .onChange(of: task.note) { _, synced in
            // Edits from other devices show unless this one is being typed.
            if !isEditingNote {
                note = synced ?? ""
            }
        }
        .onChange(of: isEditingNote) { _, isEditing in
            if !isEditing {
                saveNote()
            }
        }
        .onDisappear(perform: saveNote)
    }

    private var priorityRow: some View {
        Picker(selection: priority) {
            ForEach(TaskPriority.allCases.reversed(), id: \.self) { priority in
                Text(priority.label).tag(priority)
            }
        } label: {
            PlanningLabel("Priority", systemImage: "flag")
        }
        .pickerStyle(.menu)
        .tint(task.priority.color)
    }

    private var dueRow: some View {
        DateRow {
            PlanningLabel("Due Date", systemImage: "calendar")
        } value: {
            if task.due != nil {
                DatePicker("Due Date", selection: due, displayedComponents: .date)
                    .labelsHidden()
                ClearButton(label: "Remove Due Date") {
                    Task { await model.setDue(nil) }
                }
            } else {
                AddButton(label: "Add Due Date") {
                    Task { await model.setDue(CalendarDay(.now)) }
                }
            }
        }
    }

    private var scheduleRow: some View {
        DateRow {
            PlanningLabel("Planned For", systemImage: "clock")
        } value: {
            if task.scheduledAt != nil {
                DatePicker("Planned For", selection: scheduledAt)
                    .labelsHidden()
                ClearButton(label: "Remove Plan") {
                    Task { await model.schedule(nil) }
                }
            } else {
                AddButton(label: "Plan a Time") {
                    Task { await model.schedule(Self.nextHour(after: .now)) }
                }
            }
        }
    }

    /// The chips themselves, the whole row opening the tag sheet.
    private var tagsRow: some View {
        Button(action: onEditTags) {
            HStack(alignment: .top) {
                PlanningLabel("Tags", systemImage: "tag")
                Spacer()
                if task.tags.isEmpty {
                    Text("Add")
                        .foregroundStyle(DadsColor.key900)
                        .frame(minWidth: 44, minHeight: 44)
                } else {
                    FlowLayout(spacing: 6, lineSpacing: 6) {
                        ForEach(task.tags) { TagChip(tag: $0) }
                    }
                    .padding(.vertical, 12)
                    // Ends where the other rows' text does.
                    .padding(.trailing, 6)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Tags"))
        .accessibilityValue(task.tags.isEmpty
            ? Text("None")
            : Text(verbatim: task.tags.map(\.name).formatted(.list(type: .and))))
        .accessibilityHint(Text("Chooses the task’s tags."))
        .accessibilityAddTraits(.isButton)
    }

    private var noteRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 8) {
                // One line of the note tall, so it sits beside the first line.
                Image(systemName: "note.text")
                    .foregroundStyle(DadsColor.gray600)
                    .frame(width: 24, height: 21)
                    .accessibilityHidden(true)
                TextField("Note", text: $note, prompt: Text("Add a note"), axis: .vertical)
                    .focused($isEditingNote)
                    .dadsFont(.dns16N130)
                    .foregroundStyle(DadsColor.gray900)
            }
            if let noteIssue {
                Text(noteIssue.message)
                    .dadsFont(.dns14N130)
                    .foregroundStyle(DadsColor.error1)
                    .padding(.leading, 32)
            }
        }
        .padding(.vertical, 12)
        .toolbar {
            if isEditingNote {
                ToolbarItem(placement: .keyboard) {
                    HStack {
                        Spacer()
                        Button("Done") { isEditingNote = false }
                    }
                }
            }
        }
    }

    private var priority: Binding<TaskPriority> {
        Binding { task.priority } set: { priority in
            Task { await model.setPriority(priority) }
        }
    }

    private var due: Binding<Date> {
        Binding { task.due?.date() ?? .now } set: { date in
            Task { await model.setDue(CalendarDay(date)) }
        }
    }

    private var scheduledAt: Binding<Date> {
        Binding { task.scheduledAt ?? .now } set: { date in
            Task { await model.schedule(date) }
        }
    }

    private func saveNote() {
        guard note != (task.note ?? "") else {
            return
        }
        Task {
            do throws(NoteIssue) {
                try await model.setNote(note)
                noteIssue = nil
            } catch {
                noteIssue = error
                AccessibilityNotification.Announcement(String(localized: error.message)).post()
            }
        }
    }

    /// The next whole hour, a time people plan around.
    static func nextHour(after date: Date) -> Date {
        let calendar = Calendar.current
        let hour = calendar.dateInterval(of: .hour, for: date)?.start ?? date
        return calendar.date(byAdding: .hour, value: 1, to: hour) ?? date
    }
}

/// A name and a date control on one line, or the control under the name
/// when a date and time do not fit beside it.
private struct DateRow<Label: View, Value: View>: View {
    @ViewBuilder let label: Label
    @ViewBuilder let value: Value

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack {
                label
                Spacer()
                value
            }
            VStack(alignment: .trailing, spacing: 0) {
                label.frame(maxWidth: .infinity, alignment: .leading)
                HStack { value }
            }
            .padding(.bottom, 4)
        }
    }
}

/// A planning row's name with its symbol, the symbols lined up.
private struct PlanningLabel: View {
    let title: LocalizedStringKey
    let systemImage: String

    init(_ title: LocalizedStringKey, systemImage: String) {
        self.title = title
        self.systemImage = systemImage
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(DadsColor.gray600)
                .frame(width: 24)
                .accessibilityHidden(true)
            Text(title)
                .dadsFont(.dns16N130)
                .foregroundStyle(DadsColor.gray900)
        }
        .frame(minHeight: 44)
    }
}

private struct AddButton: View {
    let label: LocalizedStringKey
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("Add")
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.borderless)
        .tint(DadsColor.key900)
        .accessibilityLabel(Text(label))
    }
}

private struct ClearButton: View {
    let label: LocalizedStringKey
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(DadsColor.gray536)
                .frame(width: 44, height: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(Text(label))
    }
}
