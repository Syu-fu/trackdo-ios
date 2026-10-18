//! UniFFI bindings of trackdo-core for the iOS client.

mod core;
mod env;
mod error;
mod ids;
mod views;
mod wire;

use std::sync::{Arc, Mutex, MutexGuard};

use trackdo_core::hlc::DeviceId;
use uuid::Uuid;

use crate::core::Core;
use crate::env::{SystemClock, UuidV7};

pub use crate::core::{EventOutcome, PushOutcome, SnapshotOutcome};
pub use error::FfiError;
pub use views::{EntryRecord, TaskRecord};

uniffi::setup_scaffolding!();

/// The local replica. Calls are synchronous and only touch memory; the host
/// serializes them and persists the state after every change.
#[derive(uniffi::Object)]
pub struct TrackdoCore {
    core: Mutex<Core<SystemClock, UuidV7>>,
}

#[uniffi::export]
impl TrackdoCore {
    /// A replica for a new install, with a new random device id.
    #[uniffi::constructor]
    pub fn new() -> Arc<Self> {
        let device = DeviceId(Uuid::new_v4().as_u128());
        Arc::new(Self {
            core: Mutex::new(Core::new(device, SystemClock, UuidV7)),
        })
    }

    /// Returns the new task's id.
    pub fn create(&self, title: String) -> Result<String, FfiError> {
        self.lock().create(&title)
    }

    pub fn rename(&self, task_id: String, title: String) -> Result<(), FfiError> {
        self.lock().rename(&task_id, &title)
    }

    /// Also stops the task's running timer.
    pub fn complete(&self, task_id: String) -> Result<(), FfiError> {
        self.lock().complete(&task_id)
    }

    pub fn reopen(&self, task_id: String) -> Result<(), FfiError> {
        self.lock().reopen(&task_id)
    }

    /// Also stops the task's running timer.
    pub fn delete(&self, task_id: String) -> Result<(), FfiError> {
        self.lock().delete(&task_id)
    }

    /// Starts a timer, stopping any other one; reopens a done task. Returns
    /// the new entry's id.
    pub fn start(&self, task_id: String) -> Result<String, FfiError> {
        self.lock().start(&task_id)
    }

    pub fn stop(&self, entry_id: String) -> Result<(), FfiError> {
        self.lock().stop(&entry_id)
    }

    /// `stopped_at_ms` is `None` only to keep a running entry running.
    pub fn edit_times(
        &self,
        entry_id: String,
        started_at_ms: u64,
        stopped_at_ms: Option<u64>,
    ) -> Result<(), FfiError> {
        self.lock()
            .edit_times(&entry_id, started_at_ms, stopped_at_ms)
    }

    pub fn delete_entry(&self, entry_id: String) -> Result<(), FfiError> {
        self.lock().delete_entry(&entry_id)
    }

    /// Records past work. Returns the new entry's id.
    pub fn add_entry(
        &self,
        task_id: String,
        started_at_ms: u64,
        stopped_at_ms: u64,
    ) -> Result<String, FfiError> {
        self.lock()
            .add_entry(&task_id, started_at_ms, stopped_at_ms)
    }

    /// Tasks that are not deleted, oldest first.
    pub fn tasks(&self) -> Vec<TaskRecord> {
        self.lock().tasks()
    }

    pub fn running_entry(&self) -> Option<EntryRecord> {
        self.lock().running_entry()
    }

    /// Entries of the task that are not deleted, by start time.
    pub fn entries_for(&self, task_id: String) -> Result<Vec<EntryRecord>, FfiError> {
        self.lock().entries_for(&task_id)
    }

    /// Body of the next `POST /ops`, or `None` when nothing is pending.
    pub fn next_push_batch(&self) -> Option<Vec<u8>> {
        self.lock().next_push_batch()
    }

    /// Applies a `POST /ops` response; persist the state afterwards.
    pub fn handle_push_response(&self, status: u16, body: Vec<u8>) -> PushOutcome {
        self.lock().handle_push_response(status, &body)
    }

    /// No server log is known yet: fetch `GET /snapshot` before streaming.
    pub fn needs_snapshot(&self) -> bool {
        self.lock().needs_snapshot()
    }

    /// `Last-Event-ID` for `GET /events`, or `None` to stream from the start.
    pub fn last_event_id(&self) -> Option<String> {
        self.lock().last_event_id()
    }

    /// Applies an `op` event; persist the state afterwards.
    pub fn handle_event(&self, id: String, data: Vec<u8>) -> EventOutcome {
        self.lock().handle_event(&id, &data)
    }

    /// Merges a `GET /snapshot` body; persist the state afterwards.
    pub fn apply_snapshot(&self, body: Vec<u8>) -> SnapshotOutcome {
        self.lock().apply_snapshot(&body)
    }
}

impl TrackdoCore {
    /// A panic while holding the lock leaves the replica consistent, since
    /// every core command validates before it changes anything.
    fn lock(&self) -> MutexGuard<'_, Core<SystemClock, UuidV7>> {
        self.core
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner())
    }
}

/// Version of the sync protocol these bindings speak, sent as the
/// `Trackdo-Protocol` header and compared with `GET /healthz`.
#[uniffi::export]
pub fn protocol_version() -> u32 {
    trackdo_protocol::PROTOCOL_VERSION
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn reports_protocol_version_of_trackdo_protocol() {
        assert_eq!(protocol_version(), 3);
    }

    #[test]
    fn fresh_cores_edit_independently() {
        let first = TrackdoCore::new();
        let second = TrackdoCore::new();

        let id = first.create("a".to_owned()).unwrap();
        first.start(id.clone()).unwrap();

        assert_eq!(first.tasks()[0].id, id);
        assert!(first.running_entry().is_some());
        assert!(second.tasks().is_empty());
        assert!(first.entries_for(id).unwrap()[0].is_running);
    }

    #[test]
    fn every_command_reaches_the_replica() {
        let core = TrackdoCore::new();
        let task = core.create("a".to_owned()).unwrap();
        let entry = core.start(task.clone()).unwrap();
        core.stop(entry.clone()).unwrap();
        let stopped = core.entries_for(task.clone()).unwrap()[0].clone();
        let started = stopped.started_at_ms.unwrap();

        core.rename(task.clone(), "b".to_owned()).unwrap();
        core.complete(task.clone()).unwrap();
        core.reopen(task.clone()).unwrap();
        core.edit_times(entry.clone(), started - 1, stopped.stopped_at_ms)
            .unwrap();
        let past = core
            .add_entry(task.clone(), started - 100, started - 50)
            .unwrap();
        core.delete_entry(entry).unwrap();
        let entries = core.entries_for(task.clone()).unwrap();
        core.delete(task).unwrap();

        assert_eq!(entries.len(), 1);
        assert_eq!(entries[0].id, past);
        assert!(core.tasks().is_empty());
    }

    #[test]
    fn acknowledged_batch_is_not_sent_again() {
        let core = TrackdoCore::new();
        core.create("a".to_owned()).unwrap();
        let batch = core.next_push_batch().unwrap();
        let sent: Vec<serde_json::Value> = serde_json::from_slice(&batch).unwrap();
        let accepted: Vec<_> = sent.iter().map(|op| op["op_id"].clone()).collect();
        let response = serde_json::json!({ "accepted": accepted });

        let outcome = core.handle_push_response(200, serde_json::to_vec(&response).unwrap());

        assert_eq!(outcome, PushOutcome::Accepted);
        assert_eq!(core.next_push_batch(), None);
    }

    #[test]
    fn snapshot_and_events_move_the_stream_position() {
        let log = "01928f30-0000-7000-8000-000000000001";
        let core = TrackdoCore::new();
        let other = TrackdoCore::new();
        other.create("a".to_owned()).unwrap();
        let ops: Vec<serde_json::Value> =
            serde_json::from_slice(&other.next_push_batch().unwrap()).unwrap();
        let snapshot =
            serde_json::json!({ "log_id": log, "seq": 0, "tasks": [], "time_entries": [] });
        assert!(core.needs_snapshot());

        let applied = core.apply_snapshot(serde_json::to_vec(&snapshot).unwrap());
        let received = core.handle_event(format!("{log}:1"), serde_json::to_vec(&ops[0]).unwrap());

        assert_eq!(applied, SnapshotOutcome::Applied { needs_push: false });
        assert_eq!(received, EventOutcome::Applied { needs_push: false });
        assert!(!core.needs_snapshot());
        assert_eq!(core.last_event_id(), Some(format!("{log}:1")));
    }
}
