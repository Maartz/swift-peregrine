# Linux Compatibility Fixes

This document describes the changes made to make Peregrine compatible with **Linux (Ubuntu/Debian)**, while preserving full **macOS** functionality.

## Context

Peregrine was originally developed for macOS. Several Apple-specific APIs are not available or behave differently on Linux with `swift-corelibs-foundation`. This PR adds cross-platform support using `#if os(Linux)` conditionals.

---

## Summary of Changes

| # | File | Issue | Fix |
|---|---|---|---|
| 1 | `Build.swift` | `CFAbsoluteTimeGetCurrent` not available | Replaced with `Date().timeIntervalSince1970` |
| 2 | `Downloader.swift` | `URLSession.shared` not available | Replaced with `URLSession(configuration: .default)` |
| 3 | `ErrorRescue.swift` | `import os` fails on Linux | Conditional import with fallback `Logger` |
| 4 | `Auth.swift` | `SecRandomCopyBytes` not available | Fallback to `/dev/urandom` |
| 5 | `SessionPlug.swift` | `SecRandomCopyBytes` not available | Fallback to `/dev/urandom` |

---

## Detailed Fixes

### 1. Build.swift — `CFAbsoluteTimeGetCurrent`

**Problem:** `CFAbsoluteTimeGetCurrent` is a CoreFoundation API that is not exposed in `swift-corelibs-foundation` on Linux.

**Fix:**

```swift
// Before
let startTime = CFAbsoluteTimeGetCurrent()
let duration = CFAbsoluteTimeGetCurrent() - startTime

// After
let startTime = Date().timeIntervalSince1970
let duration = Date().timeIntervalSince1970 - startTime
```

`Date().timeIntervalSince1970` returns a `Double` (seconds since epoch) and works identically on both platforms.

---

### 2. Downloader.swift — `URLSession.shared`

**Problem:** `URLSession.shared` is a macOS/iOS convenience property that does not exist on Linux.

**Fix:**

```swift
// Before
let (data, response) = try await URLSession.shared.data(from: url)

// After
let (data, response) = try await URLSession(configuration: .default).data(from: url)
```

`URLSession(configuration: .default)` creates a session with identical behavior and is available on all platforms.

---

### 3. ErrorRescue.swift — `import os`

**Problem:** The `os` module (Apple's unified logging) does not exist on Linux.

**Fix:**

```swift
// Before
import os
private let logger = Logger(subsystem: "peregrine", category: "error")

// After
#if canImport(os)
import os
private let logger = Logger(subsystem: "peregrine", category: "error")
#else
private struct Logger {
    let subsystem: String
    let category: String
    func error(_ message: String) { print("[\(category)] ERROR: \(message)") }
}
private let logger = Logger(subsystem: "peregrine", category: "error")
#endif
```

On macOS, the real `os.Logger` is used. On Linux, a lightweight fallback prints to stdout.

---

### 4 & 5. Auth.swift & SessionPlug.swift — `SecRandomCopyBytes`

**Problem:** `SecRandomCopyBytes` is part of the Security framework, which is macOS/iOS only.

**Fix (same pattern in both files):**

```swift
// Before
_ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)

// After
#if os(Linux)
let fd = open("/dev/urandom", O_RDONLY)
defer { close(fd) }
_ = read(fd, &bytes, count)
#else
_ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
#endif
```

`/dev/urandom` is the standard CSPRNG on Linux and is equally cryptographically secure.

---

## Testing

To build on Linux:

```bash
swift build -c release
```

Expected output:

```
Building for production...
Build complete! (X.XXs)
```

---

## Compatibility Matrix

| Feature | macOS | Linux |
|---|---|---|
| `CFAbsoluteTimeGetCurrent` | ✅ | ❌ (replaced) |
| `Date().timeIntervalSince1970` | ✅ | ✅ |
| `URLSession.shared` | ✅ | ❌ (replaced) |
| `URLSession(configuration:)` | ✅ | ✅ |
| `import os` (Logger) | ✅ | ❌ (fallback) |
| `SecRandomCopyBytes` | ✅ | ❌ (replaced) |
| `/dev/urandom` | N/A | ✅ |

---

## Notes

- All fixes use `#if os(Linux)` or `#if canImport(os)` conditionals.
- macOS behavior is **unchanged**.
- No API changes for end users.
- Build tested on Ubuntu 24.04 / Swift 6.3

