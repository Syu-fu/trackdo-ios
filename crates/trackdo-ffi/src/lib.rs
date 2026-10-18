//! UniFFI bindings of trackdo-core for the iOS client.

uniffi::setup_scaffolding!();

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
}
