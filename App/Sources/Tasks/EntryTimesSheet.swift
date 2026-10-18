import SwiftUI
import TrackdoKit

/// Edits an entry's start and end, or records past work. A running entry
/// has no end to edit. Unsaved changes are confirmed before closing.
struct EntryTimesSheet: View {
    enum Purpose: Identifiable {
        case add
        case edit(EntryItem)

        var id: String {
            switch self {
            case .add: "add"
            case let .edit(entry): "edit-\(entry.id)"
            }
        }
    }

    let model: TaskDetailModel
    let purpose: Purpose

    @Environment(\.dismiss) private var dismiss
    @State private var start: Date
    @State private var stop: Date
    @State private var issue: EntryTimesIssue?
    @State private var isConfirmingDiscard = false
    private let initial: (start: Date, stop: Date)

    init(model: TaskDetailModel, purpose: Purpose, now: Date = .now) {
        self.model = model
        self.purpose = purpose
        let times: (start: Date, stop: Date)
        switch purpose {
        case .add:
            let end = Calendar.current.dateInterval(of: .minute, for: now)?.start ?? now
            times = (end - 3600, end)
        case let .edit(entry):
            times = (entry.startedAt ?? now, entry.stoppedAt ?? now)
        }
        initial = times
        _start = State(initialValue: times.start)
        _stop = State(initialValue: times.stop)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    DadsFormField(
                        label: "Start",
                        isRequired: true,
                        support: "When the work began.",
                        error: isRunning ? issue?.message : nil
                    ) {
                        picker($start)
                    }
                    if isRunning {
                        DadsFormField(label: "End") {
                            Text("Still running. Stop the timer to set the end.")
                                .dadsFont(.std16N170)
                                .foregroundStyle(DadsColor.gray800)
                        }
                    } else {
                        DadsFormField(
                            label: "End",
                            isRequired: true,
                            support: "When the work ended, after the start and not later than now.",
                            error: issue?.message
                        ) {
                            picker($stop)
                        }
                    }
                    if !isRunning {
                        duration
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 24)
            }
            .background(DadsColor.white)
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel, action: cancel)
                        .confirmationDialog("Discard your changes?", isPresented: $isConfirmingDiscard) {
                            Button("Discard Changes", role: .destructive) { dismiss() }
                            Button("Keep Editing", role: .cancel) {}
                        }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(confirmTitle, action: save)
                }
            }
        }
        .interactiveDismissDisabled(isChanged)
        .onChange(of: issue) { _, issue in
            if let issue {
                AccessibilityNotification.Announcement(String(localized: issue.message)).post()
            }
        }
    }

    private func picker(_ selection: Binding<Date>) -> some View {
        DatePicker("", selection: selection, in: ...Date.now, displayedComponents: [.date, .hourAndMinute])
            .labelsHidden()
            .tint(DadsColor.key900)
    }

    /// What the entered times add up to, before saving.
    private var duration: some View {
        let ms = UInt64(max(0, stop.timeIntervalSince(start)) * 1000)
        return VStack(alignment: .leading, spacing: 4) {
            Text("Duration")
                .dadsFont(.std17B170)
                .foregroundStyle(DadsColor.gray800)
            Text(verbatim: ElapsedTime.clock(ms))
                .dadsFont(.std20B150)
                .monospacedDigit()
                .foregroundStyle(DadsColor.gray900)
                .accessibilityLabel(Text(verbatim: ElapsedTime.spoken(ms)))
        }
        .accessibilityElement(children: .combine)
    }

    private var isRunning: Bool {
        if case let .edit(entry) = purpose {
            return entry.isRunning
        }
        return false
    }

    private var isChanged: Bool {
        start != initial.start || stop != initial.stop
    }

    private var navigationTitle: LocalizedStringKey {
        switch purpose {
        case .add: "Add Past Entry"
        case .edit: "Edit Times"
        }
    }

    private var confirmTitle: LocalizedStringKey {
        switch purpose {
        case .add: "Add"
        case .edit: "Save"
        }
    }

    private func cancel() {
        if isChanged {
            isConfirmingDiscard = true
        } else {
            dismiss()
        }
    }

    private func save() {
        Task {
            do throws(EntryTimesIssue) {
                switch purpose {
                case .add: try await model.addEntry(start: start, stop: stop)
                case let .edit(entry): try await model.editTimes(entry.id, start: start, stop: isRunning ? nil : stop)
                }
                dismiss()
            } catch {
                issue = error
            }
        }
    }
}
