//! Sending pending operations with `POST /ops`.
//!
//! The host posts each batch from [`Core::next_push_batch`] and hands the
//! response to [`Core::handle_push_response`], until no batch is left or the
//! outcome says to stop or wait.

use trackdo_core::env::{Clock, IdGen};
use trackdo_core::op::OpId;
use trackdo_protocol::op::OpDto;

use super::Core;
use crate::ids;
use crate::wire::{Accepted, ErrorBody, ErrorDetail};

/// Most ops the server takes in one request.
pub(crate) const MAX_BATCH: usize = 500;

/// What the host should do after a `POST /ops` response.
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Enum)]
pub enum PushOutcome {
    /// The batch was stored; send the next one.
    Accepted,
    /// The server refused the op for good and the whole batch with it. The
    /// op was dropped; send the next batch. Worth logging: a correct client
    /// and server never get here.
    Rejected {
        op_id: String,
        code: String,
        message: String,
    },
    /// The token is wrong. Stop until the settings change.
    Unauthorized,
    /// The app or the server needs updating. Stop until either changes.
    UnsupportedProtocol,
    /// The server failed; send again after backing off.
    Retry,
    /// A response the API does not specify. Back off; nothing was changed.
    Unexpected { status: u16, message: String },
}

impl<C: Clock + Clone, G: IdGen> Core<C, G> {
    /// Body of the next `POST /ops`: the oldest pending ops as a JSON array
    /// of `OpDto`, or `None` when everything was sent.
    pub(crate) fn next_push_batch(&self) -> Option<Vec<u8>> {
        let pending = self.replica.pending_ops();
        if pending.is_empty() {
            return None;
        }
        let batch: Vec<OpDto> = pending.iter().take(MAX_BATCH).map(OpDto::from).collect();
        Some(serde_json::to_vec(&batch).expect("OpDto always serializes"))
    }

    pub(crate) fn handle_push_response(&mut self, status: u16, body: &[u8]) -> PushOutcome {
        match status {
            200 => self.accept(body),
            401 => PushOutcome::Unauthorized,
            409 | 422 => self.reject(status, body),
            400 => match error_detail(body) {
                Some(error) if error.code == "unsupported_protocol_version" => {
                    PushOutcome::UnsupportedProtocol
                }
                _ => unexpected(status, body),
            },
            500..=599 => PushOutcome::Retry,
            _ => unexpected(status, body),
        }
    }

    fn accept(&mut self, body: &[u8]) -> PushOutcome {
        match serde_json::from_slice::<Accepted>(body) {
            Ok(Accepted { accepted }) => {
                let op_ids: Vec<OpId> = accepted.iter().map(|id| OpId(id.as_u128())).collect();
                self.replica.acknowledge(&op_ids);
                PushOutcome::Accepted
            }
            Err(error) => PushOutcome::Unexpected {
                status: 200,
                message: error.to_string(),
            },
        }
    }

    fn reject(&mut self, status: u16, body: &[u8]) -> PushOutcome {
        let Some(ErrorDetail {
            code,
            message,
            op_id: Some(op_id),
        }) = error_detail(body)
        else {
            return unexpected(status, body);
        };
        self.replica.reject(&[OpId(op_id.as_u128())]);
        PushOutcome::Rejected {
            op_id: ids::encode(op_id.as_u128()),
            code,
            message,
        }
    }
}

fn error_detail(body: &[u8]) -> Option<ErrorDetail> {
    serde_json::from_slice::<ErrorBody>(body)
        .ok()
        .map(|body| body.error)
}

fn unexpected(status: u16, body: &[u8]) -> PushOutcome {
    PushOutcome::Unexpected {
        status,
        message: String::from_utf8_lossy(body).into_owned(),
    }
}

#[cfg(test)]
mod tests {
    use serde_json::json;
    use trackdo_core::op::Op;
    use trackdo_protocol::op::OpDto;

    use super::*;
    use crate::core::tests::core;

    fn sent_ops(body: &[u8]) -> Vec<Op> {
        let dtos: Vec<OpDto> = serde_json::from_slice(body).unwrap();
        dtos.into_iter()
            .map(|dto| Op::try_from(dto).unwrap())
            .collect()
    }

    fn pending_ids<C: Clock + Clone, G: IdGen>(core: &Core<C, G>) -> Vec<String> {
        core.replica
            .pending_ops()
            .iter()
            .map(|op| ids::encode(op.op_id.0))
            .collect()
    }

    fn error_body(code: &str, op_id: Option<&str>) -> Vec<u8> {
        let mut error = json!({ "code": code, "message": "refused" });
        if let Some(op_id) = op_id {
            error["op_id"] = json!(op_id);
        }
        serde_json::to_vec(&json!({ "error": error })).unwrap()
    }

    fn accepted_body(op_ids: &[String]) -> Vec<u8> {
        serde_json::to_vec(&json!({ "accepted": op_ids })).unwrap()
    }

    #[test]
    fn nothing_to_send_without_pending_ops() {
        let (core, _) = core();

        assert_eq!(core.next_push_batch(), None);
    }

    #[test]
    fn batch_holds_pending_ops_in_order() {
        let (mut core, _) = core();
        core.create("a").unwrap();

        let body = core.next_push_batch().unwrap();

        assert_eq!(sent_ops(&body), core.replica.pending_ops());
    }

    #[test]
    fn batch_is_capped_at_server_limit() {
        let (mut core, _) = core();
        for _ in 0..300 {
            core.create("a").unwrap();
        }

        let body = core.next_push_batch().unwrap();

        assert_eq!(sent_ops(&body), core.replica.pending_ops()[..MAX_BATCH]);
    }

    #[test]
    fn accepted_ops_are_acknowledged() {
        let (mut core, _) = core();
        core.create("a").unwrap();
        let sent = pending_ids(&core);
        core.create("b").unwrap();

        let outcome = core.handle_push_response(200, &accepted_body(&sent));

        assert_eq!(outcome, PushOutcome::Accepted);
        assert_eq!(pending_ids(&core).len(), 2);
        assert!(pending_ids(&core).iter().all(|id| !sent.contains(id)));
    }

    #[test]
    fn rejected_op_is_dropped_and_reported() {
        for (status, code) in [(409, "task_mismatch"), (422, "invalid_op")] {
            let (mut core, _) = core();
            core.create("a").unwrap();
            let pending = pending_ids(&core);

            let outcome = core.handle_push_response(status, &error_body(code, Some(&pending[0])));

            assert_eq!(
                outcome,
                PushOutcome::Rejected {
                    op_id: pending[0].clone(),
                    code: code.to_owned(),
                    message: "refused".to_owned(),
                }
            );
            assert_eq!(pending_ids(&core), pending[1..]);
        }
    }

    #[test]
    fn rejection_without_op_id_is_unexpected() {
        let (mut core, _) = core();
        core.create("a").unwrap();
        let pending = pending_ids(&core);

        let outcome = core.handle_push_response(422, &error_body("invalid_op", None));

        assert!(matches!(
            outcome,
            PushOutcome::Unexpected { status: 422, .. }
        ));
        assert_eq!(pending_ids(&core), pending);
    }

    #[test]
    fn unauthorized_stops_sending() {
        let (mut core, _) = core();
        core.create("a").unwrap();
        let pending = pending_ids(&core);

        let outcome = core.handle_push_response(401, &error_body("unauthorized", None));

        assert_eq!(outcome, PushOutcome::Unauthorized);
        assert_eq!(pending_ids(&core), pending);
    }

    #[test]
    fn protocol_mismatch_stops_sending() {
        let (mut core, _) = core();

        let outcome =
            core.handle_push_response(400, &error_body("unsupported_protocol_version", None));

        assert_eq!(outcome, PushOutcome::UnsupportedProtocol);
    }

    #[test]
    fn server_errors_are_retried() {
        for status in [500, 502, 503] {
            let (mut core, _) = core();

            assert_eq!(core.handle_push_response(status, b""), PushOutcome::Retry);
        }
    }

    #[test]
    fn other_responses_are_unexpected() {
        let cases: [(u16, Vec<u8>); 4] = [
            (400, error_body("invalid_json", None)),
            (413, error_body("too_large", None)),
            (200, b"not json".to_vec()),
            (418, b"".to_vec()),
        ];
        for (status, body) in cases {
            let (mut core, _) = core();

            let outcome = core.handle_push_response(status, &body);

            assert!(
                matches!(outcome, PushOutcome::Unexpected { status: s, .. } if s == status),
                "{status}: {outcome:?}"
            );
        }
    }
}
