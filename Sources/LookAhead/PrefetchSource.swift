// Copyright (c) 2026 Async Digital Ltd
// SPDX-License-Identifier: MIT

/// Supplies the resource for a key, wherever it lives: an app bundle, an
/// Apple-hosted asset pack, a CloudKit record, a URL session, a test double.
///
/// The prefetcher calls `fetch(_:)` from the main actor, and because the
/// requirement is a nonisolated `async` function the work runs off the main
/// actor. Return something cheap to move between threads (a file URL, `Data`)
/// and leave main-actor work, such as building an audio player, to the
/// prefetcher's `prepare` step.
///
/// Implementations should check for cancellation. The prefetcher cancels a
/// fetch as soon as its key leaves the window, and ignores any result that
/// arrives after that.
public protocol PrefetchSource<Key, Resource>: Sendable {
    associatedtype Key: Hashable & Sendable
    associatedtype Resource: Sendable

    func fetch(_ key: Key) async throws -> Resource
}
