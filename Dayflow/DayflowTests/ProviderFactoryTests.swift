//
//  ProviderFactoryTests.swift
//  DayflowTests
//

import XCTest
@testable import Dayflow

final class ProviderFactoryTests: XCTestCase {
    private var mockKeychainManager: MockKeychainManager!
    private var mockUserDefaults: MockUserDefaults!
    private var providerFactory: ProviderFactory!
    
    override func setUp() async throws {
        mockKeychainManager = MockKeychainManager()
        mockUserDefaults = MockUserDefaults()
        providerFactory = ProviderFactory(
            keychainManager: mockKeychainManager,
            userDefaults: mockUserDefaults
        )
    }
    
    override func tearDown() async throws {
        await providerFactory.stopChangeObservation()
    }
    
    func testGetProviderType_DefaultsToGemini() async throws {
        // Given: No provider type saved
        mockUserDefaults.data = nil
        
        // When: Getting provider type
        let providerType = await providerFactory.getProviderType()
        
        // Then: Should default to Gemini
        XCTAssertEqual(providerType, .geminiDirect)
    }
    
    func testGetProviderType_SavedProvider() async throws {
        // Given: Saved provider type
        let savedProvider = LLMProviderType.dayflowBackend(endpoint: "https://test.example.com")
        let encodedData = try JSONEncoder().encode(savedProvider)
        mockUserDefaults.data = encodedData
        
        // When: Getting provider type
        let providerType = await providerFactory.getProviderType()
        
        // Then: Should return saved provider
        XCTAssertEqual(providerType, savedProvider)
    }
    
    func testGetProviderType_MigratesDeprecatedProvider() async throws {
        // Given: Deprecated ChatGPT/Claude provider
        let deprecatedProvider = LLMProviderType.chatGPTClaude
        let encodedData = try JSONEncoder().encode(deprecatedProvider)
        mockUserDefaults.data = encodedData
        
        // When: Getting provider type
        let providerType = await providerFactory.getProviderType()
        
        // Then: Should migrate to Gemini (no Dayflow token)
        XCTAssertEqual(providerType, .geminiDirect)
        
        // And: Should persist the migrated choice
        let persistedData = mockUserDefaults.data
        let persistedProvider = try JSONDecoder().decode(LLMProviderType.self, from: persistedData!)
        XCTAssertEqual(persistedProvider, .geminiDirect)
    }
    
    func testGetProviderType_MigratesToDayflowWhenTokenAvailable() async throws {
        // Given: Deprecated provider with Dayflow token
        let deprecatedProvider = LLMProviderType.chatGPTClaude
        let encodedData = try JSONEncoder().encode(deprecatedProvider)
        mockUserDefaults.data = encodedData
        mockKeychainManager.token = "test-dayflow-token"
        
        // When: Getting provider type
        let providerType = await providerFactory.getProviderType()
        
        // Then: Should migrate to Dayflow backend
        XCTAssertEqual(providerType, .dayflowBackend(endpoint: "https://api.dayflow.app"))
    }
    
    func testGetProvider_CreatesGeminiProvider() async throws {
        // Given: Gemini provider type with API key
        mockKeychainManager.token = "test-gemini-key"
        mockUserDefaults.data = try JSONEncoder().encode(LLMProviderType.geminiDirect)
        
        // When: Getting provider
        let provider = try await providerFactory.getProvider()
        
        // Then: Should create Gemini provider
        XCTAssertTrue(provider is GeminiDirectProvider)
    }
    
    func testGetProvider_CreatesDayflowProvider() async throws {
        // Given: Dayflow provider type with token
        mockKeychainManager.token = "test-dayflow-key"
        mockUserDefaults.data = try JSONEncoder().encode(LLMProviderType.dayflowBackend())
        
        // When: Getting provider
        let provider = try await providerFactory.getProvider()
        
        // Then: Should create Dayflow provider
        XCTAssertTrue(provider is DayflowBackendProvider)
    }
    
    func testGetProvider_CreatesOllamaProvider() async throws {
        // Given: Ollama provider type
        mockUserDefaults.data = try JSONEncoder().encode(LLMProviderType.ollamaLocal())
        
        // When: Getting provider
        let provider = try await providerFactory.getProvider()
        
        // Then: Should create Ollama provider
        XCTAssertTrue(provider is OllamaProvider)
    }
    
    func testGetProvider_ThrowsWhenNoGeminiKey() async throws {
        // Given: Gemini provider type but no API key
        mockKeychainManager.token = nil
        mockUserDefaults.data = try JSONEncoder().encode(LLMProviderType.geminiDirect)
        
        // When & Then: Should throw error
        do {
            _ = try await providerFactory.getProvider()
            XCTFail("Expected error to be thrown")
        } catch let error as LLMServiceError {
            XCTAssertEqual(error, .providerCreationFailed("Failed to retrieve Gemini API key from Keychain"))
        }
    }
    
    func testGetProvider_ThrowsWhenNoDayflowToken() async throws {
        // Given: Dayflow provider type but no token
        mockKeychainManager.token = nil
        mockUserDefaults.data = try JSONEncoder().encode(LLMProviderType.dayflowBackend())
        
        // When & Then: Should throw error
        do {
            _ = try await providerFactory.getProvider()
            XCTFail("Expected error to be thrown")
        } catch let error as LLMServiceError {
            XCTAssertEqual(error, .providerCreationFailed("Failed to retrieve Dayflow token from Keychain"))
        }
    }
    
    func testGetProvider_UsesCache() async throws {
        // Given: Provider created once
        mockKeychainManager.token = "test-gemini-key"
        mockUserDefaults.data = try JSONEncoder().encode(LLMProviderType.geminiDirect)
        
        let provider1 = try await providerFactory.getProvider()
        let provider2 = try await providerFactory.getProvider()
        
        // Then: Should return same instance (cached)
        XCTAssertTrue(provider1 === provider2)
    }
    
    func testInvalidateCache_ForcesProviderRecreation() async throws {
        // Given: Provider created and cached
        mockKeychainManager.token = "test-gemini-key"
        mockUserDefaults.data = try JSONEncoder().encode(LLMProviderType.geminiDirect)
        
        let provider1 = try await providerFactory.getProvider()
        
        // When: Cache is invalidated
        await providerFactory.invalidateCache()
        
        // Then: Should create new instance
        let provider2 = try await providerFactory.getProvider()
        XCTAssertTrue(provider1 !== provider2)
    }
}

// MARK: - Mock Classes

class MockKeychainManager {
    var token: String?
    
    func retrieve(for provider: String) -> String? {
        return token
    }
}

class MockUserDefaults: UserDefaults {
    var data: Data?
    
    override func data(forKey defaultName: String) -> Data? {
        if defaultName == "llmProviderType" {
            return data
        }
        return super.data(forKey: defaultName)
    }
    
    override func set(_ value: Any?, forKey defaultName: String) {
        if defaultName == "llmProviderType", let dataValue = value as? Data {
            data = dataValue
        } else {
            super.set(value, forKey: defaultName)
        }
    }
}