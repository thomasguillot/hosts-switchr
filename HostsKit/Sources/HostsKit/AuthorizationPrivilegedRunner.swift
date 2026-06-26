import Foundation

public enum RunnerError: Error, Equatable {
    case scriptFailed(String)
}

public final class AuthorizationPrivilegedRunner: PrivilegedRunner, @unchecked Sendable {
    public init() {}

    public func apply(_ request: ApplyRequest) throws -> String {
        let staged = Self.singleQuote(request.stagedPath)
        // Unique app-controlled temp in /etc (same filesystem as target) so concurrent applies can't clobber each other's staged file before the mv.
        let tmp = Self.singleQuote("/etc/hosts.hsk-tmp.\(UUID().uuidString)")
        // Snapshot written only inside root-only-writable /etc — no symlink-swap path to redirect this root write.
        let bakTmpPath = "/etc/hosts.hsk-bak.\(UUID().uuidString)"
        let bakTmp = Self.singleQuote(bakTmpPath)
        let criticalChain = [
            "cp \(staged) \(tmp)",
            "chown root:wheel \(tmp)",
            "chmod 644 \(tmp)",
            "cp /etc/hosts \(bakTmp)",      // snapshot must be captured immediately before the mv to reflect commit-time /etc/hosts
            "chmod 644 \(bakTmp)",          // 0644 so the unprivileged copy-out can read this root-owned snapshot
            "mv \(tmp) /etc/hosts",         // atomic rename is the commit point — nothing alters /etc/hosts between snapshot and here
        ].joined(separator: " && ")
        // Best-effort (not &&-joined) so a cleanup hiccup can't abort the commit. +5m only, to never delete a concurrent instance's in-flight snapshot. `-H` follows the /etc symlink.
        let cleanup = "find -H /etc -maxdepth 1 -type f -name 'hosts.hsk-bak.*' -mmin +5 -delete 2>/dev/null; "
            + "find -H /etc -maxdepth 1 -type f -name 'hosts.hsk-tmp.*' -mmin +5 -delete 2>/dev/null"
        // DNS flush always exits 0 — a flush failure must not make apply() throw once /etc/hosts is replaced.
        let command = "\(cleanup); if \(criticalChain); then { dscacheutil -flushcache; killall -HUP mDNSResponder; :; }; "
            + "else rm -f \(tmp) \(bakTmp); false; fi"

        let escaped = Self.escapeForAppleScriptStringLiteral(command)
        let source = "do shell script \"\(escaped)\" with administrator privileges"
        var errorInfo: NSDictionary?
        guard let script = NSAppleScript(source: source) else {
            throw RunnerError.scriptFailed("Could not construct AppleScript")
        }
        script.executeAndReturnError(&errorInfo)
        if let errorInfo {
            let message = errorInfo[NSAppleScript.errorMessage] as? String ?? "Unknown error"
            throw RunnerError.scriptFailed(message)
        }
        return bakTmpPath
    }

    static func singleQuote(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    static func escapeForAppleScriptStringLiteral(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
         .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
