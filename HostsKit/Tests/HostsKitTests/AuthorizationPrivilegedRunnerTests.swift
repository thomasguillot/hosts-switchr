import Foundation
import Testing
@testable import HostsKit

@Suite struct AuthorizationPrivilegedRunnerTests {
    private func command(_ request: ApplyRequest) -> String {
        var n = 0
        return AuthorizationPrivilegedRunner.command(
            for: request, hostsTmp: "/etc/hosts.hsk-tmp.T", bakTmp: "/etc/hosts.hsk-bak.B",
            resolverTmp: { n += 1; return "/etc/resolver/.hsk-tmp.U\(n)" })
    }
    private let head = "find -H /etc -maxdepth 1 -type f -name 'hosts.hsk-bak.*' -mmin +5 -delete 2>/dev/null; "
        + "find -H /etc -maxdepth 1 -type f -name 'hosts.hsk-tmp.*' -mmin +5 -delete 2>/dev/null; "
        + "if cp '/tmp/s.hosts' '/etc/hosts.hsk-tmp.T' && chown root:wheel '/etc/hosts.hsk-tmp.T' && chmod 644 '/etc/hosts.hsk-tmp.T' "
        + "&& cp /etc/hosts '/etc/hosts.hsk-bak.B' && chmod 644 '/etc/hosts.hsk-bak.B' && mv '/etc/hosts.hsk-tmp.T' /etc/hosts; then "
    private let tail = "else rm -f '/etc/hosts.hsk-tmp.T' '/etc/hosts.hsk-bak.B'; false; fi"
    private let marker = "'# Managed by Hosts Switchr. Removed when no wildcard needs it.'"
    private let resolverDirChecks = "[ ! -L /etc/resolver ] && mkdir -m 755 -p /etc/resolver && [ -O /etc/resolver ] && [ \"$(find -P /etc/resolver -maxdepth 0 ! -perm +022)\" = /etc/resolver ] "
        + "&& [ \"$(ls -led /etc/resolver | wc -l | tr -d ' ')\" = 1 ]"
    private let reclaim = "find -P /etc/resolver -maxdepth 1 -type f -name '.hsk-tmp.*' -mmin +5 -delete 2>/dev/null; "

    private func writeGuard(_ target: String) -> String {
        "[ ! -L '\(target)' ] && { [ ! -e '\(target)' ] || { [ -f '\(target)' ] "
            + "&& [ \"$(head -n 1 '\(target)')\" = \(marker) ]; }; }"
    }

    private func removal(_ target: String) -> String {
        "[ ! -L '\(target)' ] && { [ ! -e '\(target)' ] || { [ -f '\(target)' ] "
            + "&& [ \"$(head -n 1 '\(target)')\" = \(marker) ] && rm -f '\(target)'; }; }"
    }

    @Test func withoutResolverChanges_scriptIsUnchanged() {
        #expect(command(ApplyRequest(stagedPath: "/tmp/s.hosts"))
            == head + "{ dscacheutil -flushcache; killall -HUP mDNSResponder; :; }; " + tail)
    }

    @Test func resolverStepRunsAfterHostsCommitAndBeforeFlush() {
        let request = ApplyRequest(stagedPath: "/tmp/s.hosts",
                                   resolverWrites: [ResolverWrite(domain: "test", port: 53535)],
                                   resolverRemovals: ["old.test"])
        #expect(command(request) == head + "rc=0; { " + reclaim
            + "[ ! -L /etc/resolver ] && mkdir -m 755 -p /etc/resolver && [ -O /etc/resolver ] "
            + "&& [ \"$(find -P /etc/resolver -maxdepth 0 ! -perm +022)\" = /etc/resolver ] "
            + "&& [ \"$(ls -led /etc/resolver | wc -l | tr -d ' ')\" = 1 ] "
            + "&& printf '%s\\n' '# Managed by Hosts Switchr. Removed when no wildcard needs it.' 'nameserver 127.0.0.1' 'port 53535' "
            + "> '/etc/resolver/.hsk-tmp.U1' && chown root:wheel '/etc/resolver/.hsk-tmp.U1' "
            + "&& chmod 644 '/etc/resolver/.hsk-tmp.U1' "
            + "&& [ ! -L '/etc/resolver/test' ] && { [ ! -e '/etc/resolver/test' ] || { [ -f '/etc/resolver/test' ] "
            + "&& [ \"$(head -n 1 '/etc/resolver/test')\" = '# Managed by Hosts Switchr. Removed when no wildcard needs it.' ]; }; } "
            + "&& mv -h '/etc/resolver/.hsk-tmp.U1' '/etc/resolver/test' "
            + "&& [ ! -L '/etc/resolver/old.test' ] && { [ ! -e '/etc/resolver/old.test' ] || { [ -f '/etc/resolver/old.test' ] "
            + "&& [ \"$(head -n 1 '/etc/resolver/old.test')\" = '# Managed by Hosts Switchr. Removed when no wildcard needs it.' ] "
            + "&& rm -f '/etc/resolver/old.test'; }; }; "
            + "} || { rm -f '/etc/resolver/.hsk-tmp.U1'; rc=3; }; "
            + "dscacheutil -flushcache; killall -HUP mDNSResponder; exit $rc; " + tail)
    }

    @Test func eachWriteGetsItsOwnTemp() {
        let request = ApplyRequest(stagedPath: "/tmp/s.hosts", resolverWrites: [
            ResolverWrite(domain: "test", port: 53535), ResolverWrite(domain: "corp.internal", port: 53535)])
        let c = command(request)
        #expect(c.contains("mv -h '/etc/resolver/.hsk-tmp.U1' '/etc/resolver/test'"))
        #expect(c.contains("mv -h '/etc/resolver/.hsk-tmp.U2' '/etc/resolver/corp.internal'"))
        #expect(c.contains("} || { rm -f '/etc/resolver/.hsk-tmp.U1' '/etc/resolver/.hsk-tmp.U2'; rc=3; }; "))
    }

    @Test func removalOnlyFailureBranchHasNoTemps() {
        let c = command(ApplyRequest(stagedPath: "/tmp/s.hosts", resolverRemovals: ["test"]))
        #expect(c.contains(resolverDirChecks + " && "
            + removal("/etc/resolver/test") + "; } || { rc=3; }; "))
    }

    @Test func resolverDirectoryMustBeARootOnlyNonSymlinkBeforeAnyWrite() {
        for request in [
            ApplyRequest(stagedPath: "/tmp/s.hosts", resolverWrites: [ResolverWrite(domain: "test", port: 53535)]),
            ApplyRequest(stagedPath: "/tmp/s.hosts", resolverRemovals: ["test"]),
        ] {
            let c = command(request)
            #expect(c.contains("; " + resolverDirChecks + " && "))
            #expect(!c.contains("find -H /etc/resolver"))
        }
    }

    @Test func ownershipIsRecheckedImmediatelyBeforeEachMvAndRm() {
        let request = ApplyRequest(stagedPath: "/tmp/s.hosts",
                                   resolverWrites: [ResolverWrite(domain: "app.test", port: 53535)],
                                   resolverRemovals: ["a.internal", "b.internal"])
        let c = command(request)
        #expect(c.contains("&& chmod 644 '/etc/resolver/.hsk-tmp.U1' && " + writeGuard("/etc/resolver/app.test")
            + " && mv -h '/etc/resolver/.hsk-tmp.U1' '/etc/resolver/app.test' && "))
        #expect(c.contains(" && " + removal("/etc/resolver/a.internal") + " && " + removal("/etc/resolver/b.internal") + "; }"))
        #expect(c.components(separatedBy: "rm -f '/etc/resolver/").count == 4)
        #expect(c.components(separatedBy: " ] && rm -f '/etc/resolver/").count == 3)
        #expect(c.components(separatedBy: "{ rm -f '/etc/resolver/.hsk-tmp.U1'; rc=3; }").count == 2)
    }

    @Test func appleScriptLiteralRoundTripsTheResolverScript() throws {
        let c = command(ApplyRequest(stagedPath: "/tmp/s.hosts",
                                     resolverWrites: [ResolverWrite(domain: "test", port: 53535)],
                                     resolverRemovals: ["old.test"]))
        let literal = AuthorizationPrivilegedRunner.escapeForAppleScriptStringLiteral(c)
        var error: NSDictionary?
        let script = try #require(NSAppleScript(source: "return \"\(literal)\""))
        #expect(script.executeAndReturnError(&error).stringValue == c)
        #expect(error == nil)
    }

    @Test func onlyResolverMovesUseNoFollowMv() {
        let c = command(ApplyRequest(stagedPath: "/tmp/s.hosts",
                                     resolverWrites: [ResolverWrite(domain: "test", port: 53535)]))
        #expect(c.contains("&& mv '/etc/hosts.hsk-tmp.T' /etc/hosts; then "))
        #expect(c.components(separatedBy: "mv -h ").count == 2)
        #expect(c.components(separatedBy: "mv ").count == 3)
    }

    @Test func rootWritesResolverContentFromConstantsAndReadsNoStagedFile() {
        let c = command(ApplyRequest(stagedPath: "/tmp/s.hosts",
                                     resolverWrites: [ResolverWrite(domain: "test", port: 53535),
                                                      ResolverWrite(domain: "app.test", port: 53535)]))
        let printf = "printf '%s\\n' " + ResolverFile.lines(port: 53535).map(AuthorizationPrivilegedRunner.singleQuote)
            .joined(separator: " ")
        #expect(c.contains(printf + " > '/etc/resolver/.hsk-tmp.U1' && "))
        #expect(c.contains(printf + " > '/etc/resolver/.hsk-tmp.U2' && "))
        #expect(c.components(separatedBy: "cp ").count == 3)
        #expect(ResolverFile.lines(port: 53535).map { $0 + "\n" }.joined() == ResolverFile.contents(port: 53535))
    }

    @Test func validateRejectsUnvalidatedDomains() throws {
        for bad in ["../evil", "evil'; rm -rf /", "*.test", "example.com", "Test", "", "internal"] {
            #expect(throws: RunnerError.invalidResolverDomain(bad)) {
                try AuthorizationPrivilegedRunner.validate(ApplyRequest(stagedPath: "/tmp/s",
                    resolverWrites: [ResolverWrite(domain: bad, port: 53535)]))
            }
            #expect(throws: RunnerError.invalidResolverDomain(bad)) {
                try AuthorizationPrivilegedRunner.validate(ApplyRequest(stagedPath: "/tmp/s", resolverRemovals: [bad]))
            }
        }
        try AuthorizationPrivilegedRunner.validate(ApplyRequest(stagedPath: "/tmp/s",
            resolverWrites: [ResolverWrite(domain: "app.test", port: 53535)], resolverRemovals: ["svc.internal"]))
    }

    @Test func resultDistinguishesHostsFailureFromResolverFailure() throws {
        #expect(try AuthorizationPrivilegedRunner.result(errorNumber: nil, message: nil, snapshotPath: "/b")
            == PrivilegedApplyResult(snapshotPath: "/b", resolverFailed: false))
        #expect(try AuthorizationPrivilegedRunner.result(errorNumber: 3, message: "x", snapshotPath: "/b")
            == PrivilegedApplyResult(snapshotPath: "/b", resolverFailed: true))
        #expect(throws: RunnerError.scriptFailed("boom")) {
            try AuthorizationPrivilegedRunner.result(errorNumber: 1, message: "boom", snapshotPath: "/b")
        }
        #expect(throws: RunnerError.scriptFailed("User canceled.")) {
            try AuthorizationPrivilegedRunner.result(errorNumber: -128, message: "User canceled.", snapshotPath: "/b")
        }
        #expect(AuthorizationPrivilegedRunner.resolverFailedExitCode == 3)
    }
}

@Suite struct ResolverStepShellTests {
    private struct Sandbox {
        let root: URL
        let dir: URL
        let ours = ResolverFile.contents(port: 53535)

        init() throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent("resolver-sh-\(UUID().uuidString)")
            dir = root.appendingPathComponent("resolver")
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        }

        func file(_ name: String) -> URL { dir.appendingPathComponent(name) }

        func put(_ name: String, _ text: String) throws {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try text.write(to: file(name), atomically: true, encoding: .utf8)
        }

        func read(_ name: String) -> String? { try? String(contentsOf: file(name), encoding: .utf8) }

        func temps() -> [String] {
            ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []).filter { $0.hasPrefix(".hsk-tmp.") }
        }

        func run(
            _ shell: String, writes: [String] = [], removals: [String] = [], in target: URL? = nil, prefix: String = ""
        ) throws -> Int32 {
            var n = 0
            let full = AuthorizationPrivilegedRunner.command(
                for: ApplyRequest(stagedPath: "/tmp/s.hosts",
                                  resolverWrites: writes.map { ResolverWrite(domain: $0, port: 53535) },
                                  resolverRemovals: removals),
                hostsTmp: "/etc/hosts.hsk-tmp.T", bakTmp: "/etc/hosts.hsk-bak.B",
                resolverTmp: { n += 1; return "/etc/resolver/.hsk-tmp.U\(n)" })
            let start = try #require(full.range(of: "; then "))
            let end = try #require(full.range(of: " dscacheutil -flushcache"))
            let step = String(full[start.upperBound..<end.lowerBound])
                .replacingOccurrences(of: "/etc/resolver", with: (target ?? dir).path)
                .replacingOccurrences(of: "chown root:wheel", with: ":")
            let process = Process()
            process.executableURL = URL(fileURLWithPath: shell)
            process.arguments = ["-c", prefix + step + " exit $rc"]
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus
        }

        func stale(_ url: URL) throws {
            try ours.write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-600)], ofItemAtPath: url.path)
        }

        func clean() {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dir.path)
            try? FileManager.default.removeItem(at: root)
        }
    }

    @Test(arguments: ["/bin/sh", "/bin/dash"])
    func writesAbsentAndOwnedFilesAndRemovesOwnedOnes(shell: String) throws {
        let box = try Sandbox()
        defer { box.clean() }
        try box.put("corp.internal", ResolverFile.marker + "\nnameserver 127.0.0.1\nport 1\n")
        try box.put("old.test", box.ours)

        #expect(try box.run(shell, writes: ["test", "corp.internal"], removals: ["old.test", "gone.test"]) == 0)
        #expect(box.read("test") == box.ours)
        #expect(box.read("corp.internal") == box.ours)
        #expect(!FileManager.default.fileExists(atPath: box.file("old.test").path))
        #expect(box.temps().isEmpty)
    }

    @Test(arguments: ["/bin/sh", "/bin/dash"])
    func refusesToOverwriteAForeignFile(shell: String) throws {
        let box = try Sandbox()
        defer { box.clean() }
        try box.put("test", "nameserver 9.9.9.9\n")

        #expect(try box.run(shell, writes: ["test"]) == 3)
        #expect(box.read("test") == "nameserver 9.9.9.9\n")
        #expect(box.temps().isEmpty)
    }

    @Test(arguments: ["/bin/sh", "/bin/dash"])
    func refusesToRemoveAForeignFile(shell: String) throws {
        let box = try Sandbox()
        defer { box.clean() }
        try box.put("test", "nameserver 9.9.9.9\n" + ResolverFile.marker + "\n")

        #expect(try box.run(shell, removals: ["test"]) == 3)
        #expect(box.read("test") == "nameserver 9.9.9.9\n" + ResolverFile.marker + "\n")
    }

    @Test(arguments: ["/bin/sh", "/bin/dash"])
    func refusesSymlinkAndDirectoryTargetsEvenWhenTheyPointAtOurFile(shell: String) throws {
        let box = try Sandbox()
        defer { box.clean() }
        let elsewhere = box.root.appendingPathComponent("elsewhere")
        try box.ours.write(to: elsewhere, atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: box.dir, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: box.file("test"), withDestinationURL: elsewhere)
        try FileManager.default.createDirectory(at: box.file("corp.internal"), withIntermediateDirectories: true)

        #expect(try box.run(shell, writes: ["test"]) == 3)
        #expect(try box.run(shell, removals: ["test"]) == 3)
        #expect(try box.run(shell, writes: ["corp.internal"]) == 3)
        #expect(try box.run(shell, removals: ["corp.internal"]) == 3)
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: box.file("test").path) == elsewhere.path)
        #expect(try String(contentsOf: elsewhere, encoding: .utf8) == box.ours)
        #expect(try FileManager.default.contentsOfDirectory(atPath: box.file("corp.internal").path).isEmpty)
        #expect(box.temps().isEmpty)
    }

    @Test(arguments: ["/bin/sh", "/bin/dash"])
    func noFollowMvReplacesASymlinkToADirectoryInsteadOfMovingIntoIt(shell: String) throws {
        let box = try Sandbox()
        defer { box.clean() }
        let elsewhere = box.root.appendingPathComponent("elsewhere", isDirectory: true)
        try FileManager.default.createDirectory(at: elsewhere, withIntermediateDirectories: true)
        try box.put(".hsk-tmp.U1", box.ours)
        try FileManager.default.createSymbolicLink(at: box.file("test"), withDestinationURL: elsewhere)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: shell)
        process.arguments = ["-c", "mv -h '\(box.file(".hsk-tmp.U1").path)' '\(box.file("test").path)'"]
        try process.run()
        process.waitUntilExit()

        #expect(process.terminationStatus == 0)
        #expect(box.read("test") == box.ours)
        #expect(try FileManager.default.contentsOfDirectory(atPath: elsewhere.path).isEmpty)
    }

    @Test(arguments: ["/bin/sh", "/bin/dash"])
    func refusesAGroupOrWorldWritableResolverDirectory(shell: String) throws {
        let box = try Sandbox()
        defer { box.clean() }
        for mode in [0o777, 0o775, 0o757] {
            try FileManager.default.createDirectory(at: box.dir, withIntermediateDirectories: true)
            try FileManager.default.setAttributes([.posixPermissions: mode], ofItemAtPath: box.dir.path)

            #expect(try box.run(shell, writes: ["test"], removals: ["gone.test"]) == 3)
            #expect(try FileManager.default.contentsOfDirectory(atPath: box.dir.path).isEmpty)
        }
    }

    @Test(arguments: ["/bin/sh", "/bin/dash"])
    func refusesAResolverDirectoryCarryingAnACL(shell: String) throws {
        let box = try Sandbox()
        defer { box.clean() }
        try FileManager.default.createDirectory(at: box.dir, withIntermediateDirectories: true)
        let chmod = Process()
        chmod.executableURL = URL(fileURLWithPath: "/bin/chmod")
        chmod.arguments = ["+a", "everyone allow add_file,delete_child", box.dir.path]
        try chmod.run()
        chmod.waitUntilExit()
        try #require(chmod.terminationStatus == 0)

        #expect(try box.run(shell, writes: ["test"], removals: ["gone.test"]) == 3)
        #expect(try FileManager.default.contentsOfDirectory(atPath: box.dir.path).isEmpty)
    }

    @Test(arguments: ["/bin/sh", "/bin/dash"])
    func refusesAResolverDirectoryOwnedBySomeoneElse(shell: String) throws {
        let box = try Sandbox()
        defer { box.clean() }
        let rootOwned = URL(fileURLWithPath: "/var/empty", isDirectory: true)
        let owner = try FileManager.default.attributesOfItem(atPath: rootOwned.path)[.ownerAccountID] as? NSNumber
        try #require(owner?.uint32Value != getuid())

        #expect(try box.run(shell, removals: ["gone.test"], in: rootOwned) == 3)
        #expect(try box.run(shell, removals: ["gone.test"]) == 0)
    }

    @Test(arguments: ["/bin/sh", "/bin/dash"])
    func createsTheResolverDirectoryRootOnlyWhateverTheUmask(shell: String) throws {
        let box = try Sandbox()
        defer { box.clean() }

        #expect(try box.run(shell, writes: ["test"], prefix: "umask 000; ") == 0)
        let mode = try FileManager.default.attributesOfItem(atPath: box.dir.path)[.posixPermissions] as? NSNumber
        #expect(mode?.intValue == 0o755)
        #expect(box.read("test") == box.ours)
    }

    @Test(arguments: ["/bin/sh", "/bin/dash"])
    func reclaimDeletesStaleTempsInTheRealDirectoryOnly(shell: String) throws {
        let box = try Sandbox()
        defer { box.clean() }
        try FileManager.default.createDirectory(at: box.dir, withIntermediateDirectories: true)
        try box.stale(box.file(".hsk-tmp.OLD"))
        #expect(try box.run(shell, removals: ["gone.test"]) == 0)
        #expect(box.temps().isEmpty)

        try FileManager.default.removeItem(at: box.dir)
        let real = box.root.appendingPathComponent("real")
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
        try box.stale(real.appendingPathComponent(".hsk-tmp.OLD"))
        try FileManager.default.createSymbolicLink(at: box.dir, withDestinationURL: real)
        #expect(try box.run(shell, removals: ["gone.test"]) == 3)
        #expect(try FileManager.default.contentsOfDirectory(atPath: real.path) == [".hsk-tmp.OLD"])
    }

    @Test(arguments: ["/bin/sh", "/bin/dash"])
    func refusesASymlinkedResolverDirectory(shell: String) throws {
        let box = try Sandbox()
        defer { box.clean() }
        let real = box.root.appendingPathComponent("real")
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
        try box.ours.write(to: real.appendingPathComponent("old.test"), atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(at: box.dir, withDestinationURL: real)

        #expect(try box.run(shell, writes: ["test"], removals: ["old.test"]) == 3)
        #expect(try FileManager.default.contentsOfDirectory(atPath: real.path) == ["old.test"])
    }
}
