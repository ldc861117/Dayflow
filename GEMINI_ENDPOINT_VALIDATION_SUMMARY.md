# Gemini Endpoint Validation Implementation Summary

## Overview
This document summarizes the implementation of custom Gemini endpoint validation and wiring for the Dayflow macOS app.

## Changes Made

### 1. GeminiEndpointResolver (`Dayflow/Dayflow/Utilities/GeminiEndpointResolver.swift`)
**Purpose**: Central component for managing, validating, and normalizing custom Gemini base URLs.

**Key Features**:
- **Validation**: Enforces http/https schemes, rejects malformed URLs, whitespace, and missing hosts
- **Normalization**: Strips trailing slashes, paths, query parameters, and fragments
- **Persistence**: Atomically saves `useCustomGeminiBaseURL` and `customGeminiBaseURL` to UserDefaults
- **Error Handling**: Returns descriptive `GeminiEndpointValidationError` instances for UI feedback
- **Endpoint Resolution**: Provides `modelEndpoint(for:)` and `fileUploadEndpoint()` methods that respect custom base URLs

**Error Types**:
- `missingScheme`: "Base URL must include http:// or https://"
- `invalidScheme`: "Base URL must use http:// or https://"
- `invalidURL`: "Invalid URL format"
- `containsWhitespace`: "Base URL cannot contain whitespace"
- `missingHost`: "Base URL must have a valid host"

### 2. GeminiAPIHelper Updates (`Dayflow/Dayflow/Utilities/GeminiAPIHelper.swift`)
**Changes**:
- Replaced hardcoded `baseURL` constant with `getBaseURL()` method
- `getBaseURL()` now loads `GeminiEndpointResolver` and calls `modelEndpoint(for:)`
- Ensures all test connection calls use the resolver

### 3. GeminiDirectProvider Updates (`Dayflow/Dayflow/Core/AI/GeminiDirectProvider.swift`)
**Changes**:
- Replaced hardcoded `fileEndpoint` constant with `fileUploadEndpoint()` method
- Updated `endpointForModel(_:)` to use `GeminiEndpointResolver`
- Updated `uploadSimple(data:mimeType:)` to use resolver
- Updated `uploadResumable(data:mimeType:)` to use resolver
- All Gemini API calls (model generation, file uploads, file status checks) now read endpoints through the resolver

### 4. SettingsView UI (`Dayflow/Dayflow/Views/UI/SettingsView.swift`)
**New UI Section**: "Custom Gemini endpoint" card in the Gemini provider settings

**Features**:
- **Toggle**: "Use custom Gemini base URL" with descriptive subtitle
- **Text Field**: Accepts user-supplied base URLs with real-time validation
- **Validation Feedback**:
  - Red border and error message for invalid URLs
  - Green checkmark with "Normalized: [url]" for valid URLs
- **Test Button**: "Test base URL" 
  - Disabled when validation fails or input is empty
  - Shows loading state while testing
  - Displays success/failure status with descriptive messages
  - On success, shows "Success! Using [normalized-url]"
- **Atomic Persistence**: When toggle is switched off, both settings are reset to defaults immediately

**State Management**:
- `useCustomGeminiBaseURL`: Toggle state
- `customGeminiBaseURL`: Text field value
- `customGeminiBaseURLValidationError`: Error message from validation
- `normalizedCustomGeminiBaseURL`: Normalized URL shown on success
- `geminiBaseTestStatus`: Success/failure message from connection test
- `isTestingGeminiBaseURL`: Loading state

**Load/Save Logic**:
- `loadGeminiEndpointSettings()`: Loads from UserDefaults on appear
- `validateAndSaveGeminiBaseURL(_:skipSave:)`: Validates input and saves if valid
- `persistGeminiEndpointSettings()`: Writes to UserDefaults via resolver
- `testGeminiBaseURL()`: Runs connection test using GeminiAPIHelper
- `onChange(of: useCustomGeminiBaseURL)`: Resets both fields when toggled off
- `onChange(of: customGeminiBaseURL)`: Validates and saves on every keystroke

### 5. Unit Tests (`Dayflow/DayflowTests/GeminiEndpointResolverTests.swift`)
**Coverage**:
- ✅ Validation: HTTPs, HTTP, trailing slashes, paths, query params, fragments, whitespace trimming
- ✅ Error Cases: Missing scheme, invalid scheme, whitespace, empty string, invalid URL
- ✅ Persistence: Load/save cycle, reset to defaults
- ✅ Endpoint Resolution: Default when not enabled, custom when enabled, fallback on invalid
- ✅ Model & Upload Endpoints: Both default and custom base URLs
- ✅ Integration: Simulated custom host changes both model and upload URLs

### 6. Integration Tests (`Dayflow/DayflowTests/GeminiEndpointIntegrationTests.swift`)
**Scenarios**:
- ✅ Custom base URL is respected by resolver after save/load
- ✅ API helper uses resolver endpoints
- ✅ Toggle off resets custom base to nil
- ✅ Empty custom base is removed on save
- ✅ Resolver normalizes URLs on save

## Acceptance Criteria Validation

### ✅ 1. Invalid Base URL Handling
**Requirement**: Entering an invalid base (missing scheme, whitespace, malformed URL) surfaces a clear error and blocks persistence/test invocation until corrected.

**Implementation**:
- `GeminiEndpointResolver.normalizeAndValidate(_:)` throws descriptive errors
- UI displays error message in red with icon
- Text field gets red border
- Test button is disabled while error exists
- No save occurs until validation passes

### ✅ 2. Valid Custom Host Persistence
**Requirement**: Valid custom hosts are normalized, persisted, and reloaded in a fresh session.

**Implementation**:
- `GeminiEndpointResolver.save()` normalizes and stores to UserDefaults
- `GeminiEndpointResolver.load()` retrieves settings
- Normalized URL shown in UI with green checkmark
- Settings persist across app restarts via UserDefaults
- Unit tests validate save/load cycle

### ✅ 3. Custom Base Affects All Endpoints
**Requirement**: When a custom base is active, both content generation and file upload endpoints point at that host.

**Implementation**:
- `GeminiDirectProvider.endpointForModel(_:)` uses resolver
- `GeminiDirectProvider.fileUploadEndpoint()` uses resolver
- `GeminiAPIHelper.getBaseURL()` uses resolver
- All API calls (model, upload, status) read from resolver
- Integration tests verify both endpoints use custom host

### ✅ 4. Test Coverage
**Requirement**: Test coverage exists for GeminiEndpointResolver normalization and for the resolver being consumed by the API helper.

**Implementation**:
- 15+ unit tests in `GeminiEndpointResolverTests`
- 5 integration tests in `GeminiEndpointIntegrationTests`
- Tests cover validation, normalization, persistence, endpoint resolution, and integration scenarios
- Smoke test verifies custom host changes composed URLs

### ✅ 5. Atomic Toggle Behavior
**Requirement**: Persist `useCustomGeminiBaseURL` and `customGeminiBaseURL` atomically, resetting both to defaults when the toggle is switched off.

**Implementation**:
- `onChange(of: useCustomGeminiBaseURL)` handler immediately resets all fields when toggled off
- `persistGeminiEndpointSettings()` called immediately after reset
- `GeminiEndpointResolver.save()` writes both settings atomically
- Test validates toggle off removes custom base

### ✅ 6. Test Button Behavior
**Requirement**: Update the "Test base URL" button to disable while validation fails and to show the normalized host that will be used when the test succeeds.

**Implementation**:
- Button disabled when:
  - Validation error exists
  - Input is empty
  - Test is running
- Success message shows "Success! Using [normalized-url]"
- Failure message shows error description
- Visual state changes (green highlight on success)

## Example Usage Flow

1. User navigates to Settings → Providers → "Custom Gemini endpoint"
2. User toggles "Use custom Gemini base URL" ON
3. User enters "https://proxy.example.com/path"
4. UI shows "Normalized: https://proxy.example.com" (green)
5. User clicks "Test base URL"
6. Button shows "Testing..."
7. On success: "Success! Using https://proxy.example.com"
8. Settings are saved to UserDefaults
9. All future Gemini API calls use https://proxy.example.com/v1beta/models/...
10. User toggles OFF → both fields reset, back to default Google endpoint

## Error Handling Examples

### Missing Scheme
**Input**: `proxy.example.com`
**Error**: "Base URL must include http:// or https://"
**UI**: Red border, error message, test button disabled

### Invalid Scheme
**Input**: `ftp://proxy.example.com`
**Error**: "Base URL must use http:// or https://"
**UI**: Red border, error message, test button disabled

### Whitespace
**Input**: `https://proxy.example .com`
**Error**: "Base URL cannot contain whitespace"
**UI**: Red border, error message, test button disabled

### Valid with Normalization
**Input**: `https://proxy.example.com/v1/api?key=123#fragment`
**Normalized**: `https://proxy.example.com`
**UI**: Green checkmark, "Normalized: https://proxy.example.com", test button enabled

## Technical Details

### UserDefaults Keys
- `useCustomGeminiBaseURL`: Boolean
- `customGeminiBaseURL`: String (optional)

### Resolver Logic
```swift
func resolveBaseURL() -> String {
    guard useCustomBase, let customBase else {
        return defaultBaseURL  // "https://generativelanguage.googleapis.com"
    }
    
    if let normalized = try? Self.normalizeAndValidate(customBase) {
        return normalized
    }
    
    return defaultBaseURL  // Fallback if custom is invalid
}
```

### Normalization Steps
1. Trim whitespace
2. Check for internal whitespace → error
3. Parse as URLComponents → validate scheme
4. Ensure http or https
5. Strip user, password, path, query, fragment
6. Remove trailing slashes
7. Return normalized string

## Files Modified

1. **Created**: `Dayflow/Dayflow/Utilities/GeminiEndpointResolver.swift` (131 lines)
2. **Modified**: `Dayflow/Dayflow/Utilities/GeminiAPIHelper.swift` (changed baseURL to dynamic)
3. **Modified**: `Dayflow/Dayflow/Core/AI/GeminiDirectProvider.swift` (changed fileEndpoint and endpointForModel)
4. **Modified**: `Dayflow/Dayflow/Views/UI/SettingsView.swift` (added UI section and state management)
5. **Created**: `Dayflow/DayflowTests/GeminiEndpointResolverTests.swift` (195 lines)
6. **Created**: `Dayflow/DayflowTests/GeminiEndpointIntegrationTests.swift` (83 lines)

## Summary

All acceptance criteria have been met:
- ✅ Invalid URLs are blocked with clear error messages
- ✅ Valid URLs are normalized and persisted
- ✅ Custom base affects all endpoints (model and upload)
- ✅ Comprehensive test coverage exists
- ✅ Toggle behavior is atomic
- ✅ Test button behaves as specified

The implementation is production-ready, well-tested, and follows Swift/SwiftUI best practices.
