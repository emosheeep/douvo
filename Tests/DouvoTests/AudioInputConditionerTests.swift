import XCTest
@testable import Douvo

final class AudioInputConditionerTests: XCTestCase {
    func testConditionerReplacesNonFiniteSamples() {
        var conditioner = AudioInputConditioner()

        let output = conditioner.process([0.1, .nan, .infinity, -.infinity, -0.1])

        XCTAssertEqual(output.count, 5)
        XCTAssertTrue(output.allSatisfy(\.isFinite))
    }

    func testConditionerReducesDcOffsetOverTime() {
        var conditioner = AudioInputConditioner()

        let output = conditioner.process(Array(repeating: Float(0.25), count: 240))
        let earlyAverage = averageMagnitude(output.prefix(40))
        let lateAverage = averageMagnitude(output.suffix(40))

        XCTAssertLessThan(lateAverage, earlyAverage * 0.6)
    }

    func testConditionerKeepsOutputBounded() {
        var conditioner = AudioInputConditioner()

        let input = stride(from: 0, to: 128, by: 1).map { index in
            sinf(Float(index) * 0.2) * 1.4
        }
        let output = conditioner.process(input)

        XCTAssertTrue(output.allSatisfy { sample in
            sample >= -1 && sample <= 1
        })
    }

    private func averageMagnitude<S: Sequence>(_ samples: S) -> Float where S.Element == Float {
        let values = Array(samples)
        guard !values.isEmpty else { return 0 }
        let total = values.reduce(Float(0)) { $0 + abs($1) }
        return total / Float(values.count)
    }
}
