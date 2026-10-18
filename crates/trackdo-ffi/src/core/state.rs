//! The replica's state as stored by the host between launches:
//! `{"format": 1, "state": ReplicaStateDto}`.
//!
//! `format` versions this file and is independent of the wire protocol.

use serde::{Deserialize, Serialize};
use trackdo_core::env::{Clock, IdGen};
use trackdo_core::replica::{Replica, ReplicaState};
use trackdo_protocol::state::ReplicaStateDto;

use super::Core;
use crate::error::FfiError;

const FORMAT: u32 = 1;

#[derive(Serialize, Deserialize)]
struct Stored {
    format: u32,
    state: ReplicaStateDto,
}

/// Read first, so a newer file is refused as such rather than as malformed.
#[derive(Deserialize)]
struct Format {
    format: u32,
}

impl<C: Clock + Clone, G: IdGen> Core<C, G> {
    /// Rebuilds a core from what [`Self::state_json`] returned.
    pub(crate) fn restore(json: &[u8], clock: C, ids: G) -> Result<Self, FfiError> {
        let Format { format } = serde_json::from_slice(json).map_err(invalid)?;
        if format != FORMAT {
            return Err(FfiError::UnsupportedStateFormat { format });
        }
        let Stored { state, .. } = serde_json::from_slice(json).map_err(invalid)?;
        let state = ReplicaState::try_from(state).map_err(invalid)?;
        Ok(Self {
            replica: Replica::restore(state, clock.clone(), ids),
            clock,
        })
    }

    pub(crate) fn state_json(&self) -> Vec<u8> {
        let stored = Stored {
            format: FORMAT,
            state: ReplicaStateDto::from(&self.replica.state()),
        };
        serde_json::to_vec(&stored).expect("the stored state always serializes")
    }
}

fn invalid(error: impl ToString) -> FfiError {
    FfiError::InvalidState {
        message: error.to_string(),
    }
}

#[cfg(test)]
mod tests {
    use serde_json::{Value, json};

    use super::*;
    use crate::core::tests::{TestClock, core as new_core};
    use crate::env::UuidV7;

    const LOG: &str = "01928f30-0000-7000-8000-000000000001";

    fn restore(json: &[u8]) -> Result<Core<TestClock, UuidV7>, FfiError> {
        let (_, clock) = new_core();
        Core::restore(json, clock, UuidV7)
    }

    fn stored(core: &Core<TestClock, UuidV7>) -> Value {
        serde_json::from_slice(&core.state_json()).unwrap()
    }

    #[test]
    fn state_is_wrapped_with_its_format() {
        let (core, _) = new_core();

        let stored = stored(&core);

        assert_eq!(stored["format"], json!(1));
        assert!(stored["state"]["hlc"].is_object());
    }

    #[test]
    fn restored_core_has_the_same_data_and_position() {
        let (mut core, _) = new_core();
        let snapshot = json!({ "log_id": LOG, "seq": 7, "tasks": [], "time_entries": [] });
        core.apply_snapshot(&serde_json::to_vec(&snapshot).unwrap());
        let task = core.create("a").unwrap();
        core.start(&task).unwrap();

        let restored = restore(&core.state_json()).unwrap();

        assert_eq!(restored.tasks(), core.tasks());
        assert_eq!(restored.running_entry(), core.running_entry());
        assert_eq!(restored.next_push_batch(), core.next_push_batch());
        assert_eq!(restored.last_event_id(), Some(format!("{LOG}:7")));
    }

    #[test]
    fn restored_core_keeps_its_device() {
        let (core, _) = new_core();
        let device = stored(&core)["state"]["hlc"]["device"].clone();
        let mut restored = restore(&core.state_json()).unwrap();

        restored.create("a").unwrap();

        let sent: Vec<Value> =
            serde_json::from_slice(&restored.next_push_batch().unwrap()).unwrap();
        assert_eq!(sent[0]["hlc"]["device"], device);
    }

    #[test]
    fn unknown_format_is_refused() {
        let (core, _) = new_core();
        let mut stored = stored(&core);
        stored["format"] = json!(2);

        let result = restore(&serde_json::to_vec(&stored).unwrap());

        assert!(matches!(
            result,
            Err(FfiError::UnsupportedStateFormat { format: 2 })
        ));
    }

    #[test]
    fn malformed_state_is_refused() {
        let (mut core, _) = new_core();
        core.create("a").unwrap();
        let mut non_canonical = stored(&core);
        non_canonical["state"]["tasks"][0]["title"]["value"] = json!(" a ");
        let cases = [
            b"not json".to_vec(),
            b"{\"format\": 1}".to_vec(),
            serde_json::to_vec(&non_canonical).unwrap(),
        ];

        for json in cases {
            let result = restore(&json);

            assert!(
                matches!(result, Err(FfiError::InvalidState { .. })),
                "{:?}",
                result.err()
            );
        }
    }
}
