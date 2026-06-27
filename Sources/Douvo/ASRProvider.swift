import Foundation

enum ASRProvider: String, CaseIterable, Identifiable, Codable {
    case web
    case android
    case mix

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .web:
            "Web"
        case .android:
            "Android"
        case .mix:
            "Mix"
        }
    }

    var detail: String {
        switch self {
        case .web:
            "Doubao Web ASR"
        case .android:
            "Doubao IME protocol"
        case .mix:
            "Web + Android with AI merge"
        }
    }

    var usesWebASR: Bool {
        self == .web || self == .mix
    }

    var usesAndroidASR: Bool {
        self == .android || self == .mix
    }

    var activeProviderKeys: Set<String> {
        switch self {
        case .web:
            ["web"]
        case .android:
            ["android"]
        case .mix:
            ["web", "android"]
        }
    }
}

enum ASRProviderStore {
    private static let key = "asrProvider"

    static var selected: ASRProvider {
        get {
            guard let rawValue = UserDefaults.standard.string(forKey: key),
                  let provider = ASRProvider(rawValue: rawValue) else {
                return .web
            }
            return provider
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: key)
            AppLog.info("ASR provider set to \(newValue.rawValue)")
        }
    }
}
