// Copyright (c) 2026 Async Digital Ltd
// SPDX-License-Identifier: MIT

import Synchronization
import Testing

struct OutcomeTimedOut: Error {}

/// The result of `task`, or an `OutcomeTimedOut` error and a recorded issue
/// if it has not finished within `limit`.
///
/// Awaiting `task.value` directly cannot be interrupted: it ignores
/// cancellation, so a regression that leaves a load suspended would hang the
/// whole run, and a Swift Testing time limit does not end such a wait. This
/// helper races the task against a deadline instead and gives up on it.
@MainActor
func outcome<Success: Sendable>(
    of task: Task<Success, any Error>,
    limit: Duration = .seconds(2),
    sourceLocation: SourceLocation = #_sourceLocation
) async throws -> Success {
    typealias Waiter = CheckedContinuation<Result<Success, any Error>?, Never>
    let waiter = Mutex<Waiter?>(nil)
    let result = await withCheckedContinuation { (continuation: Waiter) in
        waiter.withLock { $0 = continuation }
        Task {
            let result = await task.result
            waiter.withLock { $0.take() }?.resume(returning: result)
        }
        Task {
            try? await Task.sleep(for: limit)
            waiter.withLock { $0.take() }?.resume(returning: nil)
        }
    }
    guard let result else {
        Issue.record("Task did not finish within \(limit).", sourceLocation: sourceLocation)
        throw OutcomeTimedOut()
    }
    return try result.get()
}
