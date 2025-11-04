# Technical Design Document: Gemini Custom Endpoint 404 Fix

**Author**: @architect-evolver
**Date**: 2025-11-04
**Status**: Ready for Implementation

## 1. Overview

This document outlines the necessary changes to resolve a persistent "404 Not Found" error occurring during video uploads to a custom Gemini endpoint. The investigation has concluded that the custom endpoint does not support the resumable upload protocol (`/upload/v1beta/files`) currently used in `GeminiDirectProvider.swift`.

The architectural solution is to introduce a conditional upload mechanism. When a custom base URL is configured, the system will switch to an `inline_data` upload method, which is confirmed to be supported by the custom endpoint. The existing resumable upload will be retained for the standard Google endpoints.

## 2. System Component Diagram

```
[Dayflow App]
      |
      v
[GeminiDirectProvider.transcribeVideo]
      |
      +-----> [isUsingCustomBase?] --(YES)--> [transcribeVideoWithInlineData] (NEW)
      |                                           |
      |                                           v
      |                             [POST to {custom_base}/v1beta/models/gemini-2.5-pro:generateContent]
      |                                     (with inline_data)
      |
      +-----> [isUsingCustomBase?] --(NO)---> [uploadAndAwait] -> [geminiTranscribeRequest] (EXISTING)
                                                  |
                                                  v
                                    [Resumable upload to generativelanguage.googleapis.com]
```

## 3. Technical Specifications

The following changes are to be implemented in `Dayflow/Dayflow/Core/AI/GeminiDirectProvider.swift`.

### 3.1. Robust URL Construction

The `buildRequestURL` function must be modified to prevent the creation of URLs with double slashes (`//`) when combining a base URL and a path.

**File**: `Dayflow/Dayflow/Core/AI/GeminiDirectProvider.swift`
**Function**: `private func buildRequestURL(path: String) throws -> URL`

**Logic**:
1.  Get the `base` URL from `resolveBaseURL()`.
2.  If the `base` URL has a trailing slash, remove it.
3.  Ensure the `path` has a leading slash.
4.  Combine the modified `base` and `path` to form the final URL.

**Reference Implementation**:
```swift
private func buildRequestURL(path: String) throws -> URL {
    var base = resolveBaseURL()
    // Ensure base URL doesn't have a trailing slash
    if base.hasSuffix("/") {
        base = String(base.dropLast())
    }
    
    // Ensure path has a leading slash
    let finalPath = path.hasPrefix("/") ? path : "/" + path
    
    guard let url = URL(string: base + finalPath) else {
        throw GeminiAPIHelper.APIError.invalidURL(description: "Invalid endpoint URL: \(base + finalPath)")
    }
    
    if isUsingCustomBase {
        return url
    } else {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw GeminiAPIHelper.APIError.invalidURL(description: "Invalid URL components for: \(url)")
        }
        components.queryItems = (components.queryItems ?? []) + [URLQueryItem(name: "key", value: apiKey)]
        guard let finalURL = components.url else {
            throw GeminiAPIHelper.APIError.invalidURL(description: "Could not construct final URL from components for: \(url)")
        }
        return finalURL
    }
}
```

### 3.2. New `transcribeVideoWithInlineData` Function

A new private function must be created to handle video transcription using the `inline_data` method. This function will encapsulate the logic from the working Python script.

**File**: `Dayflow/Dayflow/Core/AI/GeminiDirectProvider.swift`
**Function**: `private func transcribeVideoWithInlineData(videoData: Data, mimeType: String, prompt: String, batchId: Int64?, groupId: String, model: GeminiModel, attempt: Int) async throws -> (String, String)`

**Logic**:
1.  Base64-encode the `videoData`.
2.  Construct the `requestBody` JSON payload with the `inline_data` field, mirroring the Python script's structure.
3.  Build the request to the `generateContent` endpoint (e.g., `/v1beta/models/gemini-2.5-pro:generateContent`).
4.  Set the appropriate headers (`x-goog-api-key`, `Content-Type`).
5.  Execute the request using `URLSession.shared.data(for: request)`.
6.  Perform error handling and response parsing similar to the existing `geminiTranscribeRequest` function.
7.  Return the transcribed text and the model used.

### 3.3. Update `transcribeVideo` Dispatcher Logic

The main `transcribeVideo` function must be updated to act as a dispatcher, choosing the correct upload method based on the configuration.

**File**: `Dayflow/Dayflow/Core/AI/GeminiDirectProvider.swift`
**Function**: `func transcribeVideo(...) async throws -> (observations: [Observation], log: LLMCall)`

**Logic**:
1.  Inside the `while attempt < maxRetries` loop, before calling the upload/transcription logic, add a condition:
    ```swift
    if isUsingCustomBase {
        // Call the new inline data transcription method
        let (response, usedModel) = try await transcribeVideoWithInlineData(
            videoData: videoData,
            mimeType: mimeType,
            prompt: finalTranscriptionPrompt,
            batchId: batchId,
            groupId: callGroupId,
            model: activeModel,
            attempt: attempt + 1
        )
        // ... proceed with parsing and validation as before
    } else {
        // Use the existing resumable upload flow
        let fileURI = try await uploadAndAwait(tempURL, mimeType: mimeType, key: apiKey).1
        let (response, usedModel) = try await geminiTranscribeRequest(
            fileURI: fileURI,
            // ... other parameters
        )
        // ... proceed with parsing and validation as before
    }
    ```
2.  The `videoData` will need to be passed into the `while` loop. The temporary file creation can remain, as it's still needed for the resumable path.

## 4. Task Breakdown

1.  **Implement `buildRequestURL` modification**: Apply the changes specified in section 3.1.
2.  **Create `transcribeVideoWithInlineData` function**: Implement the new function as specified in section 3.2.
3.  **Update `transcribeVideo` dispatcher**: Modify the main `transcribeVideo` function to include the conditional logic from section 3.3.

This concludes the technical design. The task is now ready for delegation to `@technical-maestro`.