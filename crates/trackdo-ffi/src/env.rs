//! Host capabilities `trackdo-core` needs: wall-clock time and unique ids.

use std::time::{SystemTime, UNIX_EPOCH};

use trackdo_core::env::{Clock, IdGen};
use trackdo_core::op::OpId;
use trackdo_core::task::TaskId;
use trackdo_core::time_entry::TimeEntryId;
use uuid::Uuid;

/// The device's wall clock in UTC milliseconds.
#[cfg_attr(
    not(test),
    expect(dead_code, reason = "used once the replica is exported")
)]
pub(crate) struct SystemClock;

impl Clock for SystemClock {
    /// A clock set before the epoch reads as 0; the HLC absorbs the jump.
    fn now_millis(&self) -> u64 {
        let since_epoch = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap_or_default();
        u64::try_from(since_epoch.as_millis()).unwrap_or(u64::MAX)
    }
}

/// UUIDv7 ids, strictly increasing within the process.
#[cfg_attr(
    not(test),
    expect(dead_code, reason = "used once the replica is exported")
)]
pub(crate) struct UuidV7;

impl IdGen for UuidV7 {
    fn task_id(&mut self) -> TaskId {
        TaskId(Uuid::now_v7().as_u128())
    }

    fn time_entry_id(&mut self) -> TimeEntryId {
        TimeEntryId(Uuid::now_v7().as_u128())
    }

    fn op_id(&mut self) -> OpId {
        OpId(Uuid::now_v7().as_u128())
    }
}

#[cfg(test)]
mod tests {
    use std::collections::HashSet;

    use super::*;

    fn unix_millis() -> u64 {
        let since_epoch = SystemTime::now().duration_since(UNIX_EPOCH).unwrap();
        u64::try_from(since_epoch.as_millis()).unwrap()
    }

    #[test]
    fn system_clock_reports_current_unix_millis() {
        let before = unix_millis();
        let now = SystemClock.now_millis();
        let after = unix_millis();

        assert!(
            (before..=after).contains(&now),
            "{now} not in {before}..={after}"
        );
    }

    #[test]
    fn ids_are_uuid_v7() {
        let mut ids = UuidV7;

        let generated = [ids.task_id().0, ids.time_entry_id().0, ids.op_id().0];

        for id in generated {
            assert_eq!(Uuid::from_u128(id).get_version_num(), 7);
        }
    }

    #[test]
    fn ids_are_unique_and_increasing() {
        let mut ids = UuidV7;

        let generated: Vec<u128> = (0..1_000).map(|_| ids.op_id().0).collect();

        assert_eq!(
            generated.iter().collect::<HashSet<_>>().len(),
            generated.len()
        );
        assert!(generated.windows(2).all(|pair| pair[0] < pair[1]));
    }
}
