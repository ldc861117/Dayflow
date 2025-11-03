import XCTest
@testable import Dayflow

private final class GeminiTestURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
    static var lastRequest: URLRequest?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = GeminiTestURLProtocol.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (response, data) = try handler(request)
            GeminiTestURLProtocol.lastRequest = request
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

final class GeminiEndpointIntegrationTests: XCTestCase {
    let testDefaults = UserDefaults(suiteName: "test.GeminiEndpointIntegration")!
    
    override func setUp() {
        super.setUp()
        GeminiEndpointResolver.resetToDefaults(store: testDefaults)
    }
    
    override func tearDown() {
        GeminiEndpointResolver.resetToDefaults(store: testDefaults)
        super.tearDown()
    }
    
    func testCustomBaseURLIsRespectedByResolver() {
        let customHost = "https://proxy.example.com"
        
        var resolver = GeminiEndpointResolver(useCustomBase: true, customBase: customHost, store: testDefaults)
        resolver.save()
        
        let reloaded = GeminiEndpointResolver.load(store: testDefaults)
        
        XCTAssertTrue(reloaded.useCustomBase)
        XCTAssertEqual(reloaded.customBase, customHost)
        
        let modelEndpoint = reloaded.modelEndpoint(for: "gemini-2.5-flash-lite")
        XCTAssertTrue(modelEndpoint.hasPrefix(customHost), "Model endpoint should use custom host")
        XCTAssertTrue(modelEndpoint.contains("/v1beta/models/gemini-2.5-flash-lite:generateContent"))
        
        let uploadEndpoint = reloaded.fileUploadEndpoint()
        XCTAssertTrue(uploadEndpoint.hasPrefix(customHost), "Upload endpoint should use custom host")
        XCTAssertTrue(uploadEndpoint.contains("/upload/v1beta/files"))
    }
    
    func testAPIHelperUsesResolver() {
        let customHost = "https://custom-api.example.com"
        
        var resolver = GeminiEndpointResolver(useCustomBase: true, customBase: customHost)
        resolver.save()
        
        let loadedResolver = GeminiEndpointResolver.load()
        let expectedEndpoint = loadedResolver.modelEndpoint(for: "gemini-2.5-flash-lite")
        
        XCTAssertTrue(expectedEndpoint.contains("custom-api.example.com"))
        XCTAssertTrue(expectedEndpoint.contains("/v1beta/models/gemini-2.5-flash-lite:generateContent"))
    }
    
    func testTestConnectionUsesCustomHost() async throws {
        let customHost = "https://custom-api.example.com"
        var resolver = GeminiEndpointResolver(useCustomBase: true, customBase: customHost)
        resolver.save()
        
        defer {
            GeminiEndpointResolver.resetToDefaults()
            GeminiTestURLProtocol.handler = nil
            GeminiTestURLProtocol.lastRequest = nil
        }
        
        URLProtocol.registerClass(GeminiTestURLProtocol.self)
        defer { URLProtocol.unregisterClass(GeminiTestURLProtocol.self) }
        
        GeminiTestURLProtocol.handler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            let body = """
            {"candidates":[{"content":{"parts":[{"text":"Hi from Gemini!"}]}}]}
            """.data(using: .utf8)!
            return (response, body)
        }
        
        let text = try await GeminiAPIHelper.shared.testConnection(apiKey: "fake-key")
        XCTAssertEqual(text, "Hi from Gemini!")
        
        guard let request = GeminiTestURLProtocol.lastRequest else {
            XCTFail("Expected request to be captured")
            return
        }
        XCTAssertEqual(request.url?.host, "custom-api.example.com")
        XCTAssertTrue(request.url?.absoluteString.contains("/v1beta/models/gemini-2.5-flash-lite:generateContent") ?? false)
    }
    
    func testToggleOffResetsCustomBase() {
        var resolver = GeminiEndpointResolver(useCustomBase: true, customBase: "https://proxy.example.com", store: testDefaults)
        resolver.save()
        
        var toggled = GeminiEndpointResolver(useCustomBase: false, customBase: "https://proxy.example.com", store: testDefaults)
        toggled.save()
        
        let reloaded = GeminiEndpointResolver.load(store: testDefaults)
        XCTAssertFalse(reloaded.useCustomBase)
        XCTAssertNil(reloaded.customBase)
        
        XCTAssertEqual(reloaded.resolveBaseURL(), GeminiEndpointResolver.defaultBaseURL)
    }
    
    func testSettingEmptyCustomBaseRemovesIt() {
        var resolver = GeminiEndpointResolver(useCustomBase: true, customBase: "", store: testDefaults)
        resolver.save()
        
        let reloaded = GeminiEndpointResolver.load(store: testDefaults)
        XCTAssertTrue(reloaded.useCustomBase)
        XCTAssertNil(reloaded.customBase)
        
        XCTAssertEqual(reloaded.resolveBaseURL(), GeminiEndpointResolver.defaultBaseURL)
    }
    
    func testResolverNormalizesURLOnSave() {
        var resolver = GeminiEndpointResolver(useCustomBase: true, customBase: "https://example.com///path/to/api", store: testDefaults)
        resolver.save()
        
        let reloaded = GeminiEndpointResolver.load(store: testDefaults)
        XCTAssertEqual(reloaded.customBase, "https://example.com")
    }
}
