//! Errors raised across the FFI.

use thiserror::Error;
use trackdo_core::hlc::HlcError;
use trackdo_core::note::NoteError;
use trackdo_core::replica::CommandError;
use trackdo_core::tag::TagNameError;
use trackdo_core::time_entry::Timestamp;
use trackdo_core::title::TitleError;

use crate::ids;

/// Ids are UUID strings and times Unix milliseconds, as everywhere in the
/// bindings.
#[derive(Debug, Clone, PartialEq, Eq, Error, uniffi::Error)]
pub enum FfiError {
    #[error("{id} is not a UUID")]
    InvalidId { id: String },
    #[error("title must not be empty")]
    EmptyTitle,
    #[error("title must be a single line")]
    TitleContainsLineBreak,
    #[error("title must be at most {max} characters, got {actual}")]
    TitleTooLong { max: u64, actual: u64 },
    #[error("note must be at most {max} characters, got {actual}")]
    NoteTooLong { max: u64, actual: u64 },
    #[error("task {id} does not exist")]
    TaskNotFound { id: String },
    #[error("task {id} is deleted")]
    TaskDeleted { id: String },
    #[error("moving {task_id} under {parent_id} would create a cycle")]
    Cycle { task_id: String, parent_id: String },
    #[error("tag name must not be empty")]
    EmptyTagName,
    #[error("tag name must be a single line")]
    TagNameContainsLineBreak,
    #[error("tag name must be at most {max} characters, got {actual}")]
    TagNameTooLong { max: u64, actual: u64 },
    #[error("tag {id} does not exist")]
    TagNotFound { id: String },
    #[error("tag {id} is deleted")]
    TagDeleted { id: String },
    #[error("tag {id} already has that name")]
    TagNameTaken { id: String },
    #[error("time entry {id} does not exist")]
    EntryNotFound { id: String },
    #[error("time entry {id} is deleted")]
    EntryDeleted { id: String },
    #[error("time entry {id} is not running")]
    EntryNotRunning { id: String },
    #[error("stop time {stopped_at_ms} precedes start time {started_at_ms}")]
    StopBeforeStart {
        started_at_ms: u64,
        stopped_at_ms: u64,
    },
    #[error("time {at_ms} is in the future")]
    InFuture { at_ms: u64 },
    /// Practically unreachable: needs billions of writes within a millisecond.
    #[error("logical clock overflowed")]
    ClockOverflow,
    /// The stored state was written by a newer app.
    #[error("stored state format {format} is not supported")]
    UnsupportedStateFormat { format: u32 },
    #[error("stored state is invalid: {message}")]
    InvalidState { message: String },
}

impl From<CommandError> for FfiError {
    fn from(error: CommandError) -> Self {
        match error {
            CommandError::Title(error) => error.into(),
            CommandError::Note(NoteError::TooLong { max, actual }) => Self::NoteTooLong {
                max: count(max),
                actual: count(actual),
            },
            CommandError::NotFound(id) => Self::TaskNotFound {
                id: ids::encode(id.0),
            },
            CommandError::Deleted(id) => Self::TaskDeleted {
                id: ids::encode(id.0),
            },
            CommandError::Cycle { task, parent } => Self::Cycle {
                task_id: ids::encode(task.0),
                parent_id: ids::encode(parent.0),
            },
            CommandError::TagName(error) => error.into(),
            CommandError::TagNotFound(id) => Self::TagNotFound {
                id: ids::encode(id.0),
            },
            CommandError::TagDeleted(id) => Self::TagDeleted {
                id: ids::encode(id.0),
            },
            CommandError::TagNameTaken(id) => Self::TagNameTaken {
                id: ids::encode(id.0),
            },
            CommandError::EntryNotFound(id) => Self::EntryNotFound {
                id: ids::encode(id.0),
            },
            CommandError::EntryDeleted(id) => Self::EntryDeleted {
                id: ids::encode(id.0),
            },
            CommandError::NotRunning(id) => Self::EntryNotRunning {
                id: ids::encode(id.0),
            },
            CommandError::StopBeforeStart {
                started: Timestamp(started_at_ms),
                stopped: Timestamp(stopped_at_ms),
            } => Self::StopBeforeStart {
                started_at_ms,
                stopped_at_ms,
            },
            CommandError::InFuture(Timestamp(at_ms)) => Self::InFuture { at_ms },
            CommandError::Clock(HlcError::CounterOverflow) => Self::ClockOverflow,
        }
    }
}

impl From<TitleError> for FfiError {
    fn from(error: TitleError) -> Self {
        match error {
            TitleError::Empty => Self::EmptyTitle,
            TitleError::ContainsLineBreak => Self::TitleContainsLineBreak,
            TitleError::TooLong { max, actual } => Self::TitleTooLong {
                max: count(max),
                actual: count(actual),
            },
        }
    }
}

impl From<TagNameError> for FfiError {
    fn from(error: TagNameError) -> Self {
        match error {
            TagNameError::Empty => Self::EmptyTagName,
            TagNameError::ContainsLineBreak => Self::TagNameContainsLineBreak,
            TagNameError::TooLong { max, actual } => Self::TagNameTooLong {
                max: count(max),
                actual: count(actual),
            },
        }
    }
}

fn count(n: usize) -> u64 {
    u64::try_from(n).unwrap_or(u64::MAX)
}

#[cfg(test)]
mod tests {
    use trackdo_core::hlc::HlcError;
    use trackdo_core::note::NoteError;
    use trackdo_core::replica::CommandError;
    use trackdo_core::tag::{TagId, TagNameError};
    use trackdo_core::task::TaskId;
    use trackdo_core::time_entry::{TimeEntryId, Timestamp};
    use trackdo_core::title::TitleError;

    use super::*;
    use crate::ids;

    #[test]
    fn command_errors_map_to_ffi_errors() {
        let id = ids::encode(7);
        let cases = [
            (CommandError::Title(TitleError::Empty), FfiError::EmptyTitle),
            (
                CommandError::Title(TitleError::ContainsLineBreak),
                FfiError::TitleContainsLineBreak,
            ),
            (
                CommandError::Title(TitleError::TooLong {
                    max: 500,
                    actual: 501,
                }),
                FfiError::TitleTooLong {
                    max: 500,
                    actual: 501,
                },
            ),
            (
                CommandError::NotFound(TaskId(7)),
                FfiError::TaskNotFound { id: id.clone() },
            ),
            (
                CommandError::Deleted(TaskId(7)),
                FfiError::TaskDeleted { id: id.clone() },
            ),
            (
                CommandError::EntryNotFound(TimeEntryId(7)),
                FfiError::EntryNotFound { id: id.clone() },
            ),
            (
                CommandError::EntryDeleted(TimeEntryId(7)),
                FfiError::EntryDeleted { id: id.clone() },
            ),
            (
                CommandError::NotRunning(TimeEntryId(7)),
                FfiError::EntryNotRunning { id },
            ),
            (
                CommandError::StopBeforeStart {
                    started: Timestamp(20),
                    stopped: Timestamp(10),
                },
                FfiError::StopBeforeStart {
                    started_at_ms: 20,
                    stopped_at_ms: 10,
                },
            ),
            (
                CommandError::InFuture(Timestamp(99)),
                FfiError::InFuture { at_ms: 99 },
            ),
            (
                CommandError::Clock(HlcError::CounterOverflow),
                FfiError::ClockOverflow,
            ),
            (
                CommandError::Note(NoteError::TooLong {
                    max: 10_000,
                    actual: 10_001,
                }),
                FfiError::NoteTooLong {
                    max: 10_000,
                    actual: 10_001,
                },
            ),
            (
                CommandError::TagName(TagNameError::Empty),
                FfiError::EmptyTagName,
            ),
            (
                CommandError::TagName(TagNameError::ContainsLineBreak),
                FfiError::TagNameContainsLineBreak,
            ),
            (
                CommandError::TagName(TagNameError::TooLong {
                    max: 50,
                    actual: 51,
                }),
                FfiError::TagNameTooLong {
                    max: 50,
                    actual: 51,
                },
            ),
            (
                CommandError::TagNotFound(TagId(7)),
                FfiError::TagNotFound { id: ids::encode(7) },
            ),
            (
                CommandError::TagDeleted(TagId(7)),
                FfiError::TagDeleted { id: ids::encode(7) },
            ),
            (
                CommandError::TagNameTaken(TagId(7)),
                FfiError::TagNameTaken { id: ids::encode(7) },
            ),
            (
                CommandError::Cycle {
                    task: TaskId(7),
                    parent: TaskId(8),
                },
                FfiError::Cycle {
                    task_id: ids::encode(7),
                    parent_id: ids::encode(8),
                },
            ),
        ];

        for (command, expected) in cases {
            assert_eq!(FfiError::from(command), expected);
        }
    }
}
