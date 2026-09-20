//
//  BatchedResponseTests.swift
//
//  Covers BatchedResponse.extractValue, the per-PID slice-and-decode step
//  requestPIDs uses to split a mode-01 batch reply. Each PID's slice in that
//  reply starts with its own echo byte (e.g. RPM's `bytes: 3` is 1 echo byte
//  + 2 data bytes) — extractValue must drop it before decoding, matching
//  what the single-PID path already does via `responseData.dropFirst()` in
//  sendCommand. Before this fix the echo byte was decoded as part of the
//  value itself, corrupting every PID in a batched request: UAS-based PIDs
//  (RPM, MAF, speed, …) got a huge out-of-range value that failed the
//  protocol-range check and read as unavailable, while single-byte
//  percent-style PIDs (throttle, engine load, …) silently used their own
//  echo byte as the reading instead of the real data byte.
//

@testable import SwiftOBD2
import XCTest

final class BatchedResponseTests: XCTestCase {
    func testExtractValueDropsTheEchoByteForEachPID() {
        // A two-PID batch reply for 010C (RPM) then 0111 (Throttle Position),
        // as it arrives after the mode byte (41) has already been stripped:
        // [0C, 1F, 40] = RPM echo + 2000rpm's data bytes, [11, 80] = Throttle
        // echo + a ~50% data byte.
        let response = Data([0x0C, 0x1F, 0x40, 0x11, 0x80])
        var batch = BatchedResponse(response: response, .metric)

        let rpm = batch.extractValue(.mode1(.rpm))
        XCTAssertEqual(rpm?.value, 2000, accuracy: 0.01)

        let throttle = batch.extractValue(.mode1(.throttlePos))
        XCTAssertEqual(throttle?.value, 128.0 * 100.0 / 255.0, accuracy: 0.01)
    }

    func testExtractValueConsumesExactlyItsOwnSlice() {
        // Confirms extractValue advances the shared buffer by exactly
        // `properties.bytes`, so a third PID appended after the first two
        // still decodes from the right offset instead of drifting.
        let response = Data([0x0C, 0x1F, 0x40, 0x11, 0x80, 0x05, 0x5A])
        var batch = BatchedResponse(response: response, .metric)

        _ = batch.extractValue(.mode1(.rpm))
        _ = batch.extractValue(.mode1(.throttlePos))
        let coolant = batch.extractValue(.mode1(.coolantTemp))

        XCTAssertEqual(coolant?.value, Double(0x5A) - 40.0, accuracy: 0.01)
    }

    func testExtractValueDecodesVehicleSpeedsGenuinelyOneDataByte() {
        // Regression: on a real vehicle at a stop, 010D's batched slice was
        // exactly [0D, 00] — echo byte + a single 0 km/h data byte — but
        // decoding failed with "No data received" because the UAS table
        // entry for speed's ID (0x09) had minBytes: 2, left over from before
        // this file's fix started actually dropping the echo byte. Before
        // that fix, the still-present echo byte coincidentally padded the
        // count to 2 and slipped past the check (while decoding garbage);
        // after it, the genuinely 1-byte reading correctly failed the
        // 2-byte minimum. Speed is 1 data byte per SAE J1979 — this must
        // succeed, not throw.
        let response = Data([0x0D, 0x00])
        var batch = BatchedResponse(response: response, .metric)

        let speed = batch.extractValue(.mode1(.speed))
        XCTAssertEqual(speed?.value, 0, accuracy: 0.01)
    }

    func testExtractValueDecodesNonZeroVehicleSpeed() {
        let response = Data([0x0D, 0x64]) // 100 km/h
        var batch = BatchedResponse(response: response, .metric)

        let speed = batch.extractValue(.mode1(.speed))
        XCTAssertEqual(speed?.value, 100, accuracy: 0.01)
    }
}
