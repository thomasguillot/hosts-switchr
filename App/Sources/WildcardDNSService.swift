import Foundation
import HostsKit
import Network

enum WildcardServiceState: Equatable, Sendable {
    case stopped
    case ready
    case portInUse
    case failed(String)
}

final class WildcardDNSService: @unchecked Sendable {
    typealias StateHandler = @MainActor @Sendable (WildcardServiceState) -> Void

    private struct Tracked {
        let connection: NWConnection
        var activity: UInt64
    }

    private struct Report {
        var listeners: [NWListener] = []
        var connections: [NWConnection] = []
        var state: WildcardServiceState?
        var generation: UInt64 = 0
        var handler: StateHandler?

        func cancel() {
            listeners.forEach { $0.cancel() }
            connections.forEach { $0.cancel() }
        }

        func run(for service: WildcardDNSService) {
            cancel()
            guard let state, let handler else { return }
            let generation = generation
            Task { @MainActor [weak service] in
                guard service?.claimDelivery(generation) == true else { return }
                handler(state)
            }
        }
    }

    private static let idleTimeout: DispatchTimeInterval = .seconds(10)

    private let queue: DispatchQueue
    private let lock = NSLock()
    private var matcher = WildcardMatcher(.empty)
    private var udpListener: NWListener?
    private var tcpListener: NWListener?
    private var readyListeners: Set<ObjectIdentifier> = []
    private var closingListeners: [ObjectIdentifier: NWListener] = [:]
    private var port: UInt16?
    private var pendingPort: UInt16?
    private var state: WildcardServiceState = .stopped
    private var generation: UInt64 = 0
    private var deliveredGeneration: UInt64 = 0
    private var onState: StateHandler?
    private var connections: [UInt64: Tracked] = [:]
    private var nextConnectionID: UInt64 = 0

    init(queue: DispatchQueue = DispatchQueue(label: "com.hostsswitchr.wildcard-dns")) {
        self.queue = queue
    }

    deinit {
        takeAllLocked().cancel()
    }

    func serve(_ set: WildcardSet, port: UInt16, onState: @escaping StateHandler) {
        guard !set.isEmpty else {
            lock.withLock { self.onState = onState }
            stop()
            return
        }
        let matcher = WildcardMatcher(set)
        let reports: [Report] = lock.withLock {
            self.matcher = matcher
            self.onState = onState
            if udpListener != nil, self.port == port { return [settleLocked(state)] }
            let teardown = takeAllLocked()
            state = .stopped
            pendingPort = port
            return [teardown] + [startPendingLocked()].compactMap { $0 }
        }
        reports.forEach { $0.run(for: self) }
    }

    func stop() {
        let report = lock.withLock {
            let teardown = takeAllLocked()
            pendingPort = nil
            matcher = WildcardMatcher(.empty)
            return settleLocked(.stopped, teardown)
        }
        report.run(for: self)
    }

    private func settleLocked(_ newState: WildcardServiceState, _ teardown: Report = Report()) -> Report {
        var report = teardown
        state = newState
        generation += 1
        report.state = newState
        report.generation = generation
        report.handler = onState
        return report
    }

    // Deliveries hop to the main actor after the lock is released, so one decided earlier can arrive later.
    private func claimDelivery(_ generation: UInt64) -> Bool {
        lock.withLock {
            guard generation > deliveredGeneration else { return false }
            deliveredGeneration = generation
            return true
        }
    }

    private func startPendingLocked() -> Report? {
        guard closingListeners.isEmpty, let port = pendingPort else { return nil }
        pendingPort = nil
        let udp: NWListener
        let tcp: NWListener
        do {
            udp = try Self.listener(.udp, port: port)
            let tcpParameters = NWParameters.tcp
            tcpParameters.allowLocalEndpointReuse = true
            tcp = try Self.listener(tcpParameters, port: port)
        } catch {
            return settleLocked(.failed(error.localizedDescription))
        }
        udpListener = udp
        tcpListener = tcp
        self.port = port
        configure(udp, datagram: true)
        configure(tcp, datagram: false)
        udp.start(queue: queue)
        tcp.start(queue: queue)
        return nil
    }

    private static func listener(_ parameters: NWParameters, port: UInt16) throws -> NWListener {
        guard port != 0, let endpointPort = NWEndpoint.Port(rawValue: port) else {
            throw NWError.posix(.EINVAL)
        }
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: endpointPort)
        return try NWListener(using: parameters)
    }

    private func configure(_ listener: NWListener, datagram: Bool) {
        let id = ObjectIdentifier(listener)
        listener.stateUpdateHandler = { [weak self] newState in
            self?.listener(id, changedTo: newState)
        }
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else {
                connection.cancel()
                return
            }
            accept(connection, from: id, datagram: datagram)
        }
    }

    private func listener(_ id: ObjectIdentifier, changedTo newState: NWListener.State) {
        let report: Report? = lock.withLock {
            if case .cancelled = newState {
                closingListeners[id] = nil
                return startPendingLocked()
            }
            let current = [udpListener, tcpListener].compactMap { $0 }.map(ObjectIdentifier.init)
            guard current.contains(id) else { return nil }
            switch newState {
            case .ready:
                readyListeners.insert(id)
                guard readyListeners.count == 2 else { return nil }
                return settleLocked(.ready)
            case .failed(let error), .waiting(let error):
                return settleLocked(Self.state(for: error), takeAllLocked())
            default:
                return nil
            }
        }
        report?.run(for: self)
    }

    private static func state(for error: NWError) -> WildcardServiceState {
        if case .posix(.EADDRINUSE) = error { return .portInUse }
        return .failed(error.localizedDescription)
    }

    // Closing listeners are kept until they report .cancelled; rebinding before that fails with EADDRINUSE.
    private func takeAllLocked() -> Report {
        let listeners = [udpListener, tcpListener].compactMap { $0 }
        for listener in listeners { closingListeners[ObjectIdentifier(listener)] = listener }
        let report = Report(listeners: listeners, connections: connections.values.map(\.connection))
        udpListener = nil
        tcpListener = nil
        readyListeners = []
        port = nil
        connections = [:]
        return report
    }

    private func accept(_ connection: NWConnection, from listener: ObjectIdentifier, datagram: Bool) {
        let accepted: UInt64? = lock.withLock {
            let current = datagram ? udpListener : tcpListener
            guard current.map(ObjectIdentifier.init) == listener else { return nil }
            nextConnectionID += 1
            connections[nextConnectionID] = Tracked(connection: connection, activity: 0)
            return nextConnectionID
        }
        guard let id = accepted else {
            connection.cancel()
            return
        }
        connection.stateUpdateHandler = { [weak self] newState in
            switch newState {
            case .cancelled:
                self?.forget(id)
            case .failed, .waiting:
                connection.cancel()
            default:
                break
            }
        }
        connection.start(queue: queue)
        touch(id)
        if datagram {
            receiveDatagram(on: connection, id: id)
        } else {
            receiveStream(on: connection, id: id, buffer: Data())
        }
    }

    private func receiveDatagram(on connection: NWConnection, id: UInt64) {
        connection.receiveMessage { [weak self] content, _, _, error in
            guard let self, error == nil else {
                connection.cancel()
                return
            }
            if let content, let reply = WildcardDNSResponder.response(to: content, matcher: currentMatcher) {
                connection.send(content: reply, completion: .idempotent)
            }
            touch(id)
            receiveDatagram(on: connection, id: id)
        }
    }

    private func receiveStream(on connection: NWConnection, id: UInt64, buffer: Data) {
        connection.receive(
            minimumIncompleteLength: 1, maximumLength: 65_536
        ) { [weak self] content, _, isComplete, error in
            guard let self, error == nil else {
                connection.cancel()
                return
            }
            var buffer = buffer
            if let content { buffer.append(content) }
            let matcher = currentMatcher
            var output = Data()
            for query in DNSFraming.split(&buffer) {
                if let reply = WildcardDNSResponder.response(to: query, matcher: matcher) {
                    output.append(DNSFraming.frame(reply))
                }
            }
            if isComplete {
                connection.send(
                    content: output.isEmpty ? nil : output, contentContext: .finalMessage, isComplete: true,
                    completion: .contentProcessed { _ in connection.cancel() })
                return
            }
            touch(id)
            guard !output.isEmpty else {
                receiveStream(on: connection, id: id, buffer: buffer)
                return
            }
            let remainder = buffer
            connection.send(
                content: output,
                completion: .contentProcessed { [weak self] error in
                    guard let self, error == nil else {
                        connection.cancel()
                        return
                    }
                    receiveStream(on: connection, id: id, buffer: remainder)
                })
        }
    }

    private var currentMatcher: WildcardMatcher {
        lock.withLock { matcher }
    }

    private func touch(_ id: UInt64) {
        let activity: UInt64? = lock.withLock {
            guard var tracked = connections[id] else { return nil }
            tracked.activity += 1
            connections[id] = tracked
            return tracked.activity
        }
        guard let activity else { return }
        queue.asyncAfter(deadline: .now() + Self.idleTimeout) { [weak self] in
            self?.expire(id, ifStillAt: activity)
        }
    }

    private func expire(_ id: UInt64, ifStillAt activity: UInt64) {
        let idle = lock.withLock {
            connections[id].flatMap { $0.activity == activity ? $0.connection : nil }
        }
        idle?.cancel()
    }

    private func forget(_ id: UInt64) {
        lock.withLock { _ = connections.removeValue(forKey: id) }
    }
}
