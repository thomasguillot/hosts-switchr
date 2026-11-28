public struct ResolverWrite: Equatable, Sendable {
    public let domain: String
    public let port: UInt16
    public init(domain: String, port: UInt16) {
        self.domain = domain
        self.port = port
    }
}

public struct ApplyRequest: Equatable, Sendable {
    public let stagedPath: String
    public let resolverWrites: [ResolverWrite]
    public let resolverRemovals: [String]
    public init(stagedPath: String, resolverWrites: [ResolverWrite] = [], resolverRemovals: [String] = []) {
        self.stagedPath = stagedPath
        self.resolverWrites = resolverWrites
        self.resolverRemovals = resolverRemovals
    }
}

public struct PrivilegedApplyResult: Equatable, Sendable {
    public let snapshotPath: String
    public let resolverFailed: Bool
    public init(snapshotPath: String, resolverFailed: Bool) {
        self.snapshotPath = snapshotPath
        self.resolverFailed = resolverFailed
    }
}

public protocol PrivilegedRunner: Sendable {
    func apply(_ request: ApplyRequest) throws -> PrivilegedApplyResult
}
