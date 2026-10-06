//
//  WristbandCopyTests.swift
//  BlueiotMinimalTests
//
//  The visitor-facing text of the wristband session. A wrong mapping fails
//  silently: the visitor reads advice for a different failure. The views are
//  not tested.
//
import Proximiio
import XCTest
#if canImport(ProximiioBlueiot)
import ProximiioBlueiot
#endif
@testable import BlueiotMinimal

final class WristbandCopyTests: XCTestCase {

    // MARK: - Bind errors

    func testBindErrorsHaveTheirOwnMessage() {
        XCTAssertEqual(
            WristbandCopy.message(for: BlueiotBindingError.tagAlreadyBound(requestID: nil)),
            "This wristband is already in use. Please ask the staff."
        )
        XCTAssertEqual(
            WristbandCopy.message(for: BlueiotBindingError.tagNotAvailable(requestID: nil)),
            "This wristband is not active. Please ask the staff."
        )
        XCTAssertEqual(
            WristbandCopy.message(for: BlueiotBindingError.tagNotAtReception(requestID: nil)),
            "Connect this wristband at the reception desk."
        )
        XCTAssertTrue(
            WristbandCopy.message(for: BlueiotBindingError.appTokenRejected(requestID: nil))
                .contains("BLUEIOT_RELAY_APP_TOKEN")
        )
    }

    /// The take-over refusal names what the phone sent, not the relay's text.
    func testZoneRefusalFollowsTheLocationCause() {
        func message(_ cause: BlueiotLocationCause) -> String {
            WristbandCopy.message(for: BlueiotBindingError.notInAuthorizedZone(
                cause: cause, serverMessage: "outside zone", requestID: nil
            ))
        }
        XCTAssertTrue(message(.permissionMissing).contains("allow location"))
        XCTAssertTrue(message(.approximateLocation).contains("Precise Location"))
        XCTAssertTrue(message(.simulatedLocation).contains("simulated"))
        XCTAssertEqual(
            message(.rejectedByRelay),
            "To take over this wristband, be inside the museum with location enabled, or ask at the reception desk."
        )
        XCTAssertFalse(message(.rejectedByRelay).contains("outside zone"))
    }

    func testRateLimitStatesTheWait() {
        XCTAssertEqual(
            WristbandCopy.message(for: BlueiotBindingError.rateLimited(retryAfter: 29.2, requestID: nil)),
            "Too many attempts. Try again in 30 seconds."
        )
        XCTAssertEqual(
            WristbandCopy.message(for: BlueiotBindingError.rateLimited(retryAfter: nil, requestID: nil)),
            "Too many attempts. Try again in a moment."
        )
    }

    // MARK: - End reasons

    func testSupersededNoticeNamesTheOtherPhone() {
        XCTAssertTrue(
            WristbandCopy.notice(for: .superseded).hasPrefix("Your wristband was scanned by another phone.")
        )
    }

    /// A reason a newer relay adds still ends the visit with a notice.
    func testUnknownReasonHasANotice() {
        XCTAssertEqual(WristbandCopy.notice(for: .unknown("NEW_REASON")), "Your visit has ended.")
    }

    // MARK: - Status line

    func testStatusLineFollowsLinkAndSignal() {
        let session = BlueiotBindingSession(bindingID: UUID(), endsAt: .distantFuture, tokenExpiresAt: .distantFuture)
        XCTAssertEqual(WristbandCopy.status(of: .active(session, link: .connecting, signal: .ok)), "Connecting…")
        XCTAssertEqual(WristbandCopy.status(of: .active(session, link: .online, signal: .ok)), "Online")
        XCTAssertEqual(WristbandCopy.status(of: .active(session, link: .online, signal: .lost(since: .now))), "Signal lost")
        XCTAssertEqual(WristbandCopy.status(of: .active(session, link: .reconnecting, signal: .ok)), "Reconnecting…")
        XCTAssertNil(WristbandCopy.status(of: .ended(.superseded)))
        XCTAssertNil(WristbandCopy.status(of: .unbound))
    }

    /// The diagnostics line carries the state and the reason, never a tag id.
    func testLogLineHasNoTagID() {
        XCTAssertEqual(WristbandCopy.logLine(for: .ended(.superseded)), "ended, SUPERSEDED")
    }
}
