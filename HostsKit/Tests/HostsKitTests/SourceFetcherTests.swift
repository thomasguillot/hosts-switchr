import Testing
import Foundation
@testable import HostsKit

/// Stub protocol that returns a canned response for the next request. Single-threaded test use.
final class StubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var status: Int = 200
    nonisolated(unsafe) static var headers: [String: String] = [:]
    nonisolated(unsafe) static var body: Data = Data()
    nonisolated(unsafe) static var lastRequestHeaders: [String: String] = [:]

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        StubURLProtocol.lastRequestHeaders = request.allHTTPHeaderFields ?? [:]
        let response = HTTPURLResponse(url: request.url!, statusCode: StubURLProtocol.status,
                                       httpVersion: "HTTP/1.1", headerFields: StubURLProtocol.headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: StubURLProtocol.body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

private func stubbedFetcher() -> SourceFetcher {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [StubURLProtocol.self]
    return SourceFetcher(session: URLSession(configuration: config))
}

private func source() -> RemoteSource {
    RemoteSource(id: UUID(), name: "T", url: URL(string: "https://example.com/h.txt")!, kind: .custom)
}

/// Tests are serialized to prevent races on the shared StubURLProtocol static canned-response state.
@Suite(.serialized)
struct SourceFetcherTests {
    @Test func fetcher_200_returnsUpdatedWithCountsAndHeaders() async throws {
        StubURLProtocol.status = 200
        StubURLProtocol.headers = ["ETag": "v1", "Last-Modified": "Mon, 01 Jan 2026 00:00:00 GMT"]
        StubURLProtocol.body = Data("0.0.0.0 ads.example.com\n0.0.0.0 t.example.net\n".utf8)
        let result = try await stubbedFetcher().fetch(source())
        guard case let .updated(tempURL, etag, lastModified, domainCount) = result else {
            Issue.record("expected .updated"); return
        }
        #expect(etag == "v1")
        #expect(lastModified == "Mon, 01 Jan 2026 00:00:00 GMT")
        #expect(domainCount == 2)
        #expect(FileManager.default.fileExists(atPath: tempURL.path))
        try? FileManager.default.removeItem(at: tempURL)
    }

    @Test func fetcher_304_returnsNotModified() async throws {
        StubURLProtocol.status = 304
        StubURLProtocol.headers = [:]
        StubURLProtocol.body = Data()
        let result = try await stubbedFetcher().fetch(source())
        #expect(result == .notModified)
    }

    @Test func fetcher_sendsConditionalHeaders() async throws {
        StubURLProtocol.status = 304
        StubURLProtocol.headers = [:]
        StubURLProtocol.body = Data()
        var s = source(); s.etag = "v1"; s.lastModified = "Mon, 01 Jan 2026 00:00:00 GMT"
        _ = try await stubbedFetcher().fetch(s)
        #expect(StubURLProtocol.lastRequestHeaders["If-None-Match"] == "v1")
        #expect(StubURLProtocol.lastRequestHeaders["If-Modified-Since"] == "Mon, 01 Jan 2026 00:00:00 GMT")
    }

    @Test func fetcher_notHostsFormat_throws() async throws {
        StubURLProtocol.status = 200
        StubURLProtocol.headers = [:]
        StubURLProtocol.body = Data("! AdGuard\n||ads.example.com^\n".utf8)
        await #expect(throws: SourceError.self) { _ = try await stubbedFetcher().fetch(source()) }
    }

    @Test func fetcher_oversizedContentLength_throws() async throws {
        StubURLProtocol.status = 200
        StubURLProtocol.headers = ["Content-Length": "999999999999"]
        StubURLProtocol.body = Data("0.0.0.0 a.example.com\n".utf8)
        await #expect(throws: SourceError.tooLarge) { _ = try await stubbedFetcher().fetch(source()) }
    }

    @Test func fetcher_noNewlines_largeBody_throwsNotHostsFormat() async throws {
        // A body with no newlines exercises the carry-cap path in streamingScan.
        // Without the cap, each 64 KB chunk would copy the entire carry, making this O(n²).
        StubURLProtocol.status = 200
        StubURLProtocol.headers = [:]
        StubURLProtocol.body = Data(repeating: UInt8(ascii: "x"), count: 256 * 1024)
        await #expect(throws: SourceError.notHostsFormat) {
            _ = try await stubbedFetcher().fetch(source())
        }
    }

    @Test func fetcher_oneValidMapping_thenGarbageNoNewline_throwsNotHostsFormat() async throws {
        // One valid mapping + 8 KB of garbage with no newline: the oversized carry must count as
        // a content line so garbage bytes can't silently vanish from the majority check.
        var body = Data("0.0.0.0 ads.example.com\n".utf8)
        body.append(Data(repeating: UInt8(ascii: "x"), count: 8 * 1024))
        StubURLProtocol.status = 200
        StubURLProtocol.headers = [:]
        StubURLProtocol.body = body
        await #expect(throws: SourceError.notHostsFormat) {
            _ = try await stubbedFetcher().fetch(source())
        }
    }

    @Test func fetcher_longCommentLine_doesNotCountAsContent() async throws {
        // An 8 KB comment line must not count as non-mapping content; two valid mappings after it
        // must still pass the majority check (looksLikeHostsFile == true, domainCount == 2).
        var body = Data(repeating: UInt8(ascii: "#"), count: 1)
        body.append(Data(repeating: UInt8(ascii: "x"), count: 8 * 1024 - 1))
        body.append(Data("\n0.0.0.0 ads.example.com\n0.0.0.0 t.example.net\n".utf8))
        StubURLProtocol.status = 200
        StubURLProtocol.headers = [:]
        StubURLProtocol.body = body
        let result = try await stubbedFetcher().fetch(source())
        guard case let .updated(tempURL, _, _, domainCount) = result else {
            Issue.record("expected .updated"); return
        }
        #expect(domainCount == 2)
        try? FileManager.default.removeItem(at: tempURL)
    }

    // A `#`-led filler of exactly one 64 KB chunk: chunk 0 carries no terminator and the overlong
    // carry is reset, so the next chunk begins precisely at the embedded mapping-like tail — the
    // exact condition under which the buggy code reparses the tail as a fresh mapping line.
    private func overlongCommentLine() -> Data {
        var line = Data("#".utf8)
        line.append(Data(repeating: UInt8(ascii: "x"), count: 65_536 - 1))  // fills chunk 0 exactly
        line.append(Data(" 0.0.0.0 ads.example.com\n".utf8))                 // tail starts a new chunk
        return line
    }

    @Test func fetcher_overlongCommentLine_thenMappings_acceptedNotReparsed() async throws {
        // The overlong comment line must count as ONE non-mapping line; two real mappings after it
        // must yield domainCount == 2, not 3 (the embedded tail must not be reparsed as a mapping).
        var body = overlongCommentLine()
        body.append(Data("0.0.0.0 a.example.com\n0.0.0.0 b.example.net\n".utf8))
        StubURLProtocol.status = 200
        StubURLProtocol.headers = [:]
        StubURLProtocol.body = body
        let result = try await stubbedFetcher().fetch(source())
        guard case let .updated(tempURL, _, _, domainCount) = result else {
            Issue.record("expected .updated"); return
        }
        #expect(domainCount == 2)
        try? FileManager.default.removeItem(at: tempURL)
    }

    @Test func fetcher_onlyOverlongCommentWithMappingText_throwsNotHostsFormat() async throws {
        // A source that is ONLY one giant comment line containing mapping-like text and no real
        // mappings must be rejected: its tail must not be reparsed into an accepted mapping.
        StubURLProtocol.status = 200
        StubURLProtocol.headers = [:]
        StubURLProtocol.body = overlongCommentLine()
        await #expect(throws: SourceError.notHostsFormat) {
            _ = try await stubbedFetcher().fetch(source())
        }
    }

    @Test func fetcher_whitespacePaddedOverlongGarbage_countedAsContent_throwsNotHostsFormat() async throws {
        // A garbage line whose leading whitespace run crosses the 64 KB read chunk: when the first
        // 4 KB carry is all whitespace, the classifying byte is still ahead. It must NOT be skipped
        // early — the trailing "notablocklistentry" garbage must still be counted as content so the
        // lone valid mapping cannot win the majority check and wrongly get the source accepted.
        var body = Data("0.0.0.0 ads.example.com\n".utf8)
        body.append(Data(repeating: UInt8(ascii: " "), count: 70_000))
        body.append(Data("notablocklistentry\n".utf8))
        StubURLProtocol.status = 200
        StubURLProtocol.headers = [:]
        StubURLProtocol.body = body
        await #expect(throws: SourceError.notHostsFormat) {
            _ = try await stubbedFetcher().fetch(source())
        }
    }

    @Test func fetcher_crlfHostsFile_acceptedAsValidFormat() async throws {
        // CRLF line endings leave a lone "\r" after splitting on "\n"; must not be counted as content.
        let crlf = "0.0.0.0 ads.example.com\r\n\r\n0.0.0.0 t.example.net\r\n"
        StubURLProtocol.status = 200
        StubURLProtocol.headers = [:]
        StubURLProtocol.body = Data(crlf.utf8)
        let result = try await stubbedFetcher().fetch(source())
        guard case let .updated(tempURL, _, _, domainCount) = result else {
            Issue.record("expected .updated"); return
        }
        #expect(domainCount == 2)
        try? FileManager.default.removeItem(at: tempURL)
    }

    @Test func fetcher_crOnlyHostsFile_acceptedAsValidFormat() async throws {
        // Classic-Mac bare-CR line endings must be treated as line separators (String.enumerateLines
        // splits on CR too), so a valid CR-delimited hosts file is accepted with the right count.
        let cr = "0.0.0.0 ads.example.com\r\r0.0.0.0 t.example.net\r"
        StubURLProtocol.status = 200
        StubURLProtocol.headers = [:]
        StubURLProtocol.body = Data(cr.utf8)
        let result = try await stubbedFetcher().fetch(source())
        guard case let .updated(tempURL, _, _, domainCount) = result else {
            Issue.record("expected .updated"); return
        }
        #expect(domainCount == 2)
        try? FileManager.default.removeItem(at: tempURL)
    }

    @Test func fetcher_crOnlyMappingThenGarbage_throwsNotHostsFormat() async throws {
        // One valid CR-delimited mapping followed by CR-separated garbage lines: each garbage line
        // must count as content so the majority check fails and the payload is rejected.
        var body = "0.0.0.0 ads.example.com\r".data(using: .utf8)!
        for _ in 0..<20 { body.append(Data("not a hosts line at all\r".utf8)) }
        StubURLProtocol.status = 200
        StubURLProtocol.headers = [:]
        StubURLProtocol.body = body
        await #expect(throws: SourceError.notHostsFormat) {
            _ = try await stubbedFetcher().fetch(source())
        }
    }

    @Test func fetcher_httpError_throws() async throws {
        StubURLProtocol.status = 500
        StubURLProtocol.headers = [:]
        StubURLProtocol.body = Data()
        await #expect(throws: (any Error).self) { _ = try await stubbedFetcher().fetch(source()) }
    }

    @Test func fetcher_storedHTTPSource_failsClosed_noNetwork() async throws {
        // A http:// source left in the catalog from M2 must never be fetched.
        StubURLProtocol.status = 500   // would throw an HTTP error if a request were made
        StubURLProtocol.headers = [:]
        StubURLProtocol.body = Data()
        let http = RemoteSource(
            id: UUID(), name: "Legacy", url: URL(string: "http://example.com/h.txt")!, kind: .custom)
        await #expect(throws: SourceError.insecureURL) { _ = try await stubbedFetcher().fetch(http) }
    }

    @Test func redirectGuard_allowsHTTPSRedirect() async {
        let g = HTTPSRedirectGuard()
        let session = URLSession.shared
        let task = session.dataTask(with: URLRequest(url: URL(string: "https://example.com/h.txt")!))
        let resp = HTTPURLResponse(url: URL(string: "https://example.com/h.txt")!, statusCode: 301,
                                   httpVersion: "HTTP/1.1", headerFields: ["Location": "https://cdn.example.com/h.txt"])!
        let newReq = URLRequest(url: URL(string: "https://cdn.example.com/h.txt")!)
        let result = await g.urlSession(session, task: task, willPerformHTTPRedirection: resp, newRequest: newReq)
        #expect(result != nil)
        #expect(g.blockedInsecureRedirect == false)
    }

    @Test func redirectGuard_blocksHTTPDowngrade() async {
        let g = HTTPSRedirectGuard()
        let session = URLSession.shared
        let task = session.dataTask(with: URLRequest(url: URL(string: "https://example.com/h.txt")!))
        let resp = HTTPURLResponse(url: URL(string: "https://example.com/h.txt")!, statusCode: 301,
                                   httpVersion: "HTTP/1.1", headerFields: ["Location": "http://cdn.example.com/h.txt"])!
        let newReq = URLRequest(url: URL(string: "http://cdn.example.com/h.txt")!)
        let result = await g.urlSession(session, task: task, willPerformHTTPRedirection: resp, newRequest: newReq)
        #expect(result == nil)
        #expect(g.blockedInsecureRedirect == true)
    }
}
