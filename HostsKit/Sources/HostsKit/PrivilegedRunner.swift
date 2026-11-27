public struct ResolverWrite: Equatable, Sendable {
    public let domain: String
    public let stagedPath: String
    public init(domain: String, stagedPath: String) {
        self.domain = domain
        self.stagedPath = stagedPath
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
    public let message: String?
    public init(snapshotPath: String, resolverFailed: Bool, message: String? = nil) {
        self.snapshotPath = snapshotPath
        self.resolverFailed = resolverFailed
        self.message = message
    }
}

public protocol PrivilegedRunner: Sendable {
    func apply(_ request: ApplyRequest) throws -> PrivilegedApplyResult
}
