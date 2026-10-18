//! Ids cross the FFI as hyphenated lowercase UUID strings.

use uuid::Uuid;

use crate::error::FfiError;

pub(crate) fn encode(id: u128) -> String {
    Uuid::from_u128(id).hyphenated().to_string()
}

pub(crate) fn decode(id: &str) -> Result<u128, FfiError> {
    Uuid::try_parse(id)
        .map(|uuid| uuid.as_u128())
        .map_err(|_| FfiError::InvalidId { id: id.to_owned() })
}

#[cfg(test)]
mod tests {
    use super::*;

    const RAW: u128 = 0x0192_8f3a_1b2c_7d4e_8f90_a1b2_c3d4_e5f6;
    const TEXT: &str = "01928f3a-1b2c-7d4e-8f90-a1b2c3d4e5f6";

    #[test]
    fn encodes_as_hyphenated_lowercase_uuid() {
        assert_eq!(encode(RAW), TEXT);
    }

    #[test]
    fn decodes_what_it_encodes() {
        assert_eq!(decode(TEXT), Ok(RAW));
    }

    #[test]
    fn decodes_uppercase_uuid() {
        assert_eq!(decode(&TEXT.to_uppercase()), Ok(RAW));
    }

    #[test]
    fn rejects_non_uuid() {
        assert_eq!(
            decode("not-a-uuid"),
            Err(FfiError::InvalidId {
                id: "not-a-uuid".to_owned()
            })
        );
    }
}
