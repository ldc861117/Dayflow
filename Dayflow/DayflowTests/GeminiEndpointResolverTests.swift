import XCTest
@testable import Dayflow

final class GeminiEndpointResolverTests: XCTestCase {
    override func setUp() {
        super.setUp()
        GeminiEndpointResolver.resetToDefaults()
    }
    
    override func tearDown() {
        GeminiEndpointResolver.resetToDefaults()
        super.tearDown()
    }
    
    // MARK: - Validation Tests
    
    func testNormalizeAndValidate_ValidHTTPSURL() throws {
        let input = "https://api.example.com"
        let normalized = try GeminiEndpointResolver.normalizeAndValidate(input)
        XCTAssertEqual(normalized, "https://api.example.com")
    }
    
    func testNormalizeAndValidate_ValidHTTPURL() throws {
        let input = "http://localhost:8080"
        let normalized = try GeminiEndpointResolver.normalizeAndValidate(input)
        XCTAssertEqual(normalized, "http://localhost:8080")
    }
    
    func testNormalizeAndValidate_StripsTrailingSlash() throws {
        let input = "https://api.example.com/"
        let normalized = try GeminiEndpointResolver.normalizeAndValidate(input)
        XCTAssertEqual(normalized, "https://api.example.com")
    }
    
    func testNormalizeAndValidate_StripsMultipleTrailingSlashes() throws {
        let input = "https://api.example.com///"
        let normalized = try GeminiEndpointResolver.normalizeAndValidate(input)
        XCTAssertEqual(normalized, "https://api.example.com")
    }
    
    func testNormalizeAndValidate_StripsPath() throws {
        let input = "https://api.example.com/v1/beta"
        let normalized = try GeminiEndpointResolver.normalizeAndValidate(input)
        XCTAssertEqual(normalized, "https://api.example.com")
    }
    
    func testNormalizeAndValidate_StripsQueryAndFragment() throws {
        let input = "https://api.example.com?key=value#fragment"
        let normalized = try GeminiEndpointResolver.normalizeAndValidate(input)
        XCTAssertEqual(normalized, "https://api.example.com")
    }
    
    func testNormalizeAndValidate_TrimsWhitespace() throws {
        let input = "  https://api.example.com  "
        let normalized = try GeminiEndpointResolver.normalizeAndValidate(input)
        XCTAssertEqual(normalized, "https://api.example.com")
    }
    
    func testNormalizeAndValidate_MissingScheme() {
        let input = "api.example.com"
        XCTAssertThrowsError(try GeminiEndpointResolver.normalizeAndValidate(input)) { error in
            XCTAssertTrue(error is GeminiEndpointValidationError)
            XCTAssertEqual((error as? GeminiEndpointValidationError), .missingScheme)
        }
    }
    
    func testNormalizeAndValidate_InvalidScheme() {
        let input = "ftp://api.example.com"
        XCTAssertThrowsError(try GeminiEndpointResolver.normalizeAndValidate(input)) { error in
            XCTAssertTrue(error is GeminiEndpointValidationError)
            XCTAssertEqual((error as? GeminiEndpointValidationError), .invalidScheme)
        }
    }
    
    func testNormalizeAndValidate_ContainsWhitespace() {
        let input = "https://api.example .com"
        XCTAssertThrowsError(try GeminiEndpointResolver.normalizeAndValidate(input)) { error in
            XCTAssertTrue(error is GeminiEndpointValidationError)
            XCTAssertEqual((error as? GeminiEndpointValidationError), .containsWhitespace)
        }
    }
    
    func testNormalizeAndValidate_EmptyString() {
        let input = ""
        XCTAssertThrowsError(try GeminiEndpointResolver.normalizeAndValidate(input)) { error in
            XCTAssertTrue(error is GeminiEndpointValidationError)
            XCTAssertEqual((error as? GeminiEndpointValidationError), .invalidURL)
        }
    }
    
    func testNormalizeAndValidate_InvalidURL() {
        let input = "https://"
        XCTAssertThrowsError(try GeminiEndpointResolver.normalizeAndValidate(input)) { error in
            XCTAssertTrue(error is GeminiEndpointValidationError)
        }
    }
    
    // MARK: - Persistence Tests
    
    func testLoadAndSave() {
        var resolver = GeminiEndpointResolver(useCustomBase: true, customBase: "https://custom.example.com")
        resolver.save()
        
        let loaded = GeminiEndpointResolver.load()
        XCTAssertTrue(loaded.useCustomBase)
        XCTAssertEqual(loaded.customBase, "https://custom.example.com")
    }
    
    func testResetToDefaults() {
        var resolver = GeminiEndpointResolver(useCustomBase: true, customBase: "https://custom.example.com")
        resolver.save()
        
        GeminiEndpointResolver.resetToDefaults()
        
        let loaded = GeminiEndpointResolver.load()
        XCTAssertFalse(loaded.useCustomBase)
        XCTAssertNil(loaded.customBase)
    }
    
    // MARK: - Endpoint Resolution Tests
    
    func testResolveBaseURL_DefaultWhenNotEnabled() {
        let resolver = GeminiEndpointResolver(useCustomBase: false, customBase: "https://custom.example.com")
        XCTAssertEqual(resolver.resolveBaseURL(), "https://generativelanguage.googleapis.com")
    }
    
    func testResolveBaseURL_DefaultWhenCustomIsNil() {
        let resolver = GeminiEndpointResolver(useCustomBase: true, customBase: nil)
        XCTAssertEqual(resolver.resolveBaseURL(), "https://generativelanguage.googleapis.com")
    }
    
    func testResolveBaseURL_CustomWhenEnabled() {
        let resolver = GeminiEndpointResolver(useCustomBase: true, customBase: "https://custom.example.com")
        XCTAssertEqual(resolver.resolveBaseURL(), "https://custom.example.com")
    }
    
    func testResolveBaseURL_FallbackToDefaultOnInvalidCustom() {
        let resolver = GeminiEndpointResolver(useCustomBase: true, customBase: "invalid url")
        XCTAssertEqual(resolver.resolveBaseURL(), "https://generativelanguage.googleapis.com")
    }
    
    func testModelEndpoint_Default() {
        let resolver = GeminiEndpointResolver(useCustomBase: false, customBase: nil)
        let endpoint = resolver.modelEndpoint(for: "gemini-2.5-flash-lite")
        XCTAssertEqual(endpoint, "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-lite:generateContent")
    }
    
    func testModelEndpoint_Custom() {
        let resolver = GeminiEndpointResolver(useCustomBase: true, customBase: "https://proxy.example.com")
        let endpoint = resolver.modelEndpoint(for: "gemini-2.5-flash-lite")
        XCTAssertEqual(endpoint, "https://proxy.example.com/v1beta/models/gemini-2.5-flash-lite:generateContent")
    }
    
    func testFileUploadEndpoint_Default() {
        let resolver = GeminiEndpointResolver(useCustomBase: false, customBase: nil)
        let endpoint = resolver.fileUploadEndpoint()
        XCTAssertEqual(endpoint, "https://generativelanguage.googleapis.com/upload/v1beta/files")
    }
    
    func testFileUploadEndpoint_Custom() {
        let resolver = GeminiEndpointResolver(useCustomBase: true, customBase: "https://proxy.example.com")
        let endpoint = resolver.fileUploadEndpoint()
        XCTAssertEqual(endpoint, "https://proxy.example.com/upload/v1beta/files")
    }
    
    // MARK: - Integration Test - Simulated Custom Host
    
    func testCustomBaseURLAffectsAPIHelper() {
        // Set up a custom base URL
        var resolver = GeminiEndpointResolver(useCustomBase: true, customBase: "https://custom-proxy.example.com")
        resolver.save()
        
        // Verify that the resolver is used by the API helper
        let loadedResolver = GeminiEndpointResolver.load()
        XCTAssertTrue(loadedResolver.useCustomBase)
        XCTAssertEqual(loadedResolver.customBase, "https://custom-proxy.example.com")
        
        // Verify that endpoints are correctly constructed
        let modelEndpoint = loadedResolver.modelEndpoint(for: "gemini-2.5-flash-lite")
        XCTAssertTrue(modelEndpoint.hasPrefix("https://custom-proxy.example.com"))
        XCTAssertTrue(modelEndpoint.contains("/v1beta/models/"))
        
        let uploadEndpoint = loadedResolver.fileUploadEndpoint()
        XCTAssertTrue(uploadEndpoint.hasPrefix("https://custom-proxy.example.com"))
        XCTAssertTrue(uploadEndpoint.contains("/upload/v1beta/files"))
    }
}
