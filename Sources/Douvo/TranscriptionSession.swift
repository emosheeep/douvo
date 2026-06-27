import Foundation

struct TranscriptionSessionError: Sendable {
    let domain: String
    let code: Int
    let localizedDescription: String

    init(_ error: Error?) {
        guard let error else {
            domain = "Douvo.ASR"
            code = 0
            localizedDescription = "unknown"
            return
        }

        let nsError = error as NSError
        domain = nsError.domain
        code = nsError.code
        localizedDescription = nsError.localizedDescription
    }
}

enum TranscriptionSessionEvent: Sendable {
    case audioStarted
    case audioLevel(Float)
    case recordingSaved(String)
    case asrOpened(String)
    case asrResult(ASRRecognitionResult)
    case asrFinished(String)
    case asrError(String, TranscriptionSessionError?)
    case asrAuthError(String)
}

actor TranscriptionSession {
    typealias EventHandler = @MainActor @Sendable (TranscriptionSessionEvent) -> Void

    private let provider: ASRProvider
    private let webASRClient: DoubaoASRClient?
    private let androidASRClient: DoubaoAndroidASRClient?
    private let audioCapture: AudioCaptureManager
    private let onEvent: EventHandler

    init(provider: ASRProvider, onEvent: @escaping EventHandler) {
        let webASRClient = provider.usesWebASR ? DoubaoASRClient() : nil
        let androidASRClient = provider.usesAndroidASR ? DoubaoAndroidASRClient() : nil
        let audioCapture = AudioCaptureManager()
        self.provider = provider
        self.webASRClient = webASRClient
        self.androidASRClient = androidASRClient
        self.audioCapture = audioCapture
        self.onEvent = onEvent

        let onResult: (ASRRecognitionResult) -> Void = { [weak self] result in
            Task { await self?.emit(.asrResult(result)) }
        }

        webASRClient?.onOpen = { [weak self] in
            Task { await self?.emit(.asrOpened("web")) }
        }
        webASRClient?.onResult = onResult
        webASRClient?.onFinish = { [weak self] in
            Task { await self?.emit(.asrFinished("web")) }
        }
        webASRClient?.onError = { [weak self] error in
            let info = TranscriptionSessionError(error)
            Task { await self?.emit(.asrError("web", info)) }
        }
        webASRClient?.onAuthError = { [weak self] in
            Task { await self?.emit(.asrAuthError("web")) }
        }

        androidASRClient?.onOpen = { [weak self] in
            Task { await self?.emit(.asrOpened("android")) }
        }
        androidASRClient?.onResult = onResult
        androidASRClient?.onFinish = { [weak self] in
            Task { await self?.emit(.asrFinished("android")) }
        }
        androidASRClient?.onError = { [weak self] error in
            let info = TranscriptionSessionError(error)
            Task { await self?.emit(.asrError("android", info)) }
        }
        androidASRClient?.onAuthError = { [weak self] in
            Task { await self?.emit(.asrAuthError("android")) }
        }

        audioCapture.onWebPCMData = { [weak webASRClient] data in
            webASRClient?.sendAudio(data)
        }
        audioCapture.onAndroidOpusData = { [weak androidASRClient] data in
            androidASRClient?.sendAudio(data)
        }
        audioCapture.onLevel = { [weak self] level in
            Task { await self?.emit(.audioLevel(level)) }
        }
    }

    func start(webParams: DoubaoASRParams?) async throws {
        switch provider {
        case .web:
            guard let webParams, let webASRClient else {
                throw NSError(domain: "Douvo.ASR", code: 10, userInfo: [NSLocalizedDescriptionKey: "Web ASR parameters are missing"])
            }
            webASRClient.connect(params: webParams)
            do {
                try audioCapture.startCapture(mode: .webPCM)
            } catch {
                webASRClient.disconnect()
                throw error
            }
            await emit(.audioStarted)
        case .android:
            guard let androidASRClient else {
                throw NSError(domain: "Douvo.ASR", code: 11, userInfo: [NSLocalizedDescriptionKey: "Android ASR client is unavailable"])
            }
            let credentials = try await DoubaoAndroidCredentialStore.ensureCredentials()
            androidASRClient.connect(credentials: credentials)
            do {
                try audioCapture.startCapture(mode: .androidOpus)
            } catch {
                androidASRClient.disconnect()
                throw error
            }
            await emit(.audioStarted)
        case .mix:
            guard let webParams, let webASRClient, let androidASRClient else {
                throw NSError(domain: "Douvo.ASR", code: 12, userInfo: [NSLocalizedDescriptionKey: "Mix ASR clients are unavailable"])
            }
            let credentials = try await DoubaoAndroidCredentialStore.ensureCredentials()
            webASRClient.connect(params: webParams)
            androidASRClient.connect(credentials: credentials)
            do {
                try audioCapture.startCapture(mode: .webPCMAndAndroidOpus)
            } catch {
                webASRClient.disconnect()
                androidASRClient.disconnect()
                throw error
            }
            await emit(.audioStarted)
        }
    }

    func stop() async -> URL? {
        let recordingURL = audioCapture.stopCapture()
        if let recordingURL {
            await emit(.recordingSaved(recordingURL.path))
        }
        webASRClient?.finishSending()
        androidASRClient?.finishSending()
        return recordingURL
    }

    func cancel() {
        _ = audioCapture.stopCapture()
        webASRClient?.disconnect()
        androidASRClient?.disconnect()
    }

    private func emit(_ event: TranscriptionSessionEvent) async {
        await onEvent(event)
    }
}
