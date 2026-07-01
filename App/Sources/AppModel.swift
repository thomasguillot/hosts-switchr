import Foundation
import Observation
import UserNotifications
import HostsKit

@MainActor
@Observable
final class AppModel {
    private(set) var profiles: [Profile] = []
    private(set) var sources: [RemoteSource] = []
    private(set) var fragments: [LocalFragment] = []
    var selectedProfileID: UUID?
    var selectedFragmentID: UUID?
    private(set) var activeProfileID: UUID?
    private(set) var staleProfileIDs: Set<UUID> = []
    var lastError: String?

    private var store: ProfileStore?
    private(set) var catalog: SourceCatalog?
    private var fragmentStore: FragmentStore?
    private var fragmentSaveTask: Task<Void, Never>?
    private var pendingFragmentSave: LocalFragment?
    private let applier: HostsApplier
    private let runner: AuthorizationPrivilegedRunner
    private let composer = MergedHostsComposer()
    private let fetcher: SourceFetching
    private var prefs = Preferences()
    private var saveTask: Task<Void, Never>?
    private var pendingSave: Profile?
    private var scheduler: RefreshScheduler?
    private var didBootstrap = false

    init() {
        self.runner = AuthorizationPrivilegedRunner()
        self.applier = HostsApplier(runner: runner, backupsDir: AppPaths.backupsDir())
        self.fetcher = SourceFetcher()
    }

    func bootstrap() {
        if didBootstrap { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { _, _ in }
        do {
            let root = AppPaths.supportRoot()
            let store = try ProfileStore(root: root)
            let catalog = try SourceCatalog(root: root)
            self.store = store
            self.catalog = catalog
            let fragmentStore = try FragmentStore(root: root)
            self.fragmentStore = fragmentStore
            if store.loadedCorruptMetadata {
                lastError = "Your saved profile list was unreadable and has been set aside as profiles.json.corrupt. Profiles were recovered from disk with default names/order; rename and reorder as needed."
            } else if catalog.loadedCorruptMetadata {
                lastError = "Your saved sources list was unreadable and has been set aside as sources.json.corrupt. Built-in sources were restored; re-add any custom sources."
            } else if fragmentStore.loadedCorruptMetadata {
                lastError = "Your saved fragment list was unreadable and has been set aside as fragments.json.corrupt. Recreate any local fragments as needed."
            }
            let current: String
            do { current = try String(contentsOfFile: "/etc/hosts", encoding: .utf8) } catch {
                lastError = "Couldn't read /etc/hosts (\(error.localizedDescription)); seeding a default."
                current = "##\n# Host Database\n##\n127.0.0.1\tlocalhost\n255.255.255.255\tbroadcasthost\n::1\tlocalhost\n"
            }
            try store.seedSystemDefaultIfEmpty(currentHosts: current)
            refresh()
            if scheduler == nil {
                let s = RefreshScheduler(model: self); s.start(); self.scheduler = s
            }
            didBootstrap = true   // set only on full success, so a seed/load failure remains retryable
        } catch {
            lastError = "Couldn’t load your saved profiles. Please reopen the app, and if this keeps happening, restart your Mac."
        }
    }

    func rescheduleRefresh() { scheduler?.reschedule() }

    private func refresh() {
        guard let store, let catalog else { return }
        profiles = store.profiles
        // Don't clobber an unsaved in-flight edit; else apply could write stale content.
        if let pending = pendingSave, let idx = profiles.firstIndex(where: { $0.id == pending.id }) {
            profiles[idx] = pending
        }
        activeProfileID = store.activeProfileID
        sources = catalog.sources
        if let fragmentStore {
            fragments = fragmentStore.fragments
            if let pf = pendingFragmentSave, let i = fragments.firstIndex(where: { $0.id == pf.id }) { fragments[i] = pf }
        }
    }

    private func notify(_ title: String, _ body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: Profiles

    @discardableResult
    func createProfile() -> UUID? {
        guard let store else { return nil }
        do {
            let profile = try store.create(name: "untitled profile", content: "")
            refresh()
            selectedProfileID = profile.id
            return profile.id
        } catch {
            lastError = "Something went wrong saving that change. Please try again."
            return nil
        }
    }

    func duplicateSelected() {
        guard let id = selectedProfileID else { return }
        flushPendingSave()
        run { store in _ = try store.duplicate(id) }
    }

    func rename(_ id: UUID, to name: String) {
        guard let store else { return }
        do { try store.rename(id, to: name); refresh() }
        catch ProfileError.duplicateName { lastError = "The name “\(name)” is already taken. Please choose a different name." }
        catch { lastError = "Something went wrong saving that change. Please try again." }
    }

    func deleteSelected() {
        guard let id = selectedProfileID else { return }
        let deletedIndex = profiles.firstIndex(where: { $0.id == id })
        if pendingSave?.id == id { saveTask?.cancel(); saveTask = nil; pendingSave = nil }
        run { store in try store.delete(id) }
        if selectedProfileID == id {
            if profiles.isEmpty { selectedProfileID = nil }
            else if let idx = deletedIndex {
                selectedProfileID = profiles[min(idx, profiles.count - 1)].id
            }
        }
    }

    func updateContent(_ id: UUID, content: String) {
        guard let idx = profiles.firstIndex(where: { $0.id == id }) else { return }
        if profiles[idx].content == content { return }
        profiles[idx].content = content
        if id == activeProfileID { staleProfileIDs.insert(id) }
        let snapshot = profiles[idx]
        pendingSave = snapshot
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            if Task.isCancelled { return }
            await MainActor.run {
                // Act only on the latest pending edit; clear only on a successful write so a failed save keeps it pending and composeAndApply refuses to publish it.
                if self?.pendingSave == snapshot, self?.persist(snapshot) == true { self?.pendingSave = nil }
            }
        }
    }

    @discardableResult
    private func persist(_ profile: Profile) -> Bool {
        guard let store else { return false }
        do { try store.update(profile); return true } catch { lastError = "Couldn’t save your changes. Please try again."; return false }
    }

    func flushPendingSave() {
        saveTask?.cancel(); saveTask = nil
        // Clear only on a successful write so unpersisted content is never published to /etc/hosts.
        if let p = pendingSave, persist(p) { pendingSave = nil }
        flushPendingFragmentSave()
    }

    func warnings(for id: UUID) -> [HostsWarning] {
        guard let p = profiles.first(where: { $0.id == id }) else { return [] }
        return HostsValidator.validate(HostsFile(parsing: p.content))
    }

    // MARK: Per-profile source selection

    func setProfileSources(_ id: UUID, _ ids: [UUID]) {
        flushPendingSave()
        run { store in try store.setSources(id, ids) }
        if id == activeProfileID { staleProfileIDs.insert(id) }
    }

    // MARK: Fragments

    @discardableResult
    func createFragment() -> UUID? {
        guard let fragmentStore else { return nil }
        do { let f = try fragmentStore.create(name: "untitled fragment", content: ""); refresh(); selectedFragmentID = f.id; return f.id }
        catch { lastError = "Couldn’t create the fragment. Please try again."; return nil }
    }

    func renameFragment(_ id: UUID, to name: String) {
        guard let fragmentStore else { return }
        do { try fragmentStore.rename(id, to: name); refresh() }
        catch ProfileError.duplicateName { lastError = "The name “\(name)” is already taken. Please choose a different name." }
        catch { lastError = "Couldn’t rename the fragment. Please try again." }
    }

    func deleteFragment(_ id: UUID) {
        guard let fragmentStore, let store else { return }
        if pendingFragmentSave?.id == id { fragmentSaveTask?.cancel(); fragmentSaveTask = nil; pendingFragmentSave = nil }
        // Capture before removal: removeFragmentFromAllProfiles strips the id from every fragmentIDs.
        let affected = profiles.filter { $0.fragmentIDs.contains(id) }.map(\.id)
        do {
            try store.removeFragmentFromAllProfiles(id)
            try fragmentStore.delete(id)
        } catch { lastError = "Couldn’t delete the fragment. Please try again." }
        if selectedFragmentID == id { selectedFragmentID = nil }
        if let activeID = activeProfileID, affected.contains(activeID) { staleProfileIDs.insert(activeID) }
        refresh()
    }

    func warningsForFragment(_ id: UUID) -> [HostsWarning] {
        guard let f = fragments.first(where: { $0.id == id }) else { return [] }
        return HostsValidator.validate(HostsFile(parsing: f.content))
    }

    func updateFragmentContent(_ id: UUID, content: String) {
        guard let idx = fragments.firstIndex(where: { $0.id == id }) else { return }
        if fragments[idx].content == content { return }
        fragments[idx].content = content; fragmentGeneration += 1   // bump: an apply composing in parallel must not clear this profile's badge
        // Only the active profile is live in /etc/hosts; others recompose fresh on apply, so don't badge them.
        if let activeID = activeProfileID,
           profiles.contains(where: { $0.id == activeID && $0.fragmentIDs.contains(id) }) {
            staleProfileIDs.insert(activeID)
        }
        let snapshot = fragments[idx]
        pendingFragmentSave = snapshot
        fragmentSaveTask?.cancel()
        fragmentSaveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            if Task.isCancelled { return }
            let saved: Bool = await MainActor.run {
                guard let self, self.pendingFragmentSave == snapshot else { return false }  // act only on the latest pending edit
                let ok = self.persistFragment(snapshot)
                if ok { self.pendingFragmentSave = nil }
                return ok
            }
            if saved { await self?.autoReapplyIfActiveIncludesFragment(snapshot.id) }
        }
    }

    @discardableResult
    private func persistFragment(_ fragment: LocalFragment) -> Bool {
        guard let fragmentStore else { return false }
        do { try fragmentStore.update(fragment); return true } catch { lastError = "Couldn’t save your changes. Please try again."; return false }
    }

    func flushPendingFragmentSave() {
        fragmentSaveTask?.cancel(); fragmentSaveTask = nil
        if let f = pendingFragmentSave, persistFragment(f) { pendingFragmentSave = nil }
    }

    func setProfileFragments(_ id: UUID, _ ids: [UUID]) {
        flushPendingSave()
        run { store in try store.setFragments(id, ids) }
        if id == activeProfileID { staleProfileIDs.insert(id) }
    }

    func autoReapplyIfActiveIncludesFragment(_ fragmentID: UUID) async {
        guard prefs.autoReapply, !isApplying,
              let activeID = activeProfileID,
              let active = profiles.first(where: { $0.id == activeID }),
              active.fragmentIDs.contains(fragmentID) else { return }
        isApplying = true
        defer { isApplying = false }
        if activeProfileID == activeID {
            do {
                let outcome = try await composeAndApply(active)
                if snapshotIsCurrent(active) && sourceCacheGeneration == outcome.sourceGen && fragmentGeneration == outcome.fragGen { staleProfileIDs.remove(activeID) }
                notify("Hosts Switchr", "Updated \(active.name) from an edited fragment")
            } catch {
                lastError = "Auto re-apply failed (\(error.localizedDescription)). Re-apply when ready."
            }
        }
    }

    // MARK: Import / Export

    struct ImportSummary {
        var profilesAdded = 0
        var fragmentsAdded = 0
        var sourcesAdded = 0
        var skipped = 0
        var warnings: [String] = []
    }

    enum HostsImportKind { case profile, fragment }

    func exportConfigData() -> Data? {
        guard let store, let fragmentStore, let catalog else { return nil }
        flushPendingSave()
        let bundle = ConfigBundle.export(profiles: store.profiles, fragments: fragmentStore.fragments,
                                         sources: catalog.sources, exportedAt: Date())
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        do { return try encoder.encode(bundle) }
        catch { lastError = "Couldn't create backup: \(error.localizedDescription)"; return nil }
    }

    @discardableResult
    func importBundle(_ data: Data, mode: ConfigBundle.ImportMode) -> ImportSummary? {
        guard let store, let fragmentStore, let catalog else { return nil }
        flushPendingSave()
        let bundle: ConfigBundle
        do { bundle = try ConfigBundle.decode(data) }
        catch ConfigBundle.ImportError.unsupportedVersion(let v) {
            lastError = "This backup was made by a different version of Hosts Switchr (format \(v)). Update the app and try again."
            return nil
        } catch {
            lastError = "This file isn't a valid Hosts Switchr backup."
            return nil
        }
        let plan = ConfigBundle.plan(bundle, mode: mode, existingProfiles: store.profiles,
                                     existingFragments: fragmentStore.fragments, existingSources: catalog.sources)
        var summary = ImportSummary(warnings: plan.insecureSourceWarnings)
        do { try applyImportPlan(plan, store: store, fragmentStore: fragmentStore, catalog: catalog, summary: &summary) }
        catch { lastError = "Import failed partway: \(error.localizedDescription)" }
        let totalItems = bundle.profiles.count + bundle.fragments.count + bundle.customSources.count
        summary.skipped = max(0, totalItems - summary.profilesAdded - summary.fragmentsAdded
                                  - summary.sourcesAdded - summary.warnings.count)
        refresh()
        if selectedProfileID == nil || !profiles.contains(where: { $0.id == selectedProfileID }) { selectedProfileID = profiles.first?.id }
        if let sf = selectedFragmentID, !fragments.contains(where: { $0.id == sf }) { selectedFragmentID = nil }
        return summary
    }

    private func applyImportPlan(_ plan: ConfigBundle.ImportPlan,
                                 store: ProfileStore, fragmentStore: FragmentStore,
                                 catalog: SourceCatalog, summary: inout ImportSummary) throws {
        for id in plan.customSourceIDsToDelete { try catalog.remove(id) }
        for id in plan.fragmentIDsToDelete { try fragmentStore.delete(id) }
        for id in plan.profileIDsToDelete { try store.delete(id) }
        for s in plan.sourcesToAdd {
            let url = try SourceURLPolicy.validated(s.url)
            try catalog.add(RemoteSource(id: s.id, name: s.name, url: url, kind: .custom))
            summary.sourcesAdded += 1
        }
        for f in plan.fragmentsToAdd {
            try fragmentStore.add(LocalFragment(id: f.id, name: f.name, content: f.content))
            summary.fragmentsAdded += 1
        }
        for p in plan.profilesToAdd {
            try store.add(Profile(id: p.id, name: p.name, content: p.content,
                                  isProtected: false, sourceIDs: p.sourceIDs, fragmentIDs: p.fragmentIDs))
            summary.profilesAdded += 1
        }
    }

    func importHostsFile(at url: URL, as kind: HostsImportKind) {
        let content: String
        do { content = try String(contentsOf: url, encoding: .utf8) }
        catch { lastError = "Couldn't read \(url.lastPathComponent): \(error.localizedDescription)"; return }
        let base = url.deletingPathExtension().lastPathComponent
        let name = base.isEmpty ? "Imported" : base
        switch kind {
        case .profile:
            guard let store else { return }
            do { try store.add(Profile(name: name, content: content)); refresh(); selectedProfileID = profiles.last?.id }
            catch { lastError = "Couldn't import as profile: \(error.localizedDescription)" }
        case .fragment:
            guard let fragmentStore else { return }
            do { _ = try fragmentStore.add(LocalFragment(name: name, content: content)); refresh() }
            catch { lastError = "Couldn't import as fragment: \(error.localizedDescription)" }
        }
    }

    // MARK: Catalog management

    // Returns nil on success, or a user-facing message to show inline at the add point.
    @discardableResult
    func addSource(name: String, url: String) -> String? {
        guard let catalog else { return "Something went wrong. Please try again." }
        do { _ = try catalog.addCustom(name: name, urlString: url); refresh(); return nil }
        catch { return error.userFacingMessage }
    }

    func removeSource(_ id: UUID) {
        guard let catalog, let store else { return }
        flushPendingSave()
        guard let src = catalog.source(for: id) else { lastError = "Source not found."; return }
        guard src.kind == .custom else { lastError = "Built-in sources can't be removed."; return }
        let affected = profiles.filter { $0.sourceIDs.contains(id) }  // capture prior lists for rollback
        do {
            try store.removeSourceFromAllProfiles(id)
            do { try catalog.remove(id) } catch {
                // Roll back so a failed catalog delete doesn't detach the source from every profile.
                for p in affected { try? store.setSources(p.id, p.sourceIDs) }; throw error
            }
            for p in affected { staleProfileIDs.insert(p.id) }
            refresh()
        } catch { lastError = "Couldn’t remove the source. Please try again."; refresh() }
    }

    // MARK: Apply errors

    enum ApplyError: LocalizedError {
        case missingSourceCaches([String])
        case missingSourceRecords([String])
        case unsavedEdit
        var errorDescription: String? {
            switch self {
            case let .missingSourceCaches(names):
                return "Can't apply — these sources haven't been downloaded yet: \(names.joined(separator: ", ")). Refresh sources first."
            case let .missingSourceRecords(ids):
                return "Can't apply — \(ids.count) configured source(s) are missing from the catalog (\(ids.joined(separator: ", "))). The source list may be corrupted; remove or restore the affected sources."
            case .unsavedEdit:
                return "Can't apply — your latest edit couldn't be saved to disk. Resolve the save error and try again."
            }
        }
    }

    // MARK: Apply

    private func resolveFragments(for profile: Profile) -> [NamedContent] {
        profile.fragmentIDs.compactMap { fid in
            fragments.first { $0.id == fid }.map { NamedContent(name: $0.name, content: $0.content) }
        }
    }

    private func resolveSources(for profile: Profile)
        -> (resolved: [SourceLayer], missingRecords: [UUID]) {
        guard let catalog else { return ([], profile.sourceIDs) }
        var resolved: [SourceLayer] = []
        var missingRecords: [UUID] = []
        for sid in profile.sourceIDs {
            if let s = catalog.source(for: sid) {
                resolved.append(SourceLayer(name: s.name, cacheURL: catalog.cacheURL(for: sid), expectedHash: s.contentHash, domainCount: s.domainCount))
            } else {
                missingRecords.append(sid)
            }
        }
        return (resolved, missingRecords)
    }

    private func stagedTempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("hostsswitchr-merged-\(UUID().uuidString).hosts")
    }

    private struct ApplyOutcome { let sourceGen: Int; let fragGen: Int }
    // Pre-compose generations let callers detect a mid-apply change before clearing the stale badge.
    private func composeAndApply(_ profile: Profile) async throws -> ApplyOutcome {
        // Fail-closed: a failed flush leaves pendingSave set so the guards below abort the apply.
        flushPendingSave()
        if let pending = pendingSave, pending.id == profile.id { throw ApplyError.unsavedEdit }
        if let pendingF = pendingFragmentSave, profile.fragmentIDs.contains(pendingF.id) { throw ApplyError.unsavedEdit }
        let sourceGen = sourceCacheGeneration, fragGen = fragmentGeneration
        let local = profile.content
        let frags = resolveFragments(for: profile)
        let (resolved, missingRecords) = resolveSources(for: profile)
        if !missingRecords.isEmpty {
            throw ApplyError.missingSourceRecords(missingRecords.map { String($0.uuidString.prefix(8)) })
        }
        let missing = resolved.filter { !FileManager.default.fileExists(atPath: $0.cacheURL.path) }
        if !missing.isEmpty { throw ApplyError.missingSourceCaches(missing.map(\.name)) }
        let temp = stagedTempURL()
        defer { try? FileManager.default.removeItem(at: temp) }
        let composer = self.composer
        _ = try await Task.detached(priority: .userInitiated) {
            try composer.compose(localContent: local, localFragments: frags, sources: resolved, to: temp)
        }.value
        try applier.apply(stagedURL: temp)
        return ApplyOutcome(sourceGen: sourceGen, fragGen: fragGen)
    }

    // Not current if the profile changed/deleted mid-compose, so its stale badge must remain.
    private func snapshotIsCurrent(_ snapshot: Profile) -> Bool {
        profiles.first(where: { $0.id == snapshot.id })
            .map { $0.content == snapshot.content && $0.sourceIDs == snapshot.sourceIDs && $0.fragmentIDs == snapshot.fragmentIDs } ?? false
    }

    func applyAsync(_ id: UUID) async {
        if isApplying { return }; isApplying = true; defer { isApplying = false }
        lastError = nil
        guard let store, let p = profiles.first(where: { $0.id == id }) else { return }
        let outcome: ApplyOutcome
        do { outcome = try await composeAndApply(p) } catch {
            lastError = "Apply failed: \(error.localizedDescription)"; return
        }
        // Commit point: a later metadata-save failure must not be reported as an apply failure.
        store.setActive(id)
        if snapshotIsCurrent(p) && sourceCacheGeneration == outcome.sourceGen && fragmentGeneration == outcome.fragGen { staleProfileIDs.remove(id) }

        do { try store.save() } catch {
            lastError = "Applied \(p.name), but saving active-profile state failed: \(error.localizedDescription). It may not persist across relaunch."
        }
        refresh()
        notify("Hosts Switchr", "Applied \(p.name)")
    }

    // MARK: Refresh + auto-reapply

    private(set) var isApplying = false
    private var isRefreshing = false
    // Bumped when a source cache changes; an apply captures it pre-compose and refuses to clear the stale badge if it moved mid-apply.
    private var sourceCacheGeneration = 0
    private var fragmentGeneration = 0   // same guard for fragment-content edits

    func refreshAllSources() async {
        guard let catalog, !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        let refresher = SourceRefresher(fetcher: fetcher)
        let outcomes = await refresher.refreshAll(in: catalog)
        prefs.lastRefreshAt = Date()
        refresh()
        await handleRefreshOutcomes(outcomes)
    }

    func refreshSource(_ id: UUID) async {
        guard let catalog, !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        let outcome = await SourceRefresher(fetcher: fetcher).refresh(id, in: catalog)
        refresh()
        await handleRefreshOutcomes([outcome])
    }

    private func handleRefreshOutcomes(_ outcomes: [RefreshOutcome]) async {
        let changedIDs = Set(outcomes.filter { $0.changed }.map(\.sourceID))

        if !changedIDs.isEmpty {
            sourceCacheGeneration += 1   // a cache moved; any in-flight apply must not clear stale
            for p in profiles where !p.sourceIDs.isEmpty && !changedIDs.isDisjoint(with: Set(p.sourceIDs)) {
                staleProfileIDs.insert(p.id)
            }
            if let activeID = activeProfileID,
               let active = profiles.first(where: { $0.id == activeID }),
               !changedIDs.isDisjoint(with: Set(active.sourceIDs)),
               prefs.autoReapply,
               !isApplying {
                isApplying = true
                defer { isApplying = false }
                // Re-check: the user may have switched the active profile while we refreshed.
                if activeProfileID == activeID {
                    do {
                        let outcome = try await composeAndApply(active)
                        if snapshotIsCurrent(active) && sourceCacheGeneration == outcome.sourceGen && fragmentGeneration == outcome.fragGen { staleProfileIDs.remove(activeID) }
                        notify("Hosts Switchr", "Updated \(active.name) from refreshed blocklists")
                    } catch {
                        lastError = "Auto re-apply failed (\(error.localizedDescription)). Re-apply when ready."
                    }
                }
            }
        }

        // Invariant: an enabled source with no cache file marks dependent profiles stale, so no apply silently omits a blocklist whose cache was deleted externally.
        if let catalog {
            for p in profiles where p.sourceIDs.contains(where: { sid in
                catalog.source(for: sid) != nil
                    && !FileManager.default.fileExists(atPath: catalog.cacheURL(for: sid).path)
            }) {
                staleProfileIDs.insert(p.id)
            }
        }
    }

    private func run(_ body: (ProfileStore) throws -> Void) {
        guard let store else { return }
        do { try body(store); refresh() }
        catch ProfileError.protectedProfile { lastError = "That profile is protected and can’t be deleted." }
        catch { lastError = "Something went wrong saving that change. Please try again." }
    }

}
