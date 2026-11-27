import Foundation

public enum RunnerError: Error, Equatable {
    case scriptFailed(String)
    case invalidResolverDomain(String)
}

public final class AuthorizationPrivilegedRunner: PrivilegedRunner, @unchecked Sendable {
    static let resolverFailedExitCode: Int32 = 3

    public init() {}

    public func apply(_ request: ApplyRequest) throws -> PrivilegedApplyResult {
        try Self.validate(request)
        // Unique app-controlled temp in /etc (same filesystem as target) so concurrent applies can't clobber each other's staged file before the mv.
        let hostsTmp = "/etc/hosts.hsk-tmp.\(UUID().uuidString)"
        // Snapshot written only inside root-only-writable /etc — no symlink-swap path to redirect this root write.
        let bakTmp = "/etc/hosts.hsk-bak.\(UUID().uuidString)"
        let command = Self.command(
            for: request, hostsTmp: hostsTmp, bakTmp: bakTmp,
            resolverTmp: { "/etc/resolver/.hsk-tmp.\(UUID().uuidString)" })

        let escaped = Self.escapeForAppleScriptStringLiteral(command)
        let source = "do shell script \"\(escaped)\" with administrator privileges"
        var errorInfo: NSDictionary?
        guard let script = NSAppleScript(source: source) else {
            throw RunnerError.scriptFailed("Could not construct AppleScript")
        }
        script.executeAndReturnError(&errorInfo)
        let number = errorInfo.map { ($0[NSAppleScript.errorNumber] as? Int) ?? -1 }
        let message = errorInfo?[NSAppleScript.errorMessage] as? String
        return try Self.result(errorNumber: number, message: message, snapshotPath: bakTmp)
    }

    static func validate(_ request: ApplyRequest) throws {
        for domain in request.resolverWrites.map(\.domain) + request.resolverRemovals
        where !WildcardSuffixPolicy.isValid(domain) {
            throw RunnerError.invalidResolverDomain(domain)
        }
    }

    static func command(for request: ApplyRequest, hostsTmp: String, bakTmp: String, resolverTmp: () -> String) -> String {
        let staged = singleQuote(request.stagedPath)
        let tmp = singleQuote(hostsTmp)
        let bak = singleQuote(bakTmp)
        let criticalChain = [
            "cp \(staged) \(tmp)",
            "chown root:wheel \(tmp)",
            "chmod 644 \(tmp)",
            "cp /etc/hosts \(bak)",         // snapshot must be captured immediately before the mv to reflect commit-time /etc/hosts
            "chmod 644 \(bak)",             // 0644 so the unprivileged copy-out can read this root-owned snapshot
            "mv \(tmp) /etc/hosts",         // atomic rename is the commit point — nothing alters /etc/hosts between snapshot and here
        ].joined(separator: " && ")
        // Best-effort (not &&-joined) so a cleanup hiccup can't abort the commit. +5m only, to never delete a concurrent instance's in-flight snapshot. `-H` follows the /etc symlink.
        let cleanup = "find -H /etc -maxdepth 1 -type f -name 'hosts.hsk-bak.*' -mmin +5 -delete 2>/dev/null; "
            + "find -H /etc -maxdepth 1 -type f -name 'hosts.hsk-tmp.*' -mmin +5 -delete 2>/dev/null"
        let tail = "else rm -f \(tmp) \(bak); false; fi"
        guard !request.resolverWrites.isEmpty || !request.resolverRemovals.isEmpty else {
            // DNS flush always exits 0 — a flush failure must not make apply() throw once /etc/hosts is replaced.
            return "\(cleanup); if \(criticalChain); then { dscacheutil -flushcache; killall -HUP mDNSResponder; :; }; " + tail
        }

        // Resolver changes run only after the hosts mv commits; exit 3 tells the caller hosts changed but resolvers may not have.
        let marker = singleQuote(ResolverFile.marker)
        func ifOurs(_ target: String, then action: String = "") -> String {
            "[ ! -L \(target) ] && { [ ! -e \(target) ] || { [ -f \(target) ] "
                + "&& [ \"$(head -n 1 \(target))\" = \(marker) ]\(action); }; }"
        }
        var temps: [String] = []
        var steps = [
            "[ ! -L /etc/resolver ]", "mkdir -m 755 -p /etc/resolver", "[ -O /etc/resolver ]",
            "[ \"$(find -P /etc/resolver -maxdepth 0 ! -perm +022)\" = /etc/resolver ]",
        ]
        for write in request.resolverWrites {
            let temp = singleQuote(resolverTmp())
            let target = singleQuote("/etc/resolver/\(write.domain)")
            temps.append(temp)
            steps += [
                "cp \(singleQuote(write.stagedPath)) \(temp)", "chown root:wheel \(temp)", "chmod 644 \(temp)",
                ifOurs(target), "mv -h \(temp) \(target)",
            ]
        }
        for domain in request.resolverRemovals {
            let target = singleQuote("/etc/resolver/\(domain)")
            steps.append(ifOurs(target, then: " && rm -f \(target)"))
        }
        let reclaim = "find -P /etc/resolver -maxdepth 1 -type f -name '.hsk-tmp.*' -mmin +5 -delete 2>/dev/null"
        let failed = "rc=\(String(resolverFailedExitCode));"
        let onFailure = temps.isEmpty ? failed : "rm -f \(temps.joined(separator: " ")); \(failed)"
        return "\(cleanup); if \(criticalChain); then rc=0; { \(reclaim); \(steps.joined(separator: " && ")); } "
            + "|| { \(onFailure) }; dscacheutil -flushcache; killall -HUP mDNSResponder; exit $rc; " + tail
    }

    static func result(errorNumber: Int?, message: String?, snapshotPath: String) throws -> PrivilegedApplyResult {
        guard let errorNumber else {
            return PrivilegedApplyResult(snapshotPath: snapshotPath, resolverFailed: false, message: nil)
        }
        guard errorNumber == Int(resolverFailedExitCode) else {
            throw RunnerError.scriptFailed(message ?? "Unknown error")
        }
        return PrivilegedApplyResult(snapshotPath: snapshotPath, resolverFailed: true, message: message)
    }

    static func singleQuote(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    static func escapeForAppleScriptStringLiteral(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
         .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
