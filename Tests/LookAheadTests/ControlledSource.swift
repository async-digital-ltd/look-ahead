// Copyright (c) 2026 Async Digital Ltd
// SPDX-License-Identifier: MIT

import LookAhead
import Synchronization

/// A source whose fetches stay suspended until the test settles them, so a
/// test decides exactly when, and in what order, each load finishes.
///
/// It records every key it is asked for and every fetch that was cancelled.
/// When `honoursCancellation` is false, a cancelled fetch stays suspended
/// until settled, which is how a slow source that ignores cancellation
/// behaves.
final class ControlledSource: PrefetchSource {
    struct Failure: Error, Equatable {
        let key: String
    }

    private struct State {
        var requests: [String] = []
        var cancellations: [String] = []
        var pending: [(key: String, continuation: CheckedContinuation<String, any Error>)] = []
    }

    private let state = Mutex(State())
    private let honoursCancellation: Bool

    init(honoursCancellation: Bool = true) {
        self.honoursCancellation = honoursCancellation
    }

    var requests: [String] {
        state.withLock { $0.requests }
    }

    var cancellations: [String] {
        state.withLock { $0.cancellations }
    }

    var pendingKeys: [String] {
        state.withLock { $0.pending.map(\.key) }
    }

    func fetch(_ key: String) async throws -> String {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let cancelledAlready = state.withLock { state in
                    state.requests.append(key)
                    if honoursCancellation, Task.isCancelled {
                        state.cancellations.append(key)
                        return true
                    }
                    state.pending.append((key, continuation))
                    return false
                }
                if cancelledAlready {
                    continuation.resume(throwing: CancellationError())
                }
            }
        } onCancel: {
            let continuation = state.withLock { state -> CheckedContinuation<String, any Error>? in
                guard honoursCancellation,
                      let index = state.pending.firstIndex(where: { $0.key == key })
                else { return nil }
                state.cancellations.append(key)
                return state.pending.remove(at: index).continuation
            }
            continuation?.resume(throwing: CancellationError())
        }
    }

    /// Resumes the oldest pending fetch for `key` with `resource`.
    func succeed(_ key: String, with resource: String? = nil) {
        takeOldest(key).resume(returning: resource ?? "resource:\(key)")
    }

    /// Resumes the oldest pending fetch for `key` with `Failure(key:)`.
    func fail(_ key: String) {
        takeOldest(key).resume(throwing: Failure(key: key))
    }

    private func takeOldest(_ key: String) -> CheckedContinuation<String, any Error> {
        let continuation = state.withLock { state -> CheckedContinuation<String, any Error>? in
            guard let index = state.pending.firstIndex(where: { $0.key == key }) else { return nil }
            return state.pending.remove(at: index).continuation
        }
        guard let continuation else {
            preconditionFailure("No fetch for \(key) is pending.")
        }
        return continuation
    }
}
