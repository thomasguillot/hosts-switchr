public struct ApplyRequest: Equatable, Sendable {
    public let stagedPath: String
    public init(stagedPath: String) {
        self.stagedPath = stagedPath
    }
}

public protocol PrivilegedRunner: Sendable {
    func apply(_ request: ApplyRequest) throws -> String
}
