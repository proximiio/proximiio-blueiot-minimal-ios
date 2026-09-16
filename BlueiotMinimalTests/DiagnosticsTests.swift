//
//  DiagnosticsTests.swift
//  BlueiotMinimalTests
//
//  The diagnostics log is exported to support. The SDK redacts the credential
//  shapes it recognises; the two build-time values are redacted only because
//  `VenueConfiguration.secrets` passes them to the recorder. A line that carries
//  one verbatim produces no visible error.
//
import Proximiio
import XCTest

final class DiagnosticsTests: XCTestCase {

    /// Shaped like the real values: long, with no `token=` or `Bearer` prefix, so
    /// only the passed-in value itself can match them.
    private let secrets = ["SENTINEL-APP-TOKEN-8f2a1c", "SENTINEL-RELAY-TOKEN-1c04e7"]
    private let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("diagnostics-\(UUID().uuidString)", isDirectory: true)

    override func tearDown() async throws {
        await Proximiio.stopDiagnosticsRecording()
        try? FileManager.default.removeItem(at: directory)
    }

    func testTheLogNeverCarriesAConfiguredSecretVerbatim() async throws {
        // One recording per process; the app's own recording runs in this test host.
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
