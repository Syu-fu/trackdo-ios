//! Response bodies of trackdo-server's HTTP API (its `docs/design.md`) that
//! `trackdo-protocol` does not cover.

use serde::Deserialize;
use uuid::Uuid;

/// `200` of `POST /ops`: every op of the request, retransmissions included.
#[derive(Debug, Deserialize)]
pub(crate) struct Accepted {
    pub(crate) accepted: Vec<Uuid>,
}

/// Body of every error response.
#[derive(Debug, Deserialize)]
pub(crate) struct ErrorBody {
    pub(crate) error: ErrorDetail,
}

#[derive(Debug, Deserialize)]
pub(crate) struct ErrorDetail {
    pub(crate) code: String,
    pub(crate) message: String,
    /// Present only when the error concerns a specific operation.
    pub(crate) op_id: Option<Uuid>,
}
