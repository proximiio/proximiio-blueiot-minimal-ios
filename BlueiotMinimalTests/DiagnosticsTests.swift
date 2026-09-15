//
//  DiagnosticsTests.swift
//  BlueiotMinimalTests
//
//  The diagnostics log travels: support asks for the folder and someone sends it.
//  The SDK strips the credential shapes it knows on its own; the two values this
//  app is built with are stripped only because `VenueConfiguration.secrets` hands
//  them to the recorder — and a line that carries one verbatim looks exactly like
//  a line that does not.
//
import Proximiio
import XCTest

final class DiagnosticsTests: XCTestCase {

    /// The two real values' shape — long, and with no `token=` or `Bearer` in front
    /// of them, so nothing but the handed-over value itself can catch them.
    private let secrets = ["SENTINEL-APP-TOKEN-8f2a1c", "SENTINEL-RELAY-TOKEN-1c04e7"]
    private let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("diagnostics-\(UUID().uuidString)", isDirectory: true)

    override func tearDown() async throws {
        await Proximiio.stopDiagnosticsRecording()
        try? FileManager.default.removeItem(at: directory)
    }

    func testTheLogNeverCarriesAConfiguredSecretVerbatim() async throws {
        // One recording per process, and the app's own is running in this test host.
        await Proximiio.stopDiagnosticsRecording()
        try await Proximiio.startDiagnosticsRecording(.init(directory: directory, additionalSecrets: secrets))
        Proximiio.recordDiagnosticsEvent(.state, "relay answered 401 for \(secrets[1]) under \(secrets[0])")
        await Proximiio.stopDiagnosticsRecording()

        let log = try String(contentsOf: directory.appendingPathComponent("proximiio-diagnostics.log"), encoding: .utf8)
        XCTAssertTrue(log.contains("relay answered 401"), "the line itself was not written")
        for secret in secrets {
            XCTAssertFalse(log.contains(secret), "\(secret) written verbatim")
        }
    }
}
