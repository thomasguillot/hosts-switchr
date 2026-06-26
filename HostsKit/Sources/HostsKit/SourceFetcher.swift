import Foundation

/// Allows a redirect only when its target stays https; a non-https redirect is cancelled and recorded.
final class HTTPSRedirectGuard: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var _blocked = false
    var blockedInsecureRedirect: Bool { lock.withLock { _blocked } }

    func urlSession(
        _ session: URLSession, task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest
    ) async -> URLRequest? {
        if request.url?.scheme?.lowercased() == "https" { return request }
        lock.withLock { _blocked = true }
        return nil
    }
}

/// Writes body chunks directly to a FileHandle so no in-memory buffer accumulates. Status/Content-Length validation happens before any body is drained.
final class ChunkedBodyDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let redirectGuard: HTTPSRedirectGuard
    private let fileHandle: FileHandle
    private let onResponse: @Sendable (URLResponse) -> Void
    private let maxBytes: Int
    // Accessed only on the URLSession delegate queue (serial), so no lock needed.
    private var received: Int = 0
    private var errorFlag: Error?

    private let lock = NSLock()
    private var _continuation: CheckedContinuation<Void, Error>?
    private var _completionResult: Result<Void, Error>?

    init(
        redirectGuard: HTTPSRedirectGuard,
        fileHandle: FileHandle,
        maxBytes: Int,
        onResponse: @escaping @Sendable (URLResponse) -> Void
    ) {
        self.redirectGuard = redirectGuard
        self.fileHandle = fileHandle
        self.maxBytes = maxBytes
        self.onResponse = onResponse
    }

    func waitForCompletion() async throws {
        try await withCheckedThrowingContinuation { continuation in
            // If the task already completed before we install the continuation, resume immediately.
            lock.withLock {
                if let result = _completionResult {
                    switch result {
                    case .success: continuation.resume()
                    case .failure(let e): continuation.resume(throwing: e)
                    }
                } else {
                    _continuation = continuation
                }
            }
        }
    }

    func urlSession(
        _ session: URLSession, task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest
    ) async -> URLRequest? {
        await redirectGuard.urlSession(
            session, task: task, willPerformHTTPRedirection: response, newRequest: request)
    }

    func urlSession(
        _ session: URLSession, dataTask: URLSessionDataTask,
        didReceive response: URLResponse
    ) async -> URLSession.ResponseDisposition {
        guard let http = response as? HTTPURLResponse else {
            errorFlag = SourceError.notHostsFormat
            return .cancel
        }
        if http.statusCode != 304 {
            guard (200...299).contains(http.statusCode) else {
                errorFlag = NSError(
                    domain: "SourceFetcher", code: http.statusCode,
                    userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode)"])
                return .cancel
            }
            // expectedContentLength is -1 when unknown, so an undeclared length won't false-trigger.
            if http.expectedContentLength > Int64(maxBytes) {
                errorFlag = SourceError.tooLarge
                return .cancel
            }
        }
        onResponse(response)
        return .allow
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        received += data.count
        if received > maxBytes {
            dataTask.cancel()
            errorFlag = SourceError.tooLarge
            return
        }
        do {
            try fileHandle.write(contentsOf: data)
        } catch {
            // didCompleteWithError owns the single fileHandle.close(); don't close it here.
            errorFlag = error
            dataTask.cancel()
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        var closeError: Error?
        do { try fileHandle.close() } catch { closeError = error }
        let taskResult: Result<Void, Error>
        if let e = errorFlag ?? error {
            taskResult = .failure(e)
        } else if let e = closeError {
            taskResult = .failure(e)
        } else {
            taskResult = .success(())
        }
        var cont: CheckedContinuation<Void, Error>?
        lock.withLock {
            cont = _continuation
            _continuation = nil
            if cont == nil { _completionResult = taskResult }
        }
        if let cont {
            switch taskResult {
            case .success: cont.resume()
            case .failure(let e): cont.resume(throwing: e)
            }
        }
    }
}

final class ResponseBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: URLResponse?
    var value: URLResponse? { lock.withLock { _value } }
    func set(_ response: URLResponse) { lock.withLock { _value = response } }
}

public enum FetchResult: Sendable, Equatable {
    case notModified
    case updated(tempURL: URL, etag: String?, lastModified: String?, domainCount: Int)
}

public protocol SourceFetching: Sendable {
    func fetch(_ source: RemoteSource) async throws -> FetchResult
}

public struct SourceFetcher: SourceFetching {
    private static let maxBytes = 256 * 1024 * 1024
    private let session: URLSession
    private nonisolated(unsafe) let fileManager: FileManager

    public init(session: URLSession = .shared, fileManager: FileManager = .default) {
        self.session = session
        self.fileManager = fileManager
    }

    public func fetch(_ source: RemoteSource) async throws -> FetchResult {
        // Fail closed: never issue a request for a non-https source.
        guard source.url.scheme?.lowercased() == "https" else { throw SourceError.insecureURL }

        var request = URLRequest(url: source.url)
        request.httpMethod = "GET"
        request.timeoutInterval = 60
        if let etag = source.etag { request.setValue(etag, forHTTPHeaderField: "If-None-Match") }
        if let lm = source.lastModified { request.setValue(lm, forHTTPHeaderField: "If-Modified-Since") }

        let tempURL = fileManager.temporaryDirectory
            .appendingPathComponent("hostsswitchr-fetch-\(UUID().uuidString).hosts")
        try? fileManager.removeItem(at: tempURL)
        guard fileManager.createFile(atPath: tempURL.path, contents: nil) else {
            throw SourceError.notHostsFormat
        }
        let fileHandle = try FileHandle(forWritingTo: tempURL)

        let redirectGuard = HTTPSRedirectGuard()
        let responseBox = ResponseBox()
        let delegate = ChunkedBodyDelegate(
            redirectGuard: redirectGuard, fileHandle: fileHandle, maxBytes: Self.maxBytes,
            onResponse: { responseBox.set($0) })
        let task = session.dataTask(with: request)
        task.delegate = delegate
        task.resume()

        do {
            try await withTaskCancellationHandler {
                try await delegate.waitForCompletion()
            } onCancel: {
                task.cancel()
            }
        } catch {
            task.cancel()
            try? fileManager.removeItem(at: tempURL)
            if redirectGuard.blockedInsecureRedirect { throw SourceError.insecureRedirect }
            throw error
        }
        // Even if the delegate finished before cancellation propagated, refuse to validate or cache.
        if Task.isCancelled { try? fileManager.removeItem(at: tempURL); throw CancellationError() }
        if redirectGuard.blockedInsecureRedirect {
            try? fileManager.removeItem(at: tempURL); throw SourceError.insecureRedirect
        }
        return try validateAndBuildResult(tempURL: tempURL, responseBox: responseBox)
    }

    private func validateAndBuildResult(tempURL: URL, responseBox: ResponseBox) throws -> FetchResult {
        // Remove temp on every non-`.updated` exit; only the successful return hands it to the caller.
        var keepTemp = false
        defer { if !keepTemp { try? fileManager.removeItem(at: tempURL) } }

        guard let http = responseBox.value as? HTTPURLResponse else {
            throw SourceError.notHostsFormat
        }
        if http.statusCode == 304 { return .notModified }

        let (looksLike, domainCount) = try streamingScan(tempURL: tempURL)
        guard looksLike else { throw SourceError.notHostsFormat }

        let etag = http.value(forHTTPHeaderField: "ETag")
        let lastModified = http.value(forHTTPHeaderField: "Last-Modified")
        keepTemp = true
        return .updated(tempURL: tempURL, etag: etag, lastModified: lastModified, domainCount: domainCount)
    }

    private func streamingScan(tempURL: URL) throws -> (Bool, Int) {
        let handle = try FileHandle(forReadingFrom: tempURL)
        defer { try? handle.close() }

        let chunkSize = 65_536
        var carry = Data()
        var mapping = 0
        var content = 0

        func processLine(_ line: String) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { return }
            content += 1
            if case let .mapping(ip, _) = HostsFile.parseLine(line).kind,
               HostsValidator.isValidIP(ip) { mapping += 1 }
        }

        // 4 KB carry cap prevents O(n²) copying when a malicious source sends no newlines within the 256 MB body limit.
        let maxCarry = 4_096
        var skippingOverlongLine = false

        while true {
            let chunk: Data
            if #available(macOS 10.15.4, *) {
                chunk = (try handle.read(upToCount: chunkSize)) ?? Data()
            } else {
                chunk = handle.readData(ofLength: chunkSize)
            }
            if chunk.isEmpty { break }

            var window = carry + chunk
            carry = Data()

            while let term = window.firstIndex(where: { $0 == UInt8(ascii: "\n") || $0 == UInt8(ascii: "\r") }) {
                let lineData = window[window.startIndex..<term]
                if skippingOverlongLine {
                    skippingOverlongLine = false
                } else {
                    processLine(String(decoding: lineData, as: UTF8.self))
                }
                window = window[window.index(after: term)...]
            }
            carry = Data(window)
            if carry.count > maxCarry {
                // Classify an overlong line exactly once, but only once its first non-whitespace byte is seen, so all-whitespace carry doesn't prematurely skip the still-ahead classifying byte.
                if !skippingOverlongLine,
                   let b = carry.first(where: { $0 != UInt8(ascii: " ") && $0 != UInt8(ascii: "\t") && $0 != UInt8(ascii: "\r") }) {
                    if b != UInt8(ascii: "#") { content += 1 }
                    skippingOverlongLine = true
                }
                carry = Data()
            }
        }

        if !carry.isEmpty, !skippingOverlongLine {
            processLine(String(decoding: carry, as: UTF8.self))
        }

        let looksLike = mapping >= 1 && mapping * 2 > content
        return (looksLike, mapping)
    }
}
