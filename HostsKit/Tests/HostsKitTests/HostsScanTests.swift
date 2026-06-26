import Testing
@testable import HostsKit

@Test func scan_countsMappingLines_ignoringCommentsAndBlanks() {
    let text = "# header\n0.0.0.0 ads.example.com\n\n0.0.0.0 tracker.example.net\n# note"
    #expect(HostsScan.mappingLineCount(text) == 2)
}

@Test func scan_adblockSyntax_hasNoMappings() {
    let text = "! Title: AdGuard\n||ads.example.com^\n||tracker.example.net^"
    #expect(HostsScan.mappingLineCount(text) == 0)
}

@Test func looksLikeHosts_trueForRealHostsFile() {
    let text = "# header\n0.0.0.0 ads.example.com\n0.0.0.0 t.example.net\n::1 localhost\n"
    #expect(HostsScan.looksLikeHostsFile(text) == true)
}

@Test func looksLikeHosts_falseForAdblockSyntax() {
    let text = "! Title: AdGuard\n||ads.example.com^\n||tracker.example.net^\n"
    #expect(HostsScan.looksLikeHostsFile(text) == false)
}

@Test func looksLikeHosts_falseForAdblockWithOneStrayIP() {
    // One IP-like line among many adblock rules must NOT pass the guard.
    let text = "! Title\n0.0.0.0 a.example.com\n||b.example.com^\n||c.example.com^\n||d.example.com^\n"
    #expect(HostsScan.looksLikeHostsFile(text) == false)
}

@Test func looksLikeHosts_falseForEmptyOrAllComments() {
    #expect(HostsScan.looksLikeHostsFile("") == false)
    #expect(HostsScan.looksLikeHostsFile("# only\n# comments\n\n") == false)
}

@Test func scan_rejectsNonIPDigitTokens() {
    // A one-line HTTP error body must not look like a hosts file.
    #expect(HostsScan.looksLikeHostsFile("404 Not Found") == false)
    #expect(HostsScan.looksLikeHostsFile("200 OK") == false)
    #expect(HostsScan.looksLikeHostsFile("503 Service Unavailable\n") == false)
    #expect(HostsScan.mappingLineCount("404 Not Found") == 0)
}

@Test func scan_acceptsValidIPMappings() {
    let text = "0.0.0.0 ads.example.com\n127.0.0.1 localhost\n::1 localhost\n"
    #expect(HostsScan.looksLikeHostsFile(text) == true)
    #expect(HostsScan.mappingLineCount(text) == 3)
}
