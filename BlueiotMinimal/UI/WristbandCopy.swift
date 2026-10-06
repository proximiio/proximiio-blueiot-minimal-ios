//
//  WristbandCopy.swift
//  BlueiotMinimal
//
//  The visitor-facing text for the wristband session: one message per bind
//  error, one notice per end reason, and the status line on the map. Pure
//  functions, covered by tests.
//
//  The text is keyed on the SDK's error cases and end reasons, never on the
//  relay-api's English messages, which may change.
//
import Foundation
import Proximiio
#if canImport(ProximiioBlueiot)
import ProximiioBlueiot
#endif

enum WristbandCopy {

    /// The message for a failed bind or end.
    static func message(for error: Error) -> String {
        guard let error = error as? BlueiotBindingError else {
            return error.localizedDescription
        }
        switch error {
        case .tagAlreadyBound:
            return "This wristband is already in use. Please ask the staff."
        case .notInAuthorizedZone(let cause, _, _):
            return message(for: cause)
        case .tagNotAvailable:
            return "This wristband is not active. Please ask the staff."
        case .tagNotAtReception:
            return "Connect this wristband at the reception desk."
        case .tagNotIssued:
            return "This wristband has not been issued yet. Please ask the staff."
        case .invalidTagID:
            return "This is not a wristband number. Check the number printed on the band."
        case .rateLimited(let retryAfter, _):
            guard let retryAfter, retryAfter > 0 else { return "Too many attempts. Try again in a moment." }
            let seconds = Int(retryAfter.rounded(.up))
            return "Too many attempts. Try again in \(seconds) \(seconds == 1 ? "second" : "seconds")."
        case .network:
            return "The venue's server cannot be reached. Check the connection and try again."
        case .server, .invalidResponse:
            return "The venue's server failed. Try again in a moment."
        case .sessionLost, .bindingClosed:
            return "The wristband session has ended. Connect the wristband again."
        // Configuration faults. A visitor never sees them in a configured build.
        case .appTokenRejected:
            return "The relay-api refused the app token. Check BLUEIOT_RELAY_APP_TOKEN."
        case .notARelayAPI:
            return "BLUEIOT_RELAY_URL is not a relay-api address."
        case .invalidRequest, .forbidden, .unexpected:
            return error.localizedDescription
        @unknown default:
            return error.localizedDescription
        }
    }

    /// The message for a take-over refused with `not_in_authorized_zone`, per
    /// what the phone sent.
    static func message(for cause: BlueiotLocationCause) -> String {
        switch cause {
        case .permissionMissing:
            return "To take over this wristband, allow location for this app in Settings, or ask at the reception desk."
        case .approximateLocation:
            return "To take over this wristband, turn on Precise Location for this app in Settings, or ask at the reception desk."
        case .noFreshFix:
            return "Your location could not be determined in time. Try again, or ask at the reception desk."
        case .simulatedLocation:
            return "This phone reports a simulated location. Turn it off, or ask at the reception desk."
        case .rejectedByRelay:
            return "To take over this wristband, be inside the museum with location enabled, or ask at the reception desk."
        @unknown default:
            return "To take over this wristband, be inside the museum with location enabled, or ask at the reception desk."
        }
    }

    /// The notice shown on the wristband prompt after a session ended.
    static func notice(for reason: BlueiotBindingEndReason) -> String {
        switch reason {
        case .superseded:
            return "Your wristband was scanned by another phone. Connect it again to follow it on this phone."
        case .userEnded:
            return "Your visit has ended."
        case .returned:
            return "The wristband was returned. Thank you for your visit."
        case .timeout:
            return "The wristband stopped reporting. Please ask the staff."
        case .leftVenue:
            return "The wristband left the venue."
        case .staffRevoked:
            return "The staff released this wristband."
        case .expired:
            return "Your visit time is over."
        case .replaced:
            return "This wristband session was replaced by a newer one."
        case .sessionLost:
            return "The connection to your wristband was lost. Connect it again."
        case .unknown:
            return "Your visit has ended."
        @unknown default:
            return "Your visit has ended."
        }
    }

    /// Why the app is about to show an iOS location dialog. Shown on the
    /// prompt before the visitor taps Connect.
    static func explanation(for ask: WristbandSession.LocationAsk) -> String {
        switch ask {
        case .permission:
            return "Connecting asks for your location. It confirms that you are in the venue."
        case .preciseLocation:
            return "Connecting asks for your precise location. It confirms that you are in the venue."
        }
    }

    /// The status line on the map, or `nil` when no session is active.
    static func status(of state: BlueiotBindingState?) -> String? {
        switch state {
        case .binding:
            return "Connecting…"
        case .active(_, let link, let signal):
            switch (link, signal) {
            case (.connecting, _): return "Connecting…"
            case (.reconnecting, _): return "Reconnecting…"
            case (.online, .lost): return "Signal lost"
            case (.online, .ok): return "Online"
            default: return "Connecting…"
            }
        case .unbound, .ended, nil:
            return nil
        @unknown default:
            return nil
        }
    }

    /// The state for the diagnostics log. Holds no tag id.
    static func logLine(for state: BlueiotBindingState) -> String {
        switch state {
        case .unbound: return "unbound"
        case .binding: return "binding"
        case .active(_, let link, let signal):
            if case .lost = signal { return "active, \(link.rawValue), signal lost" }
            return "active, \(link.rawValue)"
        case .ended(let reason): return "ended, \(reason.rawValue)"
        @unknown default: return "unknown"
        }
    }
}
