//! Owned snapshots of tasks and time entries for display.

use std::time::Duration;

use trackdo_core::task::{Task, TaskStatus};
use trackdo_core::time_entry::Timestamp;
use trackdo_core::tracking::TimeEntryView;

use crate::ids;

/// A task as listed. Times are Unix milliseconds in UTC.
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct TaskRecord {
    pub id: String,
    /// `None` until the task's title write has been received.
    pub title: Option<String>,
    pub is_done: bool,
    /// The running timer belongs to this task.
    pub is_in_progress: bool,
    /// Time spent on the task, counting a running timer up to now.
    pub total_ms: u64,
}

impl TaskRecord {
    pub(crate) fn new(task: &Task, is_in_progress: bool, total: Duration) -> Self {
        Self {
            id: ids::encode(task.id().0),
            title: task.title().map(|title| title.as_str().to_owned()),
            is_done: task.status() == TaskStatus::Done,
            is_in_progress,
            total_ms: millis(total),
        }
    }
}

/// A time entry as shown, with stops derived by healing applied. Times are
/// Unix milliseconds in UTC.
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct EntryRecord {
    pub id: String,
    pub task_id: String,
    /// `None` until the entry's start write has been received.
    pub started_at_ms: Option<u64>,
    /// `None` while running or before a stop write has been received.
    pub stopped_at_ms: Option<u64>,
    pub is_running: bool,
    /// The stop was derived because another timer took over or the task was
    /// deleted; it is written back automatically.
    pub is_stop_derived: bool,
    /// The stop precedes the start after concurrent edits; the user should fix
    /// the times.
    pub needs_attention: bool,
    /// Measured time, counting up to now while running.
    pub duration_ms: u64,
}

impl EntryRecord {
    pub(crate) fn new(view: &TimeEntryView<'_>, now: Timestamp) -> Self {
        Self {
            id: ids::encode(view.id().0),
            task_id: ids::encode(view.task_id().0),
            started_at_ms: view.started_at().map(|Timestamp(at)| at),
            stopped_at_ms: view.stopped_at().map(|Timestamp(at)| at),
            is_running: view.is_running(),
            is_stop_derived: view.is_stop_derived(),
            needs_attention: view.needs_attention(),
            duration_ms: millis(view.duration(now)),
        }
    }
}

fn millis(duration: Duration) -> u64 {
    u64::try_from(duration.as_millis()).unwrap_or(u64::MAX)
}

#[cfg(test)]
mod tests {
    use trackdo_core::env::Clock;
    use trackdo_core::hlc::{DeviceId, Hlc};
    use trackdo_core::replica::Replica;
    use trackdo_core::task::{TaskChange, TaskId};
    use trackdo_core::title::Title;

    use super::*;
    use crate::env::UuidV7;

    const DEVICE: DeviceId = DeviceId(1);
    const TASK: TaskId = TaskId(0x0192_8f3a_0000_7000_8000_0000_0000_0001);

    fn written(task: Task, change: TaskChange) -> Task {
        task.apply(&change, Hlc::new(1_000, 0, DEVICE))
    }

    #[test]
    fn task_view_carries_title_and_status() {
        let task = written(
            written(
                Task::empty(TASK),
                TaskChange::Title(Title::new("milk").unwrap()),
            ),
            TaskChange::Status(TaskStatus::Done),
        );

        let view = TaskRecord::new(&task, true, Duration::from_millis(1_500));

        assert_eq!(
            view,
            TaskRecord {
                id: ids::encode(TASK.0),
                title: Some("milk".to_owned()),
                is_done: true,
                is_in_progress: true,
                total_ms: 1_500,
            }
        );
    }

    #[test]
    fn task_view_of_untitled_task_has_no_title() {
        let view = TaskRecord::new(&Task::empty(TASK), false, Duration::ZERO);

        assert_eq!(view.title, None);
        assert!(!view.is_done);
    }

    #[test]
    fn entry_view_reports_running_timer_up_to_now() {
        let mut replica = test_replica();
        let task = replica.create("work").unwrap();
        replica.start(task).unwrap();
        let running = replica.running_entry().unwrap();

        let view = EntryRecord::new(&running, Timestamp(NOW + 2_000));

        assert_eq!(
            view,
            EntryRecord {
                id: ids::encode(running.id().0),
                task_id: ids::encode(task.0),
                started_at_ms: Some(NOW),
                stopped_at_ms: None,
                is_running: true,
                is_stop_derived: false,
                needs_attention: false,
                duration_ms: 2_000,
            }
        );
    }

    #[test]
    fn entry_view_reports_stopped_interval() {
        let mut replica = test_replica();
        let task = replica.create("work").unwrap();
        let entry = replica
            .add_entry(task, Timestamp(NOW - 500), Timestamp(NOW - 100))
            .unwrap();
        let stopped = replica.entries_for(task)[0];
        assert_eq!(stopped.id(), entry);

        let view = EntryRecord::new(&stopped, Timestamp(NOW));

        assert_eq!(view.started_at_ms, Some(NOW - 500));
        assert_eq!(view.stopped_at_ms, Some(NOW - 100));
        assert!(!view.is_running);
        assert_eq!(view.duration_ms, 400);
    }

    #[test]
    fn durations_beyond_u64_millis_saturate() {
        assert_eq!(millis(Duration::MAX), u64::MAX);
    }

    const NOW: u64 = 1_730_000_000_000;

    struct FixedClock;

    impl Clock for FixedClock {
        fn now_millis(&self) -> u64 {
            NOW
        }
    }

    fn test_replica() -> Replica<FixedClock, UuidV7> {
        Replica::new(DEVICE, FixedClock, UuidV7)
    }
}
