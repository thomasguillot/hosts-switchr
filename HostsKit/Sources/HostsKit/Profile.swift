import Foundation

public struct Profile: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var name: String
    public var content: String
    public var createdAt: Date
    public var updatedAt: Date
    public var isProtected: Bool
    public var sourceIDs: [UUID]
    public var fragmentIDs: [UUID]

    public init(
        id: UUID = UUID(),
        name: String,
        content: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        isProtected: Bool = false,
        sourceIDs: [UUID] = [],
        fragmentIDs: [UUID] = []
    ) {
        self.id = id
        self.name = name
        self.content = content
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isProtected = isProtected
        self.sourceIDs = sourceIDs
        self.fragmentIDs = fragmentIDs
    }
}

public struct ProfileMetadata: Codable, Equatable, Sendable {
    public var order: [UUID]
    public var activeProfileID: UUID?
    public init(order: [UUID] = [], activeProfileID: UUID? = nil) {
        self.order = order
        self.activeProfileID = activeProfileID
    }
}
