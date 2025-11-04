import Foundation

enum GeminiEndpointValidationError: LocalizedError, Equatable {
    case missingScheme
    case invalidScheme
    case invalidURL
    case containsWhitespace
    case missingHost

    var errorDescription: String? {
        switch self {
        case .missingScheme:
            return "Base URL must include http:// or https://"
        case .invalidScheme:
            return "Base URL must use http:// or https://"
        case .invalidURL:
            return "Invalid URL format"
        case .containsWhitespace:
            return "Base URL cannot contain whitespace"
        case .missingHost:
            return "Base URL must have a valid host"
        }
    }
}

struct GeminiEndpointResolver {
    static let defaultBaseURL = "https://generativelanguage.googleapis.com"

    private static let useCustomKey = "useCustomGeminiBaseURL"
    private static let customBaseKey = "customGeminiBaseURL"

    private(set) var useCustomBase: Bool
    private(set) var customBase: String?
    private let store: UserDefaults

    init(useCustomBase: Bool, customBase: String?, store: UserDefaults = .standard) {
        self.useCustomBase = useCustomBase
        self.customBase = customBase
        self.store = store
    }

    static func load(store: UserDefaults = .standard) -> GeminiEndpointResolver {
        let useCustom = store.bool(forKey: useCustomKey)
        let customBase = store.string(forKey: customBaseKey)
        return GeminiEndpointResolver(useCustomBase: useCustom, customBase: customBase, store: store)
    }

    mutating func save() {
        store.set(useCustomBase, forKey: Self.useCustomKey)

        if useCustomBase, let customBase, !customBase.isEmpty {
            let normalized = (try? Self.normalizeAndValidate(customBase)) ?? customBase
            store.set(normalized, forKey: Self.customBaseKey)
            self.customBase = normalized
        } else {
            store.removeObject(forKey: Self.customBaseKey)
            self.customBase = nil
        }
    }

    static func resetToDefaults(store: UserDefaults = .standard) {
        store.removeObject(forKey: useCustomKey)
        store.removeObject(forKey: customBaseKey)
    }

    static func normalizeAndValidate(_ input: String) throws -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw GeminiEndpointValidationError.invalidURL }

        if trimmed.rangeOfCharacter(from: .whitespacesAndNewlines) != nil {
            throw GeminiEndpointValidationError.containsWhitespace
        }

        guard var components = URLComponents(string: trimmed) else {
            throw GeminiEndpointValidationError.invalidURL
        }

        guard let rawScheme = components.scheme else {
            throw GeminiEndpointValidationError.missingScheme
        }

        let scheme = rawScheme.lowercased()
        guard scheme == "http" || scheme == "https" else {
            throw GeminiEndpointValidationError.invalidScheme
        }
        components.scheme = scheme

        guard let host = components.host, !host.isEmpty else {
            throw GeminiEndpointValidationError.missingHost
        }

        components.user = nil
        components.password = nil
        components.path = ""
        components.query = nil
        components.fragment = nil

        guard var urlString = components.url?.absoluteString else {
            throw GeminiEndpointValidationError.invalidURL
        }

        let minimumLength = scheme.count + 3 // e.g. https://
        while urlString.count > minimumLength, urlString.hasSuffix("/") {
            urlString.removeLast()
        }

        return urlString
    }

    func resolveBaseURL() -> String {
        guard useCustomBase, let customBase else {
            return Self.defaultBaseURL
        }

        if let normalized = try? Self.normalizeAndValidate(customBase) {
            return normalized
        }

        return Self.defaultBaseURL
    }

    func modelEndpoint(for model: String) -> String {
        let base = resolveBaseURL()
        return "\(base)/v1beta/models/\(model):generateContent"
    }

    func fileUploadEndpoint() -> String {
        let base = resolveBaseURL()
        return "\(base)/upload/v1beta/files"
    }
}
