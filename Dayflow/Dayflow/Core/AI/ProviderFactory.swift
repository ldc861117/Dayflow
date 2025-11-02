//
//  ProviderFactory.swift
//  Dayflow
//

import Foundation
import Combine

/// Manages provider discovery, creation, and caching with change observation
actor ProviderFactory {
    private let keychainManager: KeychainManager
    private let userDefaults: UserDefaults
    private var cachedProvider: (type: LLMProviderType, provider: LLMProvider)?
    private var cachedProviderType: LLMProviderType?
    private var changeObserver: NSObjectProtocol?
    
    init(keychainManager: KeychainManager = .shared, userDefaults: UserDefaults = .standard) {
        self.keychainManager = keychainManager
        self.userDefaults = userDefaults
    }
    
    /// Gets the current provider type, loading from cache or UserDefaults
    func getProviderType() async -> LLMProviderType {
        if let cached = cachedProviderType {
            return cached
        }
        
        let providerType = loadProviderTypeFromStorage()
        cachedProviderType = providerType
        return providerType
    }
    
    /// Gets the current provider, creating and caching if necessary
    func getProvider() async throws -> LLMProvider {
        let providerType = await getProviderType()
        
        // Check if we have a cached provider for this type
        if let cached = cachedProvider, cached.type == providerType {
            return cached.provider
        }
        
        // Create new provider
        let provider = try createProvider(for: providerType)
        cachedProvider = (providerType, provider)
        return provider
    }
    
    /// Invalidates the cache, forcing reload on next access
    func invalidateCache() async {
        cachedProvider = nil
        cachedProviderType = nil
    }
    
    /// Starts observing provider configuration changes
    func startChangeObservation() async {
        await invalidateCache()
        
        // Observe UserDefaults changes
        changeObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            Task { [weak self] in
                await self?.handleConfigurationChange()
            }
        }
    }
    
    /// Stops observing configuration changes
    func stopChangeObservation() async {
        if let observer = changeObserver {
            NotificationCenter.default.removeObserver(observer)
            changeObserver = nil
        }
    }
    
    // MARK: - Private Methods
    
    private func loadProviderTypeFromStorage() -> LLMProviderType {
        guard let savedData = userDefaults.data(forKey: "llmProviderType") else {
            print("⚠️ [ProviderFactory] No saved provider type in UserDefaults - defaulting to Gemini")
            return .geminiDirect
        }
        
        do {
            let decoded = try JSONDecoder().decode(LLMProviderType.self, from: savedData)
            
            // Handle migration of deprecated providers
            if case .chatGPTClaude = decoded {
                return migrateDeprecatedProvider()
            }
            
            return decoded
        } catch {
            print("❌ [ProviderFactory] Failed to decode provider type: \(error)")
            return .geminiDirect
        }
    }
    
    private func migrateDeprecatedProvider() -> LLMProviderType {
        let fallbackType: LLMProviderType = {
            if let dayflowToken = keychainManager.retrieve(for: "dayflow"), !dayflowToken.isEmpty {
                print("   ↳ Found Dayflow backend credentials. Migrating to Dayflow backend provider.")
                return .dayflowBackend()
            }
            
            print("   ↳ No Dayflow token detected. Migrating to Gemini Direct provider.")
            return .geminiDirect
        }()
        
        // Persist the migrated choice
        do {
            let encodedFallback = try JSONEncoder().encode(fallbackType)
            userDefaults.set(encodedFallback, forKey: "llmProviderType")
            print("✅ [ProviderFactory] Persisted migrated provider selection: \(fallbackType)")
        } catch {
            print("❌ [ProviderFactory] Failed to persist migrated provider selection: \(error)")
        }
        
        return fallbackType
    }
    
    private func createProvider(for type: LLMProviderType) throws -> LLMProvider {
        switch type {
        case .geminiDirect:
            return try createGeminiProvider()
        case .dayflowBackend(let endpoint):
            return try createDayflowProvider(endpoint: endpoint)
        case .ollamaLocal(let endpoint):
            return OllamaProvider(endpoint: endpoint)
        case .chatGPTClaude:
            // This should have been migrated, but handle gracefully
            print("⚠️ [ProviderFactory] Received deprecated ChatGPT/Claude provider after migration. Falling back to Gemini Direct.")
            return try createGeminiProvider()
        }
    }
    
    private func createGeminiProvider() throws -> LLMProvider {
        guard let apiKey = keychainManager.retrieve(for: "gemini"), !apiKey.isEmpty else {
            throw LLMServiceError.providerCreationFailed("Failed to retrieve Gemini API key from Keychain")
        }
        
        let preference = GeminiModelPreference.load()
        return GeminiDirectProvider(apiKey: apiKey, preference: preference)
    }
    
    private func createDayflowProvider(endpoint: String) throws -> LLMProvider {
        guard let token = keychainManager.retrieve(for: "dayflow"), !token.isEmpty else {
            throw LLMServiceError.providerCreationFailed("Failed to retrieve Dayflow token from Keychain")
        }
        
        return DayflowBackendProvider(token: token, endpoint: endpoint)
    }
    
    private func handleConfigurationChange() async {
        // Check if the provider type actually changed
        let newProviderType = loadProviderTypeFromStorage()
        let currentProviderType = await getProviderType()
        
        if newProviderType != currentProviderType {
            print("🔄 [ProviderFactory] Provider configuration changed, invalidating cache")
            await invalidateCache()
        }
    }
}