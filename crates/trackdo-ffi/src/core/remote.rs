//! Receiving operations from `GET /events` and state from `GET /snapshot`.
//!
//! The host fetches a snapshot while [`Core::needs_snapshot`], connects the
//! event stream from [`Core::last_event_id`] and hands every `op` event to
//! [`Core::handle_event`]. Whenever an outcome reports `needs_push`, healing
//! or a replaced server log queued ops to send.

use std::collections::HashSet;

use trackdo_core::env::{Clock, IdGen};
use trackdo_core::op::{Op, OpId};
use trackdo_core::replica::{RemoteError, Snapshot};
use trackdo_protocol::event::EventId;
use trackdo_protocol::op::OpDto;
use trackdo_protocol::snapshot::SnapshotDto;

use super::Core;
use crate::ids;

/// What the host should do after receiving an `op` event.
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Enum)]
pub enum EventOutcome {
    /// Applied, or ignored as already seen. `needs_push` when healing queued
    /// ops to send.
    Applied { needs_push: bool },
    /// The event belongs to another log than this replica's: drop the
    /// stream, fetch a snapshot and reconnect.
    ResyncRequired,
    /// The event is malformed or overflows the logical clock. Nothing was
    /// applied, unless only healing overflowed, which the next event retries.
    /// Reconnect after backing off.
    Invalid { message: String },
    /// The server sent a time entry under another task than the one it
    /// belongs to, which a correct server never does. Nothing was applied;
    /// report it.
    TaskMismatch {
        entry_id: String,
        expected_task_id: String,
        actual_task_id: String,
    },
}

/// What the host should do after a `GET /snapshot` response body.
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Enum)]
pub enum SnapshotOutcome {
    /// Merged. `needs_push` when healing, or writes a replaced server log
    /// lacks, queued ops to send.
    Applied { needs_push: bool },
    /// As [`EventOutcome::Invalid`].
    Invalid { message: String },
    /// As [`EventOutcome::TaskMismatch`]; nothing was applied.
    TaskMismatch {
        entry_id: String,
        expected_task_id: String,
        actual_task_id: String,
    },
}

impl<C: Clock + Clone, G: IdGen> Core<C, G> {
    /// No log is known yet, so the stream cannot be resumed: fetch a snapshot
    /// first.
    pub(crate) fn needs_snapshot(&self) -> bool {
        self.replica.log_id().is_none()
    }

    /// `Last-Event-ID` to connect `GET /events` with, or `None` to stream
    /// from the start of the log.
    pub(crate) fn last_event_id(&self) -> Option<String> {
        let log_id = self.replica.log_id()?;
        let seq = self.replica.last_seq()?;
        Some(EventId { log_id, seq }.to_string())
    }

    /// Applies the `data` of an `op` event with SSE id `id`.
    pub(crate) fn handle_event(&mut self, id: &str, data: &[u8]) -> EventOutcome {
        let event_id = match id.parse::<EventId>() {
            Ok(event_id) => event_id,
            Err(error) => {
                return EventOutcome::Invalid {
                    message: error.to_string(),
                };
            }
        };
        if self.replica.log_id() != Some(event_id.log_id) {
            return EventOutcome::ResyncRequired;
        }
        let op = match decode_op(data) {
            Ok(op) => op,
            Err(message) => return EventOutcome::Invalid { message },
        };
        let before = self.pending_op_ids();
        match self.replica.apply_remote(&op, event_id.seq) {
            Ok(()) => EventOutcome::Applied {
                needs_push: self.queued_since(&before),
            },
            Err(RemoteError::TaskMismatch {
                entry,
                expected,
                actual,
            }) => EventOutcome::TaskMismatch {
                entry_id: ids::encode(entry.0),
                expected_task_id: ids::encode(expected.0),
                actual_task_id: ids::encode(actual.0),
            },
            Err(RemoteError::Clock(error)) => EventOutcome::Invalid {
                message: error.to_string(),
            },
        }
    }

    /// Merges a `GET /snapshot` response body.
    pub(crate) fn apply_snapshot(&mut self, body: &[u8]) -> SnapshotOutcome {
        let snapshot = match decode_snapshot(body) {
            Ok(snapshot) => snapshot,
            Err(message) => return SnapshotOutcome::Invalid { message },
        };
        let before = self.pending_op_ids();
        match self.replica.apply_snapshot(&snapshot) {
            Ok(()) => SnapshotOutcome::Applied {
                needs_push: self.queued_since(&before),
            },
            Err(RemoteError::TaskMismatch {
                entry,
                expected,
                actual,
            }) => SnapshotOutcome::TaskMismatch {
                entry_id: ids::encode(entry.0),
                expected_task_id: ids::encode(expected.0),
                actual_task_id: ids::encode(actual.0),
            },
            Err(RemoteError::Clock(error)) => SnapshotOutcome::Invalid {
                message: error.to_string(),
            },
        }
    }

    fn pending_op_ids(&self) -> HashSet<OpId> {
        self.replica
            .pending_ops()
            .iter()
            .map(|op| op.op_id)
            .collect()
    }

    /// Some pending op was not pending at `before`. Counting would miss a
    /// healing stop queued by the same event that acknowledged an own op.
    fn queued_since(&self, before: &HashSet<OpId>) -> bool {
        self.replica
            .pending_ops()
            .iter()
            .any(|op| !before.contains(&op.op_id))
    }
}

fn decode_op(data: &[u8]) -> Result<Op, String> {
    let dto: OpDto = serde_json::from_slice(data).map_err(|error| error.to_string())?;
    Op::try_from(dto).map_err(|error| error.to_string())
}

fn decode_snapshot(body: &[u8]) -> Result<Snapshot, String> {
    let dto: SnapshotDto = serde_json::from_slice(body).map_err(|error| error.to_string())?;
    Snapshot::try_from(dto).map_err(|error| error.to_string())
}

#[cfg(test)]
mod tests {
    use serde_json::{Value, json};

    use super::*;
    use crate::core::tests::{TestClock, core as new_core};
    use crate::env::UuidV7;

    const LOG: &str = "01928f30-0000-7000-8000-000000000001";
    const OTHER_LOG: &str = "01928f30-0000-7000-8000-000000000002";

    fn snapshot_body(log_id: &str, seq: Option<u64>) -> Vec<u8> {
        let body =
            json!({ "log_id": log_id, "seq": seq, "tasks": [], "time_entries": [], "tags": [] });
        serde_json::to_vec(&body).unwrap()
    }

    /// Ops another device has pending, as the server would broadcast them.
    fn ops_of(other: &Core<TestClock, UuidV7>) -> Vec<Value> {
        serde_json::from_slice(&other.next_push_batch().unwrap()).unwrap()
    }

    fn event_data(op: &Value) -> Vec<u8> {
        serde_json::to_vec(op).unwrap()
    }

    fn synced() -> Core<TestClock, UuidV7> {
        let (mut core, _) = new_core();
        core.apply_snapshot(&snapshot_body(LOG, None));
        core
    }

    fn acknowledge_all(core: &mut Core<TestClock, UuidV7>) {
        let ids: Vec<Value> = ops_of(core).iter().map(|op| op["op_id"].clone()).collect();
        let body = serde_json::to_vec(&json!({ "accepted": ids })).unwrap();
        core.handle_push_response(200, &body);
    }

    #[test]
    fn fresh_replica_needs_snapshot_before_streaming() {
        let (core, _) = new_core();

        assert!(core.needs_snapshot());
        assert_eq!(core.last_event_id(), None);
    }

    #[test]
    fn snapshot_sets_stream_position() {
        let (mut core, _) = new_core();

        let outcome = core.apply_snapshot(&snapshot_body(LOG, Some(42)));

        assert_eq!(outcome, SnapshotOutcome::Applied { needs_push: false });
        assert!(!core.needs_snapshot());
        assert_eq!(core.last_event_id(), Some(format!("{LOG}:42")));
    }

    #[test]
    fn snapshot_of_empty_log_has_no_position_to_resume_from() {
        let core = synced();

        assert!(!core.needs_snapshot());
        assert_eq!(core.last_event_id(), None);
    }

    #[test]
    fn snapshot_lacking_acknowledged_writes_queues_them_again() {
        let (mut core, _) = new_core();
        core.create("a").unwrap();
        acknowledge_all(&mut core);

        let outcome = core.apply_snapshot(&snapshot_body(LOG, None));

        assert_eq!(outcome, SnapshotOutcome::Applied { needs_push: true });
        assert!(core.next_push_batch().is_some());
    }

    #[test]
    fn malformed_snapshot_is_invalid() {
        let non_canonical = json!({
            "log_id": LOG, "seq": 1, "time_entries": [], "tags": [],
            "tasks": [{
                "id": LOG, "status": null, "deleted": null,
                "title": { "value": " padded ", "hlc": { "wall_ms": 1, "counter": 0, "device": LOG } }
            }]
        });
        for body in [b"{}".to_vec(), serde_json::to_vec(&non_canonical).unwrap()] {
            let (mut core, _) = new_core();

            let outcome = core.apply_snapshot(&body);

            assert!(
                matches!(outcome, SnapshotOutcome::Invalid { .. }),
                "{outcome:?}"
            );
            assert!(core.needs_snapshot());
        }
    }

    #[test]
    fn event_applies_remote_op_and_advances_position() {
        let mut core = synced();
        let (mut other, _) = new_core();
        let task = other.create("from other").unwrap();
        let ops = ops_of(&other);

        for (seq, op) in ops.iter().enumerate() {
            let outcome = core.handle_event(&format!("{LOG}:{}", seq + 1), &event_data(op));
            assert_eq!(outcome, EventOutcome::Applied { needs_push: false });
        }

        assert_eq!(core.tasks()[0].id, task);
        assert_eq!(core.tasks()[0].title.as_deref(), Some("from other"));
        assert_eq!(core.last_event_id(), Some(format!("{LOG}:{}", ops.len())));
    }

    #[test]
    fn echoed_own_op_needs_no_push() {
        let mut core = synced();
        core.create("a").unwrap();
        let ops = ops_of(&core);

        let outcome = core.handle_event(&format!("{LOG}:1"), &event_data(&ops[0]));

        assert_eq!(outcome, EventOutcome::Applied { needs_push: false });
        assert_eq!(ops_of(&core).len(), ops.len() - 1);
    }

    #[test]
    fn event_that_heals_timers_needs_push() {
        let mut core = synced();
        let mine = core.create("mine").unwrap();
        core.start(&mine).unwrap();
        acknowledge_all(&mut core);
        let (mut other, clock) = new_core();
        clock.advance(1_000);
        let theirs = other.create("theirs").unwrap();
        other.start(&theirs).unwrap();

        let outcomes: Vec<_> = ops_of(&other)
            .iter()
            .enumerate()
            .map(|(seq, op)| core.handle_event(&format!("{LOG}:{}", seq + 1), &event_data(op)))
            .collect();

        assert_eq!(
            outcomes.last(),
            Some(&EventOutcome::Applied { needs_push: true })
        );
        assert_eq!(core.running_entry().unwrap().task_id, theirs);
    }

    #[test]
    fn event_from_another_log_requires_resync() {
        let mut core = synced();
        let (mut other, _) = new_core();
        other.create("a").unwrap();
        let op = &ops_of(&other)[0];

        let outcome = core.handle_event(&format!("{OTHER_LOG}:1"), &event_data(op));

        assert_eq!(outcome, EventOutcome::ResyncRequired);
        assert!(core.tasks().is_empty());
    }

    #[test]
    fn event_before_any_snapshot_requires_resync() {
        let (mut core, _) = new_core();
        let (mut other, _) = new_core();
        other.create("a").unwrap();

        let outcome = core.handle_event(&format!("{LOG}:1"), &event_data(&ops_of(&other)[0]));

        assert_eq!(outcome, EventOutcome::ResyncRequired);
    }

    #[test]
    fn malformed_events_are_invalid() {
        let mut core = synced();
        let (mut other, _) = new_core();
        other.create("a").unwrap();
        let op = event_data(&ops_of(&other)[0]);

        for (id, data) in [
            ("7", op.as_slice()),
            (&format!("{LOG}:1"), b"{}".as_slice()),
        ] {
            let outcome = core.handle_event(id, data);

            assert!(
                matches!(outcome, EventOutcome::Invalid { .. }),
                "{outcome:?}"
            );
        }
        assert!(core.tasks().is_empty());
    }

    #[test]
    fn entry_moved_to_another_task_is_reported() {
        let mut core = synced();
        let task = core.create("a").unwrap();
        let entry = core.start(&task).unwrap();
        let mut moved = ops_of(&core)
            .into_iter()
            .find(|op| op["target"]["type"] == "time_entry")
            .unwrap();
        let other_task = ids::encode(42);
        moved["target"]["task_id"] = json!(other_task);

        let outcome = core.handle_event(&format!("{LOG}:1"), &event_data(&moved));

        assert_eq!(
            outcome,
            EventOutcome::TaskMismatch {
                entry_id: entry,
                expected_task_id: task,
                actual_task_id: other_task,
            }
        );
    }

    #[test]
    fn snapshot_moving_an_entry_to_another_task_is_reported() {
        let (mut core, _) = new_core();
        let task = core.create("a").unwrap();
        let entry = core.start(&task).unwrap();
        let other_task = ids::encode(42);
        let hlc = json!({ "wall_ms": 1, "counter": 0, "device": LOG });
        let body = json!({
            "log_id": LOG, "seq": 1, "tasks": [], "tags": [],
            "time_entries": [{
                "id": entry, "task_id": other_task, "stopped_at": null, "deleted": null,
                "started_at": { "value": 1, "hlc": hlc }
            }]
        });

        let outcome = core.apply_snapshot(&serde_json::to_vec(&body).unwrap());

        assert_eq!(
            outcome,
            SnapshotOutcome::TaskMismatch {
                entry_id: entry,
                expected_task_id: task,
                actual_task_id: other_task,
            }
        );
        assert!(core.needs_snapshot());
    }

    #[test]
    fn data_overflowing_the_clock_is_invalid() {
        let mut core = synced();
        let (mut other, _) = new_core();
        let task = other.create("a").unwrap();
        let mut op = ops_of(&other)[0].clone();
        op["hlc"]["counter"] = json!(u32::MAX);
        let overflowing = json!({
            "log_id": LOG, "seq": 1, "time_entries": [], "tags": [],
            "tasks": [{ "id": task, "title": null, "deleted": null, "status": {
                "value": "todo", "hlc": op["hlc"].clone()
            } }]
        });

        let event = core.handle_event(&format!("{LOG}:1"), &event_data(&op));
        let snapshot = core.apply_snapshot(&serde_json::to_vec(&overflowing).unwrap());

        assert!(matches!(event, EventOutcome::Invalid { .. }), "{event:?}");
        assert!(
            matches!(snapshot, SnapshotOutcome::Invalid { .. }),
            "{snapshot:?}"
        );
        assert!(core.tasks().is_empty());
    }
}
