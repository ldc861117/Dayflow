# Test Plan: Gemini Video Upload Error Handling

**Objective**: Verify that a failure from the Dayflow backend during a video upload request correctly propagates a `GeminiAPIHelper.APIError.invalidResponseData` error.

## Test Case 1: Backend Failure During Video Upload

*   **Setup**:
    1.  Introduce a mock into the `uploadAndAwait` function in `GeminiDirectProvider.swift` to simulate a non-200 HTTP response from the backend during the file upload process.
    2.  The mock should return a `HTTPURLResponse` with a status code of 500 and a sample JSON error body.

*   **Action**:
    1.  Initiate a video upload through the Dayflow application.

*   **Expected Result**:
    1.  The `transcribeVideo` function should catch an error.
    2.  The caught error should be of type `GeminiAPIHelper.APIError.invalidResponseData`.
    3.  The error's associated data should contain the HTTP status code (500) and the sample JSON error body.

*   **Actual Result (Based on Code Review)**:
    *   The `uploadAndAwait` function will throw a generic `NSError`, not the expected `GeminiAPIHelper.APIError.invalidResponseData`. This does not meet the implementation requirements.

## Test Case 2: Redundant `await` in Analytics Capture

*   **Setup**:
    1.  No special setup is required. The issue is present in the existing code.

*   **Action**:
    1.  Examine the `transcribeVideo` and `generateActivityCards` functions in `GeminiDirectProvider.swift`.

*   **Expected Result**:
    1.  The call to `AnalyticsService.shared.capture` should not be preceded by the `await` keyword, as the function is not asynchronous.

*   **Actual Result (Based on Code Review)**:
    *   The `await` keyword is present, resulting in a compiler warning: "No 'async' operations occur within 'await' expression". This is a code quality issue.