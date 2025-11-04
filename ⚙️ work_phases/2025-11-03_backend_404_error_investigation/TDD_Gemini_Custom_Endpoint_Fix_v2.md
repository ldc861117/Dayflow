# Technical Design Document v2: Gemini Custom Endpoint 404 Fix

**Author**: @architect-evolver
**Date**: 2025-11-04
**Status**: Revised - Ready for Implementation

## 1. Overview & Revision History

**V1**: Proposed a conditional upload logic to handle custom Gemini endpoints.
**V2**: This version. The V1 implementation by `@technical-maestro` failed due to significant syntax and scope errors, including placing a new function inside an existing one. This revised TDD provides explicit, line-by-line instructions to prevent a repeat of this failure.

The objective remains the same: resolve the "404 Not Found" error by using an `inline_data` upload method for custom endpoints while retaining the resumable upload for standard endpoints.

## 2. Root Cause of Previous Failure

The previous implementation failed because the `transcribeVideoWithInlineData` function was inserted into the middle of the `getFileStatus` function in `GeminiDirectProvider.swift`. This is a critical structural error that must be corrected.

## 3. Detailed Technical Specifications

All changes will be made in `Dayflow/Dayflow/Core/AI/GeminiDirectProvider.swift`.

### 3.1. **NO CHANGE**: `buildRequestURL` Function

The previous change to `buildRequestURL` was correct in principle but could not be applied. It should be re-applied as specified in the original TDD.

### 3.2. **CRITICAL**: Placement of the new `transcribeVideoWithInlineData` function

A new private function must be created to handle video transcription using the `inline_data` method.

**ACTION**: Insert the entire `transcribeVideoWithInlineData` function block **AFTER** the closing brace `}` of the `transcribeVideo` function and **BEFORE** the `// MARK: - Error Classification for Unified Retry` comment.

**File**: `Dayflow/Dayflow/Core/AI/GeminiDirectProvider.swift`

**Reference Implementation for the new function**:
```swift
private func transcribeVideoWithInlineData(videoData: Data, mimeType: String, prompt: String, batchId: Int64?, groupId: String, model: GeminiModel, attempt: Int) async throws -> (String, String) {
    let base64Video = videoData.base64EncodedString()

    let transcriptionSchema: [String:Any] = [
      "type":"ARRAY",
      "items": [
        "type":"OBJECT",
        "properties":[
          "startTimestamp":["type":"STRING"],
          "endTimestamp":  ["type":"STRING"],
          "description":   ["type":"STRING"]
        ],
        "required":["startTimestamp","endTimestamp","description"],
        "propertyOrdering":["startTimestamp","endTimestamp","description"]
      ]
    ]

    let generationConfig: [String: Any] = [
        "temperature": 0.3,
        "maxOutputTokens": 8192,
        "responseMimeType": "application/json",
        "responseSchema": transcriptionSchema
    ]

    let requestBody: [String: Any] = [
        "contents": [["parts": [
            ["text": prompt],
            ["inline_data": ["mime_type": mimeType, "data": base64Video]]
        ]]],
        "generationConfig": generationConfig
    ]

    let endpoint = try buildRequestURL(path: "/v1beta/models/\(model.rawValue):generateContent")
    var request = URLRequest(url: endpoint)
    request.httpMethod = "POST"
    setAuthHeader(on: &request)
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.timeoutInterval = 180 // 3 minutes timeout for inline data

    let requestStart = Date()

    do {
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        logCurlCommand(context: "transcribe.inline.generateContent", url: endpoint.absoluteString, requestBody: requestBody)
        logRequestTiming(context: "transcribe.inline")

        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GeminiAPIHelper.APIError.invalidResponse
        }

        let ctx = LLMCallContext(
            batchId: batchId, callGroupId: groupId, attempt: attempt, provider: "gemini",
            model: model.rawValue, operation: "transcribe_inline", requestMethod: request.httpMethod,
            requestURL: request.url, requestHeaders: request.allHTTPHeaderFields,
            requestBody: request.httpBody, startedAt: requestStart
        )
        let httpInfo = LLMHTTPInfo(httpStatus: httpResponse.statusCode, responseHeaders: httpResponse.allHeaderFields as? [String: String] ?? [:], responseBody: data)

        if httpResponse.statusCode >= 400 {
            var errorMessage = "HTTP \(httpResponse.statusCode) error"
            if let jsonError = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let error = jsonError["error"] as? [String: Any],
               let message = error["message"] as? String {
                errorMessage = message
            }
            LLMLogger.logFailure(ctx: ctx, http: httpInfo, finishedAt: Date(), errorDomain: "HTTPError", errorCode: httpResponse.statusCode, errorMessage: errorMessage)
            throw GeminiAPIHelper.APIError.httpError(statusCode: httpResponse.statusCode, message: errorMessage)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let firstCandidate = candidates.first,
              let content = firstCandidate["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let firstPart = parts.first,
              let text = firstPart["text"] as? String else {
            LLMLogger.logFailure(ctx: ctx, http: httpInfo, finishedAt: Date(), errorDomain: "ParseError", errorCode: 9, errorMessage: "Invalid response format")
            throw GeminiAPIHelper.APIError.parsingFailed(description: "Invalid response format from inline transcription.")
        }

        LLMLogger.logSuccess(ctx: ctx, http: httpInfo, finishedAt: Date())
        return (text, model.rawValue)
            
    } catch {
        logGeminiFailure(context: "transcribe.inline.catch", attempt: attempt, response: nil, data: nil, error: error)
        throw error
    }
}
```

### 3.3. **CRITICAL**: Update `transcribeVideo` to use the new function

The main `transcribeVideo` function must be modified to include the conditional logic.

**ACTION**: Replace the `while attempt < maxRetries` loop in the `transcribeVideo` function with the following code block.

**File**: `Dayflow/Dayflow/Core/AI/GeminiDirectProvider.swift`

**Reference Implementation**:
```swift
while attempt < maxRetries {
    do {
        print("🔄 Video transcribe attempt \(attempt + 1)/\(maxRetries)")
        let activeModel = modelState.current
        
        let response: String
        let usedModel: String

        if isUsingCustomBase {
            // Call the new inline data transcription method
            (response, usedModel) = try await transcribeVideoWithInlineData(
                videoData: videoData,
                mimeType: mimeType,
                prompt: finalTranscriptionPrompt,
                batchId: batchId,
                groupId: callGroupId,
                model: activeModel,
                attempt: attempt + 1
            )
        } else {
            // Use the existing resumable upload flow
            let fileURI = try await uploadAndAwait(tempURL, mimeType: mimeType, key: apiKey).1
            (response, usedModel) = try await geminiTranscribeRequest(
                fileURI: fileURI,
                mimeType: mimeType,
                prompt: finalTranscriptionPrompt,
                batchId: batchId,
                groupId: callGroupId,
                model: activeModel,
                attempt: attempt + 1
            )
        }

        let videoTranscripts = try parseTranscripts(response)

        // ... (The rest of the validation logic remains unchanged)
        var hasValidationErrors = false
        let observations = videoTranscripts.compactMap { chunk -> Observation? in
            let startSeconds = parseVideoTimestamp(chunk.startTimestamp)
            let endSeconds = parseVideoTimestamp(chunk.endTimestamp)

            let tolerance: TimeInterval = 120.0
            if Double(startSeconds) < -tolerance || Double(endSeconds) > videoDuration + tolerance {
                print("❌ VALIDATION ERROR: Observation timestamps exceed video duration!")
                hasValidationErrors = true
                return nil
            }
            let startDate = batchStartTime.addingTimeInterval(TimeInterval(startSeconds))
            let endDate = batchStartTime.addingTimeInterval(TimeInterval(endSeconds))

            return Observation(
                id: nil,
                batchId: 0,
                startTs: Int(startDate.timeIntervalSince1970),
                endTs: Int(endDate.timeIntervalSince1970),
                observation: chunk.description,
                metadata: nil,
                llmModel: usedModel,
                createdAt: Date()
            )
        }

        if hasValidationErrors {
            throw GeminiAPIHelper.APIError.validationFailed(reason: "Gemini generated observations with timestamps exceeding video duration. Video is \(durationString) long but observations extended beyond this.")
        }

        if observations.isEmpty {
            throw GeminiAPIHelper.APIError.validationFailed(reason: "No valid observations generated after filtering out invalid timestamps")
        }

        print("✅ Video transcription succeeded on attempt \(attempt + 1)")
        finalResponse = response
        finalObservations = observations
        finalUsedModel = usedModel
        break

    } catch {
        // ... (The existing error handling and retry logic remains unchanged)
        lastError = error
        print("❌ Attempt \(attempt + 1) failed: \(error.localizedDescription)")

        var appliedFallback = false
        if let nsError = error as NSError?,
           nsError.domain == "GeminiError",
           Self.capacityErrorCodes.contains(nsError.code),
           let transition = modelState.advance() {

            appliedFallback = true
            let reason = fallbackReason(for: nsError.code)
            print("↘️ Downgrading to \(transition.to.rawValue) after \(nsError.code)")

            Task { @MainActor in
                AnalyticsService.shared.capture("llm_model_fallback", [
                    "provider": "gemini",
                    "operation": "transcribe",
                    "from_model": transition.from.rawValue,
                    "to_model": transition.to.rawValue,
                    "reason": reason,
                    "batch_id": batchId as Any
                ])
            }
        }

        if !appliedFallback {
            let strategy = classifyError(error)
            if strategy == .noRetry || attempt >= maxRetries - 1 {
                print("🚫 Not retrying: strategy=\(strategy), attempt=\(attempt + 1)/\(maxRetries)")
                throw error
            }
            let delay = delayForStrategy(strategy, attempt: attempt)
            if delay > 0 {
                print("⏳ Waiting \(String(format: "%.1f", delay))s before retry (strategy: \(strategy))")
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }
    }

    attempt += 1
}
```

## 4. Task Breakdown

1.  **Apply `buildRequestURL` modification**: Implement the changes from the original TDD, section 3.1.
2.  **Add `transcribeVideoWithInlineData` function**: Carefully insert the new function block in the correct location as specified in section 3.2 of this document.
3.  **Replace `transcribeVideo` loop**: Replace the `while` loop in the main `transcribeVideo` function with the new dispatcher logic from section 3.3.

This revised TDD provides a clear, unambiguous path to a successful implementation.