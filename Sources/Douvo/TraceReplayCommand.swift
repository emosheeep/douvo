import Foundation

enum TraceReplayCommand {
    static func traceURL(from arguments: [String]) -> URL? {
        guard let index = arguments.firstIndex(of: "--replay-trace"),
              arguments.indices.contains(index + 1) else {
            return nil
        }
        return URL(fileURLWithPath: arguments[index + 1])
    }

    static func run(traceURL: URL) async -> Int32 {
        do {
            let trace = try TranscriptionTraceSnapshot.load(from: traceURL)
            let promptLabURL = try writePromptLabCase(for: trace, sourceTraceURL: traceURL)
            let replayURL = try await replayCorrection(for: trace, sourceTraceURL: traceURL, promptLabURL: promptLabURL)
            progress("Trace replay result: \(replayURL.path)")
            progress("Prompt lab case: \(promptLabURL.path)")
            return 0
        } catch {
            fputs("Trace replay failed: \(error.localizedDescription)\n", stderr)
            return 1
        }
    }

    private static func replayCorrection(
        for trace: TranscriptionTraceSnapshot,
        sourceTraceURL: URL,
        promptLabURL: URL
    ) async throws -> URL {
        let startedAt = Date()
        let started = ProcessInfo.processInfo.systemUptime
        let result = try await CorrectionPostProcessor.shared.correctedTextWithTrace(
            for: trace.rawText,
            requiresEnabled: false
        )
        let wallMilliseconds = milliseconds(since: started)
        let payload: [String: Any] = [
            "type": "trace_replay",
            "started_at": ISO8601DateFormatter().string(from: startedAt),
            "source_trace_path": sourceTraceURL.path,
            "source_trace_id": trace.id,
            "source_outcome": trace.outcome,
            "recording_path": jsonValue(trace.recordingPath),
            "prompt_snapshot_path": jsonValue(trace.promptSnapshotPath),
            "prompt_lab_case_path": promptLabURL.path,
            "raw_text": trace.rawText,
            "previous_corrected_text": jsonValue(trace.correctedText),
            "replay_corrected_text": result.text,
            "wall_ms": wallMilliseconds,
            "metadata": result.metadata,
            "timings": result.timings.map(payload(for:)),
            "debug": [
                "system_prompt": result.debugInfo.systemPrompt ?? "",
                "user_prompt": result.debugInfo.userPrompt ?? "",
                "raw_response": result.debugInfo.rawResponse ?? "",
                "cleaned_response": result.debugInfo.cleanedResponse ?? ""
            ]
        ]
        return try write(payload: payload, suffix: "trace-replay")
    }

    private static func writePromptLabCase(
        for trace: TranscriptionTraceSnapshot,
        sourceTraceURL: URL
    ) throws -> URL {
        let generationProfile = LocalLLMGenerationProfile.currentCorrection(for: trace.rawText)
        let promptConfiguration = LocalLLMPromptConfiguration.current
        let payload: [String: Any] = [
            "name": "trace-\(trace.shortID)",
            "model": LocalLLMSettingsStore.selectedModel.rawValue,
            "runs": 1,
            "punctuationStyle": promptConfiguration.punctuationStyle.rawValue,
            "removeFillerWords": promptConfiguration.removeFillerWords,
            "softenEmotionalLanguage": promptConfiguration.softenEmotionalLanguage,
            "outputStyle": promptConfiguration.outputStyle.rawValue,
            "outputStyleStrength": promptConfiguration.outputStyleStrength.rawValue,
            "reasoningMode": generationProfile.reasoningMode.rawValue,
            "maxTokens": jsonValue(generationProfile.maxTokens),
            "inputs": [
                [
                    "id": trace.shortID,
                    "text": trace.rawText,
                    "expected": jsonValue(trace.correctedText),
                    "allowFallback": false
                ]
            ],
            "metadata": [
                "source_trace_path": sourceTraceURL.path,
                "source_trace_id": trace.id,
                "recording_path": jsonValue(trace.recordingPath),
                "prompt_snapshot_path": jsonValue(trace.promptSnapshotPath)
            ]
        ]
        return try write(payload: payload, suffix: "prompt-lab-case")
    }

    private static func write(payload: [String: Any], suffix: String) throws -> URL {
        guard JSONSerialization.isValidJSONObject(payload) else {
            throw TraceReplayError.invalidOutputPayload
        }
        let data = try JSONSerialization.data(
            withJSONObject: payload,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        let directory = AppLog.directoryURL.appendingPathComponent("Replays", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let outputURL = directory.appendingPathComponent("\(timestamp())-\(suffix).json")
        try data.write(to: outputURL, options: .atomic)
        return outputURL
    }

    private static func payload(for timing: TraceTiming) -> [String: Any] {
        [
            "name": timing.name,
            "duration_ms": timing.milliseconds,
            "metadata": timing.metadata
        ]
    }

    private static func milliseconds(since start: TimeInterval) -> Int {
        Int(((ProcessInfo.processInfo.systemUptime - start) * 1000).rounded())
    }

    private static func jsonValue<T>(_ value: T?) -> Any {
        guard let value else { return NSNull() }
        return value
    }

    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss-SSS"
        return formatter.string(from: Date())
    }
}

struct TranscriptionTraceSnapshot {
    let id: String
    let outcome: String
    let rawText: String
    let correctedText: String?
    let recordingPath: String?
    let promptSnapshotPath: String?

    var shortID: String {
        String(id.prefix(8))
    }

    static func load(from url: URL) throws -> TranscriptionTraceSnapshot {
        let data = try Data(contentsOf: url)
        let object = try JSONSerialization.jsonObject(with: data)
        guard let payload = object as? [String: Any] else {
            throw TraceReplayError.invalidTrace
        }
        guard let metadata = payload["metadata"] as? [String: Any] else {
            throw TraceReplayError.missingMetadata
        }
        guard let rawText = string("raw_text", in: metadata), !rawText.isEmpty else {
            throw TraceReplayError.missingRawText
        }

        return TranscriptionTraceSnapshot(
            id: string("trace_id", in: payload) ?? url.deletingPathExtension().lastPathComponent,
            outcome: string("outcome", in: payload) ?? "unknown",
            rawText: rawText,
            correctedText: string("corrected_text", in: metadata),
            recordingPath: string("recording_path", in: metadata),
            promptSnapshotPath: string("correction.prompt_snapshot_path", in: metadata)
        )
    }

    private static func string(_ key: String, in payload: [String: Any]) -> String? {
        switch payload[key] {
        case let value as String:
            return value
        case let value as CustomStringConvertible:
            return String(describing: value)
        default:
            return nil
        }
    }
}

enum TraceReplayError: LocalizedError {
    case invalidTrace
    case missingMetadata
    case missingRawText
    case invalidOutputPayload

    var errorDescription: String? {
        switch self {
        case .invalidTrace:
            return "Trace file is not a JSON object."
        case .missingMetadata:
            return "Trace file has no metadata object."
        case .missingRawText:
            return "Trace metadata has no raw_text field. Capture a new trace before replaying."
        case .invalidOutputPayload:
            return "Could not serialize trace replay output."
        }
    }
}

private func progress(_ message: String) {
    fputs("\(message)\n", stderr)
    fflush(stderr)
}
