import Darwin
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

    static let maxStreams = 32

    private struct Stream {
        let connection: NWConnection
        var activity: UInt64
    }

    private struct Report {
        var listeners: [NWListener] = []
        var sockets: [DispatchSourceRead] = []
        var connections: [NWConnection] = []
        var state: WildcardServiceState?
        var generation: UInt64 = 0
        var handler: StateHandler?

        func cancel() {
            listeners.forEach { $0.cancel() }
            sockets.forEach { $0.cancel() }
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
    private static let streamLifetime: DispatchTimeInterval = .seconds(10)
    private static let retryDelays = [1, 2, 5, 30]
    private static let datagramsPerWakeup = 64

    private let queue: DispatchQueue
    private let lock = NSLock()
    private var matcher = WildcardMatcher(.empty)
    private var desiredPort: UInt16?
    private var boundPort: UInt16?
    private var datagramSource: DispatchSourceRead?
    private var streamListener: NWListener?
    private var streamReady = false
    private var closing = 0
    private var wantsStart = false
    private var attempt: UInt64 = 0
    private var failures = 0
    private var retryArmed = false
    private var state: WildcardServiceState = .stopped
    private var generation: UInt64 = 0
    private var deliveredGeneration: UInt64 = 0
    private var onState: StateHandler?
    private var streams: [UInt64: Stream] = [:]
    private var nextStreamID: UInt64 = 0

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
            if datagramSource != nil, boundPort == port { return [settleLocked(state)] }
            let teardown = takeAllLocked()
            state = .stopped
            desiredPort = port
            failures = 0
            wantsStart = true
            return [teardown] + [startLocked()].compactMap { $0 }
        }
        reports.forEach { $0.run(for: self) }
    }

    func stop() {
        let report = lock.withLock {
            let teardown = takeAllLocked()
            desiredPort = nil
            wantsStart = false
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

    private func failLocked(_ newState: WildcardServiceState, _ teardown: Report = Report()) -> Report {
        armRetryLocked()
        return settleLocked(newState, teardown)
    }

    private func armRetryLocked() {
        guard desiredPort != nil, !retryArmed else { return }
        retryArmed = true
        let delay = Self.retryDelays[min(failures, Self.retryDelays.count - 1)]
        failures += 1
        let token = attempt
        queue.asyncAfter(deadline: .now() + .seconds(delay)) { [weak self] in
            self?.retry(token)
        }
    }

    private func retry(_ token: UInt64) {
        let reports: [Report] = lock.withLock {
            guard token == attempt else { return [] }
            retryArmed = false
            guard desiredPort != nil, !streamReady else { return [] }
            let teardown = takeAllLocked()
            wantsStart = true
            return [teardown] + [startLocked()].compactMap { $0 }
        }
        reports.forEach { $0.run(for: self) }
    }

    private func startLocked() -> Report? {
        guard wantsStart, closing == 0, let port = desiredPort else { return nil }
        wantsStart = false
        let fd: Int32
        let listener: NWListener
        do {
            fd = try Self.bindDatagramSocket(port: port)
        } catch {
            return failLocked(Self.state(for: error))
        }
        do {
            listener = try Self.makeStreamListener(port: port)
        } catch {
            close(fd)
            return failLocked(Self.state(for: error))
        }
        boundPort = port
        streamListener = listener
        datagramSource = makeDatagramSource(fd)
        configure(listener)
        listener.start(queue: queue)
        return nil
    }

    private static func bindDatagramSocket(port: UInt16) throws -> Int32 {
        guard port != 0 else { throw NWError.posix(.EINVAL) }
        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else { throw NWError.posix(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        address.sin_addr.s_addr = UInt32(0x7F00_0001).bigEndian
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0, fcntl(fd, F_SETFD, FD_CLOEXEC) == 0, fcntl(fd, F_SETFL, O_NONBLOCK) == 0 else {
            let code = POSIXErrorCode(rawValue: errno) ?? .EIO
            close(fd)
            throw NWError.posix(code)
        }
        return fd
    }

    private static func makeStreamListener(port: UInt16) throws -> NWListener {
        guard let endpointPort = NWEndpoint.Port(rawValue: port) else { throw NWError.posix(.EINVAL) }
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        parameters.requiredInterfaceType = .loopback
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: endpointPort)
        return try NWListener(using: parameters)
    }

    private static func state(for error: Error) -> WildcardServiceState {
        if case .posix(.EADDRINUSE)? = error as? NWError { return .portInUse }
        return .failed(error.localizedDescription)
    }

    private func makeDatagramSource(_ fd: Int32) -> DispatchSourceRead {
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in
            self?.drainDatagrams(fd)
        }
        source.setCancelHandler { [weak self] in
            close(fd)
            self?.closed()
        }
        source.resume()
        return source
    }

    private func drainDatagrams(_ fd: Int32) {
        let matcher = currentMatcher
        var buffer = [UInt8](repeating: 0, count: 65_536)
        for _ in 0..<Self.datagramsPerWakeup {
            var peer = sockaddr_storage()
            var peerLength = socklen_t(MemoryLayout<sockaddr_storage>.size)
            let count = buffer.withUnsafeMutableBytes { bytes in
                withUnsafeMutablePointer(to: &peer) {
                    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                        recvfrom(fd, bytes.baseAddress, bytes.count, 0, $0, &peerLength)
                    }
                }
            }
            guard count >= 0 else { return }
            guard let reply = WildcardDNSResponder.response(to: Data(buffer[0..<count]), matcher: matcher) else {
                continue
            }
            _ = reply.withUnsafeBytes { bytes in
                withUnsafePointer(to: &peer) {
                    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                        sendto(fd, bytes.baseAddress, bytes.count, 0, $0, peerLength)
                    }
                }
            }
        }
    }

    private func configure(_ listener: NWListener) {
        let id = ObjectIdentifier(listener)
        listener.stateUpdateHandler = { [weak self] newState in
            self?.listener(id, changedTo: newState)
        }
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else {
                connection.cancel()
                return
            }
            accept(connection, from: id)
        }
    }

    private func listener(_ id: ObjectIdentifier, changedTo newState: NWListener.State) {
        if case .cancelled = newState {
            closed()
            return
        }
        let report: Report? = lock.withLock {
            guard streamListener.map(ObjectIdentifier.init) == id else { return nil }
            switch newState {
            case .ready:
                streamReady = true
                failures = 0
                return settleLocked(.ready)
            case .waiting(let error):
                return failLocked(Self.state(for: error))
            case .failed(let error):
                return failLocked(Self.state(for: error), takeAllLocked())
            default:
                return nil
            }
        }
        report?.run(for: self)
    }

    private func closed() {
        let report = lock.withLock {
            closing -= 1
            return startLocked()
        }
        report?.run(for: self)
    }

    // Closing handles are counted until they finish; rebinding before that fails with EADDRINUSE.
    private func takeAllLocked() -> Report {
        attempt += 1
        retryArmed = false
        var report = Report(connections: streams.values.map(\.connection))
        if let streamListener {
            report.listeners = [streamListener]
            closing += 1
        }
        if let datagramSource {
            report.sockets = [datagramSource]
            closing += 1
        }
        streamListener = nil
        datagramSource = nil
        streamReady = false
        boundPort = nil
        streams = [:]
        return report
    }

    private func accept(_ connection: NWConnection, from listener: ObjectIdentifier) {
        let accepted: UInt64? = lock.withLock {
            guard streamListener.map(ObjectIdentifier.init) == listener, streams.count < Self.maxStreams else {
                return nil
            }
            nextStreamID += 1
            streams[nextStreamID] = Stream(connection: connection, activity: 0)
            return nextStreamID
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
        queue.asyncAfter(deadline: .now() + Self.streamLifetime) { [weak self] in
            self?.end(id)
        }
        receiveStream(on: connection, id: id, buffer: Data())
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
            guard var tracked = streams[id] else { return nil }
            tracked.activity += 1
            streams[id] = tracked
            return tracked.activity
        }
        guard let activity else { return }
        queue.asyncAfter(deadline: .now() + Self.idleTimeout) { [weak self] in
            self?.expire(id, ifStillAt: activity)
        }
    }

    private func expire(_ id: UInt64, ifStillAt activity: UInt64) {
        let idle = lock.withLock {
            streams[id].flatMap { $0.activity == activity ? $0.connection : nil }
        }
        idle?.cancel()
    }

    private func end(_ id: UInt64) {
        lock.withLock { streams[id]?.connection }?.cancel()
    }

    private func forget(_ id: UInt64) {
        lock.withLock { _ = streams.removeValue(forKey: id) }
    }
}
