//
//  arrayChunkedTests.swift
//
//  Covers Array.chunked(into:) and Array.chunked(intoByteBudget:weightedBy:),
//  added so requestPIDs can split a long PID list into requests a vehicle
//  will actually answer instead of sending every PID as one oversized
//  mode-01 query (see requestPIDs in obd2service.swift: SAE J1979 caps a
//  single request/response at 6 bytes under CAN framing, and many ECUs
//  answer "NO DATA" — or, worse, only the first of a multi-frame ISO-TP
//  reply — once that's exceeded rather than finishing the transfer).
//

@testable import SwiftOBD2
import XCTest

final class arrayChunkedTests: XCTestCase {
    func testSplitsEvenlyDivisibleArray() {
        let chunks = Array(1...6).chunked(into: 3)
        XCTAssertEqual(chunks, [[1, 2, 3], [4, 5, 6]])
    }

    func testLastChunkIsShorterWhenNotEvenlyDivisible() {
        // Mirrors the motivating case: 10 PIDs, max 6 per request.
        let chunks = Array(1...10).chunked(into: 6)
        XCTAssertEqual(chunks, [[1, 2, 3, 4, 5, 6], [7, 8, 9, 10]])
    }

    func testArrayShorterThanChunkSizeYieldsOneChunk() {
        let chunks = [1, 2].chunked(into: 6)
        XCTAssertEqual(chunks, [[1, 2]])
    }

    func testEmptyArrayYieldsNoChunks() {
        let chunks = [Int]().chunked(into: 6)
        XCTAssertTrue(chunks.isEmpty)
    }

    func testExactMultipleOfChunkSizeHasNoTrailingEmptyChunk() {
        let chunks = Array(1...12).chunked(into: 6)
        XCTAssertEqual(chunks, [[1, 2, 3, 4, 5, 6], [7, 8, 9, 10, 11, 12]])
    }

    /// size <= 0 is a degenerate input a caller should never actually pass;
    /// this only guards against it looping forever or crashing.
    func testNonPositiveSizeReturnsWholeArrayAsOneChunk() {
        let chunks = [1, 2, 3].chunked(into: 0)
        XCTAssertEqual(chunks, [[1, 2, 3]])
    }
}

final class arrayChunkedByteBudgetTests: XCTestCase {
    func testSplitsWhenCumulativeWeightExceedsBudget() {
        // Mirrors the motivating case: engineLoad(2) + coolantTemp(2) +
        // rpm(3) + speed(2) = 9 response bytes, over a 6-byte single-frame
        // budget, even though it's only 4 PIDs (well under any PID-count
        // cap). Must split before rpm pushes the running total past 6.
        let weights = ["engineLoad": 2, "coolantTemp": 2, "rpm": 3, "speed": 2]
        let pids = ["engineLoad", "coolantTemp", "rpm", "speed"]
        let chunks = pids.chunked(intoByteBudget: 6) { weights[$0]! }
        XCTAssertEqual(chunks, [["engineLoad", "coolantTemp"], ["rpm", "speed"]])
    }

    func testFitsInOneChunkWhenUnderBudget() {
        let chunks = [1, 1, 1].chunked(intoByteBudget: 6) { $0 }
        XCTAssertEqual(chunks, [[1, 1, 1]])
    }

    func testExactlyAtBudgetStaysInOneChunk() {
        let chunks = [3, 3].chunked(intoByteBudget: 6) { $0 }
        XCTAssertEqual(chunks, [[3, 3]])
    }

    func testSingleElementOverBudgetGetsItsOwnChunkRatherThanBeingDropped() {
        let chunks = [10].chunked(intoByteBudget: 6) { $0 }
        XCTAssertEqual(chunks, [[10]])
    }

    func testOverBudgetElementDoesNotSwallowFollowingElements() {
        let chunks = [10, 1, 1].chunked(intoByteBudget: 6) { $0 }
        XCTAssertEqual(chunks, [[10], [1, 1]])
    }

    func testEmptyArrayYieldsNoChunks() {
        let chunks = [Int]().chunked(intoByteBudget: 6) { $0 }
        XCTAssertTrue(chunks.isEmpty)
    }

    func testNonPositiveBudgetReturnsWholeArrayAsOneChunk() {
        let chunks = [1, 2, 3].chunked(intoByteBudget: 0) { $0 }
        XCTAssertEqual(chunks, [[1, 2, 3]])
    }
}
