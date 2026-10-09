// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

import Foundation
import dnssd

public enum BonjourError: Error, Equatable {
    /// The service did not answer in time (gone, or the network blocks multicast).
    case timeout
    case failed(Int32)
}

/// Turns an announced service into the host name and port to connect to.
public enum BonjourResolver {
    /// `DiskStation.local` and 445 for an SMB server; the host has no trailing dot.
    public static func resolve(_ service: NetworkPlaces.Service, timeout: Duration = .seconds(5)) async throws
        -> (host: String, port: Int) {
        let request = ResolveRequest()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                request.start(service, timeout: timeout, continuation: continuation)
            }
        } onCancel: {
            request.finish(.failure(CancellationError()))
        }
    }
}

/// One DNSServiceResolve call; finishes exactly once (answer, error, timeout or cancel).
private final class ResolveRequest: @unchecked Sendable {
    private let lock = NSLock()
    private var ref: DNSServiceRef?
    private var continuation: CheckedContinuation<(host: String, port: Int), any Error>?
    private let queue = DispatchQueue(label: "BonjourResolver")

    func start(_ service: NetworkPlaces.Service, timeout: Duration,
               continuation: CheckedContinuation<(host: String, port: Int), any Error>) {
        lock.lock()
        self.continuation = continuation
        lock.unlock()
        var newRef: DNSServiceRef?
        let context = Unmanaged.passUnretained(self).toOpaque()
        let status = DNSServiceResolve(&newRef, 0, 0, service.name, service.kind.type, service.domain, { _, _, _, error, _, host, port, _, _, context in
            guard let context else { return }
            let request = Unmanaged<ResolveRequest>.fromOpaque(context).takeUnretainedValue()
            guard error == kDNSServiceErr_NoError, let host else {
                request.finish(.failure(BonjourError.failed(error)))
                return
            }
            var name = String(cString: host)
            if name.hasSuffix(".") { name.removeLast() }
            request.finish(.success((name, Int(UInt16(bigEndian: port)))))
        }, context)
        guard status == kDNSServiceErr_NoError, let newRef else {
            finish(.failure(BonjourError.failed(status)))
            return
        }
        lock.lock()
        ref = newRef
        lock.unlock()
        DNSServiceSetDispatchQueue(newRef, queue)
        let seconds = Double(timeout.components.seconds) + Double(timeout.components.attoseconds) / 1e18
        queue.asyncAfter(deadline: .now() + seconds) { [self] in finish(.failure(BonjourError.timeout)) }
    }

    func finish(_ result: Result<(host: String, port: Int), any Error>) {
        lock.lock()
        let continuation = continuation
        self.continuation = nil
        let ref = ref
        self.ref = nil
        lock.unlock()
        // Deallocating on the service's queue keeps the callback from running afterwards.
        if let ref {
            nonisolated(unsafe) let owned = ref
            queue.async { DNSServiceRefDeallocate(owned) }
        }
        continuation?.resume(with: result)
    }
}
