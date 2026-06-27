import XCTest
@testable import Douvo

final class MixASRTests: XCTestCase {
    func testMixProviderUsesBothASRPaths() {
        XCTAssertTrue(ASRProvider.mix.usesWebASR)
        XCTAssertTrue(ASRProvider.mix.usesAndroidASR)
        XCTAssertEqual(ASRProvider.mix.activeProviderKeys, ["web", "android"])
    }

    func testMixCorrectionPromptIncludesBothRecognitionResults() {
        let prompt = TranscriptionManager.mixCorrectionPromptText(
            webText: "今天我们测试 Web 识别",
            androidText: "今天我们测试安卓识别"
        )

        XCTAssertTrue(prompt.contains("识别结果一"))
        XCTAssertTrue(prompt.contains("今天我们测试 Web 识别"))
        XCTAssertTrue(prompt.contains("识别结果二"))
        XCTAssertTrue(prompt.contains("今天我们测试安卓识别"))
        XCTAssertFalse(prompt.contains("请综合两路信号"))
    }

    func testMixPromptLeakIsRejectedAsCorrectionOutput() {
        let leakedOutput = """
        本次语音输入有两路 ASR 识别结果 请综合两路信号 合并成一个最终文本 两路内容可能有重叠 漏字 错词或标点差异 识别结果一（Doubao Web）测试文本 识别结果二（Doubao Android）测试文本
        """
        let original = TranscriptionManager.mixCorrectionPromptText(
            webText: "测试文本",
            androidText: "测试文本"
        )

        XCTAssertFalse(LocalLLMPostProcessor.isUsableCorrection(leakedOutput, original: original))
    }

    func testProviderNamesCanBeLegitimateDictationText() {
        XCTAssertTrue(LocalLLMPostProcessor.isUsableCorrection(
            "我们现在测试 Doubao Web 这个渠道",
            original: "我们现在测试 Doubao Web 这个渠道"
        ))
        XCTAssertTrue(LocalLLMPostProcessor.isUsableCorrection(
            "识别结果一这个标题可以保留",
            original: "识别结果一这个标题可以保留"
        ))
    }

    func testEquivalentMixTranscriptsCanUseSingleCorrectionInput() {
        XCTAssertTrue(TranscriptionManager.areEquivalentMixTranscripts(
            "我们现在测试 Doubao Web",
            "我们现在测试 Doubao Web"
        ))
        XCTAssertTrue(TranscriptionManager.areEquivalentMixTranscripts(
            "我们现在测试 Doubao Web。",
            "我们 现在 测试 Doubao Web"
        ))
        XCTAssertFalse(TranscriptionManager.areEquivalentMixTranscripts(
            "我们现在测试 Doubao Web",
            "我们现在测试 Doubao Android"
        ))
    }
}
