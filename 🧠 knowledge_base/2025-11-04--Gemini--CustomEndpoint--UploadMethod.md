# Gemini Custom Endpoint Upload Strategy

**Domain**: Gemini API Integration
**Topic**: Custom Endpoint Compatibility
**Keywords**: `gemini`, `custom_endpoint`, `upload`, `inline_data`, `resumable_upload`, `404_error`

## 1. Problem

When using a custom base URL for the Gemini API, the standard resumable upload protocol (invoked via `/upload/v1beta/files`) may not be supported, resulting in a "404 Not Found" error. This was observed in the `GeminiDirectProvider` when attempting to upload videos for transcription.

## 2. Architectural Solution

To ensure compatibility with both standard and custom Gemini endpoints, a conditional upload logic has been implemented.

- **Standard Endpoint**: Continue using the efficient, multi-part resumable upload protocol (`uploadAndAwait`). This is the preferred method for large files when connecting to the official Google Cloud infrastructure.

- **Custom Endpoint**: Switch to an `inline_data` upload method. In this flow, the video data is Base64-encoded and sent directly within the JSON payload of the `generateContent` request. This method is more widely supported by proxy or custom implementations of the Gemini API, as confirmed by the successful execution of a Python script using this approach.

## 3. Implementation Details

The `GeminiDirectProvider.swift` class was modified to include this conditional logic.

1.  A new function, `transcribeVideoWithInlineData`, was created to handle the Base64-encoding and POST request for the inline method.
2.  The primary `transcribeVideo` function now checks if `isUsingCustomBase` is true.
3.  If true, it dispatches the call to `transcribeVideoWithInlineData`.
4.  If false, it proceeds with the existing `uploadAndAwait` resumable upload flow.

This architecture provides flexibility and robustness, ensuring that the application can seamlessly connect to different Gemini-compatible backends without upload failures.