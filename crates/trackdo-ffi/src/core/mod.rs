//! Commands and queries on the replica, in FFI terms: string ids, Unix
//! milliseconds and owned records.

mod push;
mod remote;
mod state;

pub use push::PushOutcome;
pub use remote::{EventOutcome, SnapshotOutcome};

use trackdo_core::env::{Clock, IdGen};
use trackdo_core::hlc::DeviceId;
use trackdo_core::replica::Replica;
use trackdo_core::task::{Task, TaskId};
use trackdo_core::time_entry::{TimeEntryId, Timestamp};

use crate::error::FfiError;
use crate::ids;
use crate::views::{EntryRecord, TaskRecord};

/// A replica plus the clock that dates its queries.
pub(crate) struct Core<C, G> {
    pub(super) replica: Replica<C, G>,
    clock: C,
}

impl<C: Clock + Clone, G: IdGen> Core<C, G> {
    pub(crate) fn new(device: DeviceId, clock: C, ids: G) -> Self {
        Self {
            replica: Replica::new(device, clock.clone(), ids),
            clock,
        }
    }

    pub(crate) fn create(&mut self, title: &str) -> Result<String, FfiError> {
        let id = self.replica.create(title)?;
        Ok(ids::encode(id.0))
    }

    pub(crate) fn rename(&mut self, task_id: &str, title: &str) -> Result<(), FfiError> {
        Ok(self.replica.rename(task(task_id)?, title)?)
    }

    pub(crate) fn complete(&mut self, task_id: &str) -> Result<(), FfiError> {
        Ok(self.replica.complete(task(task_id)?)?)
    }

    pub(crate) fn reopen(&mut self, task_id: &str) -> Result<(), FfiError> {
        Ok(self.replica.reopen(task(task_id)?)?)
    }

    pub(crate) fn delete(&mut self, task_id: &str) -> Result<(), FfiError> {
        Ok(self.replica.delete(task(task_id)?)?)
    }

    pub(crate) fn start(&mut self, task_id: &str) -> Result<String, FfiError> {
        let id = self.replica.start(task(task_id)?)?;
        Ok(ids::encode(id.0))
    }

    pub(crate) fn stop(&mut self, entry_id: &str) -> Result<(), FfiError> {
        Ok(self.replica.stop(entry(entry_id)?)?)
    }

    pub(crate) fn edit_times(
        &mut self,
        entry_id: &str,
        started_at_ms: u64,
        stopped_at_ms: Option<u64>,
    ) -> Result<(), FfiError> {
        Ok(self.replica.edit_times(
            entry(entry_id)?,
            Timestamp(started_at_ms),
            stopped_at_ms.map(Timestamp),
        )?)
    }

    pub(crate) fn delete_entry(&mut self, entry_id: &str) -> Result<(), FfiError> {
        Ok(self.replica.delete_entry(entry(entry_id)?)?)
    }

    pub(crate) fn add_entry(
        &mut self,
        task_id: &str,
        started_at_ms: u64,
        stopped_at_ms: u64,
    ) -> Result<String, FfiError> {
        let id = self.replica.add_entry(
            task(task_id)?,
            Timestamp(started_at_ms),
            Timestamp(stopped_at_ms),
        )?;
        Ok(ids::encode(id.0))
    }

    /// Tasks that are not deleted, oldest first since ids are UUIDv7. A task
    /// below a deleted one counts as deleted too.
    pub(crate) fn tasks(&self) -> Vec<TaskRecord> {
        let now = self.now();
        let hierarchy = self.replica.hierarchy();
        self.replica
            .tasks()
            .filter(|task| !hierarchy.is_deleted(task.id()))
            .map(|task| self.task_record(task, now))
            .collect()
    }

    pub(crate) fn running_entry(&self) -> Option<EntryRecord> {
        let now = self.now();
        self.replica
            .running_entry()
            .map(|view| EntryRecord::new(&view, now))
    }

    /// Entries of the task that are not deleted, by start time.
    pub(crate) fn entries_for(&self, task_id: &str) -> Result<Vec<EntryRecord>, FfiError> {
        let now = self.now();
        Ok(self
            .replica
            .entries_for(task(task_id)?)
            .iter()
            .map(|view| EntryRecord::new(view, now))
            .collect())
    }

    fn task_record(&self, task: &Task, now: Timestamp) -> TaskRecord {
        TaskRecord::new(
            task,
            self.replica.is_in_progress(task.id()),
            self.replica.task_total(task.id(), now),
        )
    }

    fn now(&self) -> Timestamp {
        Timestamp(self.clock.now_millis())
    }
}

fn task(id: &str) -> Result<TaskId, FfiError> {
    ids::decode(id).map(TaskId)
}

fn entry(id: &str) -> Result<TimeEntryId, FfiError> {
    ids::decode(id).map(TimeEntryId)
}

#[cfg(test)]
pub(crate) mod tests {
    use std::sync::Arc;
    use std::sync::atomic::{AtomicU64, Ordering};

    use super::*;
    use crate::env::UuidV7;

    const NOW: u64 = 1_730_000_000_000;

    #[derive(Clone)]
    pub(crate) struct TestClock(Arc<AtomicU64>);

    impl TestClock {
        pub(crate) fn advance(&self, millis: u64) {
            self.0.fetch_add(millis, Ordering::SeqCst);
        }
    }

    impl Clock for TestClock {
        fn now_millis(&self) -> u64 {
            self.0.load(Ordering::SeqCst)
        }
    }

    pub(crate) fn core() -> (Core<TestClock, UuidV7>, TestClock) {
        let clock = TestClock(Arc::new(AtomicU64::new(NOW)));
        (Core::new(DeviceId(1), clock.clone(), UuidV7), clock)
    }

    #[test]
    fn created_task_is_listed_as_todo() {
        let (mut core, _) = core();

        let id = core.create("buy milk").unwrap();

        let tasks = core.tasks();
        assert_eq!(tasks.len(), 1);
        assert_eq!(tasks[0].id, id);
        assert_eq!(tasks[0].title.as_deref(), Some("buy milk"));
        assert!(!tasks[0].is_done);
        assert!(!tasks[0].is_in_progress);
    }

    #[test]
    fn tasks_are_listed_in_creation_order() {
        let (mut core, _) = core();

        let first = core.create("a").unwrap();
        let second = core.create("b").unwrap();

        let ids: Vec<_> = core.tasks().into_iter().map(|task| task.id).collect();
        assert_eq!(ids, [first, second]);
    }

    #[test]
    fn rename_complete_and_reopen_update_the_listing() {
        let (mut core, _) = core();
        let id = core.create("a").unwrap();

        core.rename(&id, "b").unwrap();
        core.complete(&id).unwrap();
        let done = core.tasks()[0].clone();
        core.reopen(&id).unwrap();

        assert_eq!(done.title.as_deref(), Some("b"));
        assert!(done.is_done);
        assert!(!core.tasks()[0].is_done);
    }

    #[test]
    fn deleted_tasks_are_not_listed() {
        let (mut core, _) = core();
        let id = core.create("a").unwrap();

        core.delete(&id).unwrap();

        assert!(core.tasks().is_empty());
    }

    #[test]
    fn tasks_below_a_deleted_task_are_not_listed() {
        let (mut core, _) = core();
        let parent = core.create("project").unwrap();
        let child = core.create("step").unwrap();
        core.replica
            .set_parent(task(&child).unwrap(), Some(task(&parent).unwrap()))
            .unwrap();

        core.delete(&parent).unwrap();

        assert!(core.tasks().is_empty());
    }

    #[test]
    fn running_timer_counts_up_to_now() {
        let (mut core, clock) = core();
        let task = core.create("work").unwrap();

        let entry = core.start(&task).unwrap();
        clock.advance(1_500);

        let running = core.running_entry().unwrap();
        assert_eq!(running.id, entry);
        assert_eq!(running.task_id, task);
        assert_eq!(running.duration_ms, 1_500);
        let listed = &core.tasks()[0];
        assert!(listed.is_in_progress);
        assert_eq!(listed.total_ms, 1_500);
    }

    #[test]
    fn stopped_timer_is_listed_for_its_task() {
        let (mut core, clock) = core();
        let task = core.create("work").unwrap();
        let entry = core.start(&task).unwrap();
        clock.advance(700);

        core.stop(&entry).unwrap();
        clock.advance(10_000);

        assert_eq!(core.running_entry(), None);
        let entries = core.entries_for(&task).unwrap();
        assert_eq!(entries.len(), 1);
        assert_eq!(entries[0].started_at_ms, Some(NOW));
        assert_eq!(entries[0].stopped_at_ms, Some(NOW + 700));
        assert_eq!(core.tasks()[0].total_ms, 700);
    }

    #[test]
    fn past_entries_can_be_added_edited_and_deleted() {
        let (mut core, _) = core();
        let task = core.create("work").unwrap();

        let entry = core.add_entry(&task, NOW - 5_000, NOW - 1_000).unwrap();
        core.edit_times(&entry, NOW - 6_000, Some(NOW - 2_000))
            .unwrap();
        let edited = core.entries_for(&task).unwrap();
        core.delete_entry(&entry).unwrap();

        assert_eq!(edited[0].id, entry);
        assert_eq!(edited[0].started_at_ms, Some(NOW - 6_000));
        assert_eq!(edited[0].stopped_at_ms, Some(NOW - 2_000));
        assert!(core.entries_for(&task).unwrap().is_empty());
    }

    #[test]
    fn malformed_ids_are_rejected() {
        let (mut core, _) = core();

        assert_eq!(
            core.start("nope"),
            Err(FfiError::InvalidId {
                id: "nope".to_owned()
            })
        );
        assert!(matches!(
            core.entries_for("nope"),
            Err(FfiError::InvalidId { .. })
        ));
    }

    #[test]
    fn command_errors_are_reported() {
        let (mut core, _) = core();
        let unknown = ids::encode(42);

        assert_eq!(core.create("  "), Err(FfiError::EmptyTitle));
        assert_eq!(
            core.complete(&unknown),
            Err(FfiError::TaskNotFound { id: unknown })
        );
    }
}
