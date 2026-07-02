import Testing
import Foundation
@testable import HostsKit

@Suite struct FragmentStoreTests {
    private func tmpRoot() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    @Test func createUpdateRenameDeleteRoundTrip() throws {
        let root = tmpRoot()
        let store = try FragmentStore(root: root)
        let f = try store.create(name: "Work", content: "0.0.0.0 ads.example")
        #expect(store.fragments.count == 1)

        var edited = f; edited.content = "0.0.0.0 tracker.example"
        try store.update(edited)
        try store.rename(f.id, to: "Work overrides")

        // Reload from disk.
        let store2 = try FragmentStore(root: root)
        let r = store2.fragments.first { $0.id == f.id }
        #expect(r?.name == "Work overrides")
        #expect(r?.content == "0.0.0.0 tracker.example")

        try store2.delete(f.id)
        let store3 = try FragmentStore(root: root)
        #expect(store3.fragments.isEmpty)
    }

    @Test func corruptMetadataPreservedAndStartsEmpty() throws {
        let root = tmpRoot()
        try FileManager.default.createDirectory(at: AppPaths.fragmentsDir(root: root), withIntermediateDirectories: true)
        try "not json{".write(to: AppPaths.fragmentsMetadata(root: root), atomically: true, encoding: .utf8)
        let store = try FragmentStore(root: root)
        #expect(store.loadedCorruptMetadata == true)
        #expect(store.fragments.isEmpty)
        // Original preserved as a .corrupt sibling.
        let corrupt = AppPaths.fragmentsMetadata(root: root).appendingPathExtension("corrupt")
        #expect(FileManager.default.fileExists(atPath: corrupt.path))
    }

    @Test func orderingFollowsCreationThenMetadataOrder() throws {
        let root = tmpRoot()
        let store = try FragmentStore(root: root)
        let a = try store.create(name: "A", content: "")
        let b = try store.create(name: "B", content: "")
        let reloaded = try FragmentStore(root: root)
        #expect(reloaded.fragments.map(\.id) == [a.id, b.id])
    }

    @Test func fragmentStoreAddPreservesID() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = try FragmentStore(root: tmp)
        let id = UUID()
        try store.add(LocalFragment(id: id, name: "F", content: "0.0.0.0 a"))
        let reloaded = try FragmentStore(root: tmp)
        #expect(reloaded.fragments.first?.id == id)
    }

    @Test func create_dedupesDuplicateNames() throws {
        let store = try FragmentStore(root: tmpRoot())
        let a = try store.create(name: "untitled fragment", content: "")
        let b = try store.create(name: "untitled fragment", content: "")
        #expect(a.name == "untitled fragment")
        #expect(b.name == "untitled fragment 2")
    }

    @Test func reorder_persistsAcrossReload() throws {
        let root = tmpRoot()
        let store = try FragmentStore(root: root)
        let a = try store.create(name: "A", content: "")
        let b = try store.create(name: "B", content: "")
        let c = try store.create(name: "C", content: "")

        try store.reorder([c.id, a.id, b.id])
        #expect(store.fragments.map(\.id) == [c.id, a.id, b.id])

        let reloaded = try FragmentStore(root: root)
        #expect(reloaded.fragments.map(\.id) == [c.id, a.id, b.id])
    }

    @Test func reorder_ignoresUnknownIDs() throws {
        let store = try FragmentStore(root: tmpRoot())
        let a = try store.create(name: "A", content: "")
        let b = try store.create(name: "B", content: "")

        try store.reorder([UUID(), b.id, UUID(), a.id])
        #expect(store.fragments.map(\.id) == [b.id, a.id])
    }

    @Test func reorder_appendsOmittedIDsByCreatedAt() throws {
        let store = try FragmentStore(root: tmpRoot())
        let older = LocalFragment(name: "Older", content: "", createdAt: Date(timeIntervalSince1970: 100))
        let newer = LocalFragment(name: "Newer", content: "", createdAt: Date(timeIntervalSince1970: 200))
        try store.add(newer)
        try store.add(older)
        let kept = try store.create(name: "Kept", content: "")

        try store.reorder([kept.id])
        #expect(store.fragments.map(\.id) == [kept.id, older.id, newer.id])
    }

    @Test func rename_toExistingName_throwsDuplicate() throws {
        let store = try FragmentStore(root: tmpRoot())
        _ = try store.create(name: "Docker", content: "")
        let other = try store.create(name: "Staging", content: "")
        #expect(throws: ProfileError.duplicateName) { try store.rename(other.id, to: "Docker") }
    }
}
