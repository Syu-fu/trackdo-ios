import Foundation
import TrackdoKit

/// What the settings screen says about each problem: what went wrong and
/// how to fix it.
extension ServerURLError {
    var message: LocalizedStringResource {
        switch self {
        case .malformed: "Enter the full address, starting with https://."
        case .unsupportedScheme: "Start the address with https://."
        case .insecureRemoteHost: "Use https:// unless the server runs on this device or your local network."
        case .hasQueryOrFragment: "Remove the part from ? or # onward."
        case .hasCredentials: "Remove the user name and password from the address."
        }
    }
}

extension ServerSettingsError {
    func message(tokenWasEmpty: Bool) -> LocalizedStringResource {
        tokenWasEmpty ? "Enter the token that the server accepts." : "Enter the token without spaces or line breaks."
    }
}

extension SettingsIssue {
    var title: LocalizedStringResource {
        switch self {
        case .server(.unauthorized): "The server refused the token"
        case .server(.unsupportedProtocol): "The app and the server are not compatible"
        case .server(.offline): "The server could not be reached"
        case .server(.serverFailure): "The server failed"
        case .server(.unexpected), .server(.resyncRequired): "This is not a trackdo server"
        case .storage: "The settings could not be saved"
        }
    }

    var description: LocalizedStringResource {
        switch self {
        case .server(.unauthorized):
            "Check that the token is one the server accepts. Nothing was changed."
        case .server(.unsupportedProtocol):
            "Update the app or the server so that both use the same sync protocol. Nothing was changed."
        case .server(.offline):
            "Check the address and your network connection, then try again. Nothing was changed."
        case let .server(.serverFailure(status)):
            "The server answered with error \(status). Try again later. Nothing was changed."
        case .server(.unexpected), .server(.resyncRequired):
            "Something answered at this address, but not as trackdo-server does. Check the address."
        case let .storage(reason):
            "Try again. If this keeps happening, restart the device. (\(reason))"
        }
    }
}
