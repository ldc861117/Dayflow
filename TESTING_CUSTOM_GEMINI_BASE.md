# Testing Custom Gemini Base URL Feature

## Overview
This document provides instructions for testing the custom Gemini base URL feature with real-world scenarios.

## Test Scenarios

### Scenario 1: Default Google Endpoint (No Custom Base)
**Expected Behavior**: Uses Google's official Gemini API with query parameter authentication

1. Open Dayflow Settings → Providers
2. Ensure "Use custom Gemini base URL" is toggled OFF
3. Click "Edit configuration" for Gemini
4. Enter your Google Gemini API key
5. Click "Test Connection"
6. **Expected**: Success message, connection works

**Technical Details**:
- Endpoint: `https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-lite:generateContent?key=YOUR_API_KEY`
- Auth method: Query parameter (`?key=`)

### Scenario 2: Custom Base URL with Header Authentication
**Expected Behavior**: Routes all requests through custom proxy, uses header authentication

1. Open Dayflow Settings → Providers
2. Enable "Use custom Gemini base URL"
3. Enter custom base: `https://api.metamirror.club` (or your proxy)
4. **Expected**: UI shows "Normalized: https://api.metamirror.club" with green checkmark
5. Click "Test base URL"
6. **Expected**: Success message showing normalized URL

**Technical Details**:
- Endpoint: `https://api.metamirror.club/v1beta/models/gemini-2.5-flash-lite:generateContent`
- Auth method: HTTP header (`x-goog-api-key: YOUR_API_KEY`)
- No query parameters added

### Scenario 3: Video Analysis with Custom Base
**Expected Behavior**: Batch processing uses custom endpoint for all operations

1. Set up custom base URL as in Scenario 2
2. Record some screen activity (or use existing recordings)
3. Let Dayflow process a video batch
4. **Expected**: 
   - Upload succeeds to custom endpoint
   - File status checks use custom endpoint
   - Video transcription succeeds
   - Activity cards generation succeeds

**Operations That Must Work**:
- File upload (`POST /upload/v1beta/files`)
- File status check (`GET /upload/v1beta/files/{file_id}`)
- Video transcription (`POST /v1beta/models/{model}:generateContent`)
- Activity card generation (`POST /v1beta/models/{model}:generateContent`)

### Scenario 4: URL Normalization
**Expected Behavior**: Various URL formats are normalized correctly

Test these inputs:
| Input | Normalized | Valid? |
|-------|-----------|--------|
| `https://api.example.com/` | `https://api.example.com` | ✓ |
| `https://api.example.com///` | `https://api.example.com` | ✓ |
| `https://api.example.com/v1/test` | `https://api.example.com` | ✓ |
| `https://api.example.com?key=abc` | `https://api.example.com` | ✓ |
| `http://localhost:8080` | `http://localhost:8080` | ✓ |
| `api.example.com` | Error: Missing scheme | ✗ |
| `ftp://api.example.com` | Error: Invalid scheme | ✗ |
| `https://api.example .com` | Error: Contains whitespace | ✗ |

### Scenario 5: Toggle Off Resets Everything
**Expected Behavior**: Disabling custom base restores default behavior

1. Set up custom base URL
2. Toggle "Use custom Gemini base URL" OFF
3. **Expected**:
   - Text field clears
   - Validation messages disappear
   - Settings saved (both fields reset)
4. Test connection again
5. **Expected**: Uses default Google endpoint

### Scenario 6: Session Persistence
**Expected Behavior**: Custom settings survive app restart

1. Set custom base URL
2. Toggle ON
3. Test connection (should succeed)
4. Quit Dayflow completely
5. Reopen Dayflow
6. Navigate to Settings → Providers → Custom Gemini endpoint
7. **Expected**: Toggle is ON, custom URL is populated
8. Test connection
9. **Expected**: Still works with custom endpoint

## API Key Authentication Methods

### Query Parameter (Default Google Endpoint)
```swift
// URL format:
https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-lite:generateContent?key=YOUR_API_KEY

// HTTP request:
POST /v1beta/models/gemini-2.5-flash-lite:generateContent?key=AIzaSy...
Host: generativelanguage.googleapis.com
Content-Type: application/json
```

### Header-Based (Custom Proxies)
```swift
// URL format (no query param):
https://api.metamirror.club/v1beta/models/gemini-2.5-flash-lite:generateContent

// HTTP request:
POST /v1beta/models/gemini-2.5-flash-lite:generateContent
Host: api.metamirror.club
Content-Type: application/json
x-goog-api-key: clikey-your-api-key-here
```

## Testing with Python Script

The following Python script can be used to verify your custom endpoint works before configuring Dayflow:

```python
import requests
import base64
import json

def test_custom_endpoint(base_url, api_key, video_path):
    """Test custom Gemini endpoint with video analysis"""
    
    # Read and encode video
    with open(video_path, "rb") as f:
        video_bytes = f.read()
        encoded_video = base64.b64encode(video_bytes).decode('utf-8')
    
    # Build request
    url = f"{base_url}/v1beta/models/gemini-2.5-pro:generateContent"
    headers = {
        "x-goog-api-key": api_key,
        "Content-Type": "application/json"
    }
    
    payload = {
        "contents": [{
            "parts": [
                {"text": "What is in this video?"},
                {
                    "inline_data": {
                        "mime_type": "video/mp4",
                        "data": encoded_video
                    }
                }
            ]
        }]
    }
    
    response = requests.post(url, headers=headers, json=payload)
    response.raise_for_status()
    
    return response.json()

# Test it
if __name__ == "__main__":
    result = test_custom_endpoint(
        base_url="https://api.metamirror.club",
        api_key="clikey-your-key",
        video_path="/path/to/test.mp4"
    )
    print(json.dumps(result, indent=2))
```

## Troubleshooting

### Problem: "Test base URL" button stays disabled
**Cause**: URL validation failed
**Fix**: Check for error message below text field. Common issues:
- Missing `http://` or `https://`
- Whitespace in URL
- Invalid characters

### Problem: Connection test succeeds but video analysis fails
**Cause**: File upload endpoint or file status check might be failing
**Check**:
1. Enable debug logging (check Console.app for Dayflow logs)
2. Look for "🔴" error messages in logs
3. Verify custom proxy supports:
   - `POST /upload/v1beta/files`
   - `GET /upload/v1beta/files/{file_id}`
   - File upload with `X-Goog-Upload-*` headers

### Problem: Authentication errors with custom proxy
**Cause**: API key not being sent correctly
**Verify**:
- Custom endpoint receives `x-goog-api-key` header
- Default endpoint uses `?key=` query parameter
- Check with `tcpdump` or proxy logs to see actual requests

### Problem: "Invalid file URI" errors
**Cause**: File status check failing
**Check**:
- The file URI returned by upload should be accessible
- File status endpoint must support header-based auth
- URI format must match what your proxy expects

## Development/Debug Mode

To enable detailed logging for troubleshooting:

1. Launch Dayflow from Terminal:
```bash
/Applications/Dayflow.app/Contents/MacOS/Dayflow
```

2. Watch for debug output:
```
📤 Starting resumable video upload:
   Size: 2 MB
   MIME Type: video/mp4
📡 Upload session initialized:
   Status: 200
   Init Duration: 0.45s
   Upload URL: https://...
📥 Upload completed:
   Status: 200
   Upload Duration: 1.23s
✅ Video uploaded successfully
   File URI: files/abc123...
```

3. Look for authentication-related logs:
- Query param: URL will show `?key=`
- Header: No `?key=` in URL, but request includes `x-goog-api-key` header

## Expected Console Output (Success Case)

### With Default Endpoint:
```
🔄 Video transcribe attempt 1/6
✅ Video transcription succeeded on attempt 1
```

### With Custom Endpoint:
```
🔄 Video transcribe attempt 1/6
📤 Starting resumable video upload:
   Size: 2 MB
✅ Video uploaded successfully
✅ Video transcription succeeded on attempt 1
```

Both should produce identical results, just routing through different hosts.
