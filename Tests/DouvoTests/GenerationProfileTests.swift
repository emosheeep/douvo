import XCTest
@testable import Douvo

final class GenerationProfileTests: XCTestCase {
    func testCurrentCorrectionUsesMinimumOutputBudgetForShortText() {
        let profile = LocalLLMGenerationProfile.currentCorrection(for: "看一下日志")

        XCTAssertEqual(profile.reasoningMode, .disabled)
        XCTAssertEqual(profile.maxTokens, 256)
    }

    func testCurrentCorrectionScalesOutputBudgetWithInputLength() {
        let input = String(repeating: "字", count: 1_000)
        let profile = LocalLLMGenerationProfile.currentCorrection(for: input)

        XCTAssertEqual(profile.reasoningMode, .disabled)
        XCTAssertEqual(profile.maxTokens, 1_500)
    }

    func testCurrentCorrectionCapsVeryLongOutputBudget() {
        let input = String(repeating: "字", count: 3_000)
        let profile = LocalLLMGenerationProfile.currentCorrection(for: input)

        XCTAssertEqual(profile.maxTokens, 4_096)
    }

    func testReasoningEnabledKeepsLargerMinimumWithoutControllingScaling() {
        let shortProfile = LocalLLMGenerationProfile.asrCorrection(
            reasoningMode: .enabled,
            estimatedInputCharacters: 10
        )
        let longProfile = LocalLLMGenerationProfile.asrCorrection(
            reasoningMode: .enabled,
            estimatedInputCharacters: 2_000
        )

        XCTAssertEqual(shortProfile.maxTokens, 1_536)
        XCTAssertEqual(longProfile.maxTokens, 3_000)
    }
}
