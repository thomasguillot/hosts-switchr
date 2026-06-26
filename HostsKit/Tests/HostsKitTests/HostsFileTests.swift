import Testing
@testable import HostsKit

@Test func parse_emptyString_roundTripsToEmpty() {
    #expect(HostsFile(parsing: "").serialized() == "")
}

@Test func parse_roundTrips_preservingCommentsAndBlanks() {
    let text = """
    # Host Database
    127.0.0.1\tlocalhost

    255.255.255.255 broadcasthost
    ::1             localhost
    10.0.0.5 dev.local staging.local # team box
    """
    let file = HostsFile(parsing: text)
    #expect(file.serialized() == text)
}

@Test func parse_extractsMappings() {
    let file = HostsFile(parsing: "127.0.0.1 localhost\n# note\n10.0.0.5 a.local b.local")
    let maps = file.mappings
    #expect(maps.count == 2)
    #expect(maps[0].ip == "127.0.0.1")
    #expect(maps[1].hostnames == ["a.local", "b.local"])
}

@Test func parse_trailingComment_isPartOfRaw_roundTrips() {
    let line = "10.0.0.5 dev.local # comment"
    #expect(HostsFile(parsing: line).serialized() == line)
}

@Test func parse_preservesTrailingNewline() {
    let text = "127.0.0.1 localhost\n"
    #expect(HostsFile(parsing: text).serialized() == text)
}

@Test func parse_noTrailingNewline_staysWithout() {
    let text = "127.0.0.1 localhost"
    #expect(HostsFile(parsing: text).serialized() == text)
}

@Test func paths_areNestedUnderSupportRoot() {
    let root = AppPaths.supportRoot()
    #expect(AppPaths.profilesDir().path.hasPrefix(root.path))
    #expect(AppPaths.backupsDir().path.hasPrefix(root.path))
    #expect(AppPaths.profilesMetadata().path.hasPrefix(root.path))
    #expect(root.lastPathComponent == "HostsSwitchr")
}
