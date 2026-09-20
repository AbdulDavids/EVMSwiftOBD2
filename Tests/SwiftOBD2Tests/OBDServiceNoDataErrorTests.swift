//
//  OBDServiceNoDataErrorTests.swift
//
//  Covers OBDService.isNoDataError, which requestPIDs uses to tell a routine
//  "NO DATA" reply (an ECU definitively saying it has nothing for this PID,
//  not a transport failure) apart from a real connection/transport problem.
//  Before this fix, requestPIDs let ANY error from a chunk's sendCommand
//  propagate, discarding every chunk's results in that call — including
//  ones from earlier, already-successful chunks — the moment one PID (e.g.
//  an unsupported sensor like MAF) answered "NO DATA". OBDViewModel's poll
//  loop then treated that as fatal and stopped polling entirely.
//

@testable import SwiftOBD2
import XCTest

final class OBDServiceNoDataErrorTests: XCTestCase {
    func testRecognisesBareNoDataError() {
        XCTAssertTrue(OBDService.isNoDataError(BLEManagerError.noData))
    }

    func testRecognisesNoDataWrappedInCommandFailed() {
        let wrapped = OBDServiceError.commandFailed(command: "0110", error: BLEManagerError.noData)
        XCTAssertTrue(OBDService.isNoDataError(wrapped))
    }

    func testDoesNotTreatOtherBLEErrorsAsNoData() {
        XCTAssertFalse(OBDService.isNoDataError(BLEManagerError.sendMessageTimeout))
        XCTAssertFalse(OBDService.isNoDataError(BLEManagerError.peripheralNotConnected))
    }

    func testDoesNotTreatOtherErrorsWrappedInCommandFailedAsNoData() {
        let wrapped = OBDServiceError.commandFailed(command: "010C", error: BLEManagerError.sendMessageTimeout)
        XCTAssertFalse(OBDService.isNoDataError(wrapped))
    }
}
