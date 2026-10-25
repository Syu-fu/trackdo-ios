//! Owned snapshots of tasks and time entries for display.

use std::time::Duration;

use trackdo_core::date::Date;
use trackdo_core::tag::Tag;
use trackdo_core::task::{Task, TaskId, TaskPriority, TaskStatus};
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
    pub priority: Priority,
    /// `None` while the task has no note.
    pub note: Option<String>,
    pub due: Option<CalendarDate>,
    pub scheduled_at_ms: Option<u64>,
    /// The parent in effect, which may differ from the one written when
    /// concurrent moves made a cycle; `None` at the top level.
    pub parent_id: Option<String>,
    /// Tags on the task that are not deleted, by name.
    pub tags: Vec<TagRecord>,
}

/// Where a task sits and what it carries beyond its own fields.
pub(crate) struct TaskContext {
    pub(crate) parent: Option<TaskId>,
    pub(crate) tags: Vec<TagRecord>,
    pub(crate) is_in_progress: bool,
    pub(crate) total: Duration,
}

impl TaskRecord {
    pub(crate) fn new(task: &Task, context: TaskContext) -> Self {
        Self {
            id: ids::encode(task.id().0),
            title: task.title().map(|title| title.as_str().to_owned()),
            is_done: task.status() == TaskStatus::Done,
            is_in_progress: context.is_in_progress,
            total_ms: millis(context.total),
            priority: task.priority().into(),
            note: task.note().map(|note| note.as_str().to_owned()),
            due: task.due().map(CalendarDate::from),
            scheduled_at_ms: task.scheduled_at().map(|Timestamp(at)| at),
            parent_id: context.parent.map(|parent| ids::encode(parent.0)),
            tags: context.tags,
        }
    }
}

/// Ordered from least to most urgent.
#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Enum)]
pub enum Priority {
    None,
    Low,
    Medium,
    High,
}

impl From<TaskPriority> for Priority {
    fn from(priority: TaskPriority) -> Self {
        match priority {
            TaskPriority::None => Self::None,
            TaskPriority::Low => Self::Low,
            TaskPriority::Medium => Self::Medium,
            TaskPriority::High => Self::High,
        }
    }
}

impl From<Priority> for TaskPriority {
    fn from(priority: Priority) -> Self {
        match priority {
            Priority::None => Self::None,
            Priority::Low => Self::Low,
            Priority::Medium => Self::Medium,
            Priority::High => Self::High,
        }
    }
}

/// A day without a time zone, so a due date stays on the same day wherever
/// the device is.
#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Record)]
pub struct CalendarDate {
    pub year: u16,
    pub month: u8,
    pub day: u8,
}

impl From<Date> for CalendarDate {
    fn from(date: Date) -> Self {
        Self {
            year: date.year(),
            month: date.month(),
            day: date.day(),
        }
    }
}

/// A tag that is not deleted and whose name has been received.
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct TagRecord {
    pub id: String,
    pub name: String,
}

impl TagRecord {
    /// `None` for a deleted tag or one whose name has not arrived yet.
    pub(crate) fn new(tag: &Tag) -> Option<Self> {
        let name = tag.name().filter(|_| !tag.is_deleted())?;
        Some(Self {
            id: ids::encode(tag.id().0),
            name: name.as_str().to_owned(),
        })
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
    use trackdo_core::note::Note;
    use trackdo_core::replica::Replica;
    use trackdo_core::tag::{TagChange, TagId, TagName};
    use trackdo_core::task::TaskChange;
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

        let view = TaskRecord::new(
            &task,
            TaskContext {
                is_in_progress: true,
                total: Duration::from_millis(1_500),
                ..context()
            },
        );

        assert_eq!(
            view,
            TaskRecord {
                id: ids::encode(TASK.0),
                title: Some("milk".to_owned()),
                is_done: true,
                is_in_progress: true,
                total_ms: 1_500,
                priority: Priority::None,
                note: None,
                due: None,
                scheduled_at_ms: None,
                parent_id: None,
                tags: Vec::new(),
            }
        );
    }

    #[test]
    fn task_view_of_untitled_task_has_no_title() {
        let view = TaskRecord::new(&Task::empty(TASK), context());

        assert_eq!(view.title, None);
        assert!(!view.is_done);
    }

    #[test]
    fn task_view_carries_planning_fields() {
        let changes = [
            TaskChange::Priority(TaskPriority::High),
            TaskChange::Note(Note::new("call first").unwrap()),
            TaskChange::Due(Some(Date::new(2026, 10, 31).unwrap())),
            TaskChange::ScheduledAt(Some(Timestamp(NOW))),
        ];
        let task = changes.into_iter().fold(Task::empty(TASK), written);
        let tag = TagRecord {
            id: ids::encode(9),
            name: "home".to_owned(),
        };

        let view = TaskRecord::new(
            &task,
            TaskContext {
                parent: Some(TaskId(8)),
                tags: vec![tag.clone()],
                ..context()
            },
        );

        assert_eq!(view.priority, Priority::High);
        assert_eq!(view.note.as_deref(), Some("call first"));
        assert_eq!(
            view.due,
            Some(CalendarDate {
                year: 2026,
                month: 10,
                day: 31
            })
        );
        assert_eq!(view.scheduled_at_ms, Some(NOW));
        assert_eq!(view.parent_id, Some(ids::encode(8)));
        assert_eq!(view.tags, [tag]);
    }

    #[test]
    fn priorities_convert_both_ways() {
        let pairs = [
            (TaskPriority::None, Priority::None),
            (TaskPriority::Low, Priority::Low),
            (TaskPriority::Medium, Priority::Medium),
            (TaskPriority::High, Priority::High),
        ];
        for (core, ffi) in pairs {
            assert_eq!(Priority::from(core), ffi);
            assert_eq!(TaskPriority::from(ffi), core);
        }
    }

    #[test]
    fn tag_view_needs_a_name_and_a_live_tag() {
        let hlc = Hlc::new(1_000, 0, DEVICE);
        let named =
            Tag::empty(TagId(9)).apply(&TagChange::Name(TagName::new("home").unwrap()), hlc);
        let deleted = named.apply(&TagChange::Deleted(true), Hlc::new(2_000, 0, DEVICE));

        assert_eq!(
            TagRecord::new(&named),
            Some(TagRecord {
                id: ids::encode(9),
                name: "home".to_owned()
            })
        );
        assert_eq!(TagRecord::new(&Tag::empty(TagId(9))), None);
        assert_eq!(TagRecord::new(&deleted), None);
    }

    fn context() -> TaskContext {
        TaskContext {
            parent: None,
            tags: Vec::new(),
            is_in_progress: false,
            total: Duration::ZERO,
        }
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
