import Foundation
import AppKit

/// Allows a redirect only when its target stays https; a non-https redirect is cancelled and recorded.
private final class DownloadRedirectGuard: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
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

/// Writes body chunks directly to a FileHandle so no in-memory buffer accumulates. Status/size
/// validation happens before any body is drained.
private final class DownloadBodyDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    // Denylist, not allowlist: an interstitial/error page served instead of the DMG is the failure
    // mode we care about; unknown or absent MIME types are allowed through.
    static let rejectedMimeTypes: Set<String> = ["text/html", "text/plain"]

    private let redirectGuard: DownloadRedirectGuard
    private let fileHandle: FileHandle
    private let maxBytes: Int
    private let expectedSize: Int
    // Lock-free by URLSession ordering: the response disposition returns before any body chunk,
    // and completion fires after the last chunk — so these are never touched concurrently.
    private var received = 0
    private var errorFlag: Error?

    private let lock = NSLock()
    private var _continuation: CheckedContinuation<Void, Error>?
    private var _completionResult: Result<Void, Error>?

    init(
        redirectGuard: DownloadRedirectGuard,
        fileHandle: FileHandle,
        maxBytes: Int,
        expectedSize: Int
    ) {
        self.redirectGuard = redirectGuard
        self.fileHandle = fileHandle
        self.maxBytes = maxBytes
        self.expectedSize = expectedSize
    }

    func waitForCompletion() async throws {
        try await withCheckedThrowingContinuation { continuation in
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
            errorFlag = UpdateDownloader.DownloadError.badStatus(-1)
            return .cancel
        }
        guard http.statusCode == 200 else {
            errorFlag = UpdateDownloader.DownloadError.badStatus(http.statusCode)
            return .cancel
        }
        // expectedContentLength is -1 when unknown, so an undeclared length won't false-trigger.
        if http.expectedContentLength > Int64(maxBytes) {
            errorFlag = UpdateDownloader.DownloadError.tooLarge
            return .cancel
        }
        if expectedSize > 0, http.expectedContentLength >= 0,
            http.expectedContentLength != Int64(expectedSize) {
            errorFlag = UpdateDownloader.DownloadError.sizeMismatch
            return .cancel
        }
        if let mimeType = response.mimeType, Self.rejectedMimeTypes.contains(mimeType.lowercased()) {
            errorFlag = UpdateDownloader.DownloadError.unexpectedContentType
            return .cancel
        }
        return .allow
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        received += data.count
        if received > maxBytes {
            dataTask.cancel()
            errorFlag = UpdateDownloader.DownloadError.tooLarge
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
        } else if expectedSize > 0, received != expectedSize {
            taskResult = .failure(UpdateDownloader.DownloadError.sizeMismatch)
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

struct UpdateDownloader: Sendable {
    enum DownloadError: Error {
        case insecureURL, insecureRedirect, badStatus(Int), tooLarge, writeFailed, openFailed
        case sizeMismatch, unexpectedContentType
    }

    private static let maxBytes = 500 * 1024 * 1024

    private let session: URLSession
    private nonisolated(unsafe) let fileManager: FileManager

    init(session: URLSession = .shared, fileManager: FileManager = .default) {
        self.session = session
        self.fileManager = fileManager
    }

    func downloadAndOpen(dmgURL: URL, suggestedName: String, expectedSize: Int) async throws -> URL {
        // Fail closed: never download over a non-https URL.
        guard dmgURL.scheme?.lowercased() == "https" else { throw DownloadError.insecureURL }
        // Reject the advertised size before issuing any network request.
        if expectedSize > Self.maxBytes { throw DownloadError.tooLarge }

        var request = URLRequest(url: dmgURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 120

        let tempURL = fileManager.temporaryDirectory
            .appendingPathComponent("hostsswitchr-update-\(UUID().uuidString).dmg")
        let fileHandle = try makeWritableTempFile(at: tempURL)

        let redirectGuard = DownloadRedirectGuard()
        let delegate = DownloadBodyDelegate(
            redirectGuard: redirectGuard, fileHandle: fileHandle, maxBytes: Self.maxBytes,
            expectedSize: expectedSize)
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
            if redirectGuard.blockedInsecureRedirect { throw DownloadError.insecureRedirect }
            throw error
        }
        // Even if the delegate finished before cancellation propagated, refuse to move or open.
        if Task.isCancelled { try? fileManager.removeItem(at: tempURL); throw CancellationError() }
        if redirectGuard.blockedInsecureRedirect {
            try? fileManager.removeItem(at: tempURL)
            throw DownloadError.insecureRedirect
        }

        let destination = try uniqueDestination(for: sanitize(suggestedName))
        do {
            try fileManager.moveItem(at: tempURL, to: destination)
        } catch {
            try? fileManager.removeItem(at: tempURL)
            throw DownloadError.writeFailed
        }

        guard NSWorkspace.shared.open(destination) else { throw DownloadError.openFailed }
        return destination
    }

    private func makeWritableTempFile(at url: URL) throws -> FileHandle {
        guard fileManager.createFile(atPath: url.path, contents: nil) else {
            throw DownloadError.writeFailed
        }
        do {
            return try FileHandle(forWritingTo: url)
        } catch {
            try? fileManager.removeItem(at: url)
            throw error
        }
    }

    private func sanitize(_ name: String) -> String {
        let base = (name as NSString).lastPathComponent
        let cleaned = base.replacingOccurrences(of: "/", with: "-")
        let trimmed = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = trimmed.isEmpty ? "HostsSwitchr.dmg" : trimmed
        return fallback.lowercased().hasSuffix(".dmg") ? fallback : fallback + ".dmg"
    }

    private func uniqueDestination(for name: String) throws -> URL {
        let directory: URL
        if let downloads = try? fileManager.url(
            for: .downloadsDirectory, in: .userDomainMask, appropriateFor: nil, create: true) {
            directory = downloads
        } else {
            directory = fileManager.temporaryDirectory
        }

        let ext = (name as NSString).pathExtension
        let stem = (name as NSString).deletingPathExtension
        var candidate = directory.appendingPathComponent(name)
        var index = 1
        while fileManager.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(stem) (\(index)).\(ext)")
            index += 1
        }
        return candidate
    }
}
