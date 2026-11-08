// Copyright (c) 2026 Async Digital Ltd
// SPDX-License-Identifier: MIT

import Testing

/// Waits for `condition` to hold, giving the prefetcher's tasks and the
/// source's fetches time to run in between checks.
///
/// Records an issue if the condition still does not hold after `limit`.
/// The limit is a backstop for a hang, not a timing assumption: every
/// condition here holds within a few scheduler turns.
@MainActor
func eventually(
    _ condition: @MainActor () -> Bool,
    limit: Duration = .seconds(2),
    sourceLocation: SourceLocation = #_sourceLocation
) async {
    let clock = ContinuousClock()
    let deadline = clock.now + limit
    while !condition() {
        guard clock.now < deadline else {
            Issue.record("Condition did not hold within \(limit).", sourceLocation: sourceLocation)
            return
        }
        try? await Task.sleep(for: .milliseconds(1))
    }
}
