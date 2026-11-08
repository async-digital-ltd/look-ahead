// Copyright (c) 2026 Async Digital Ltd
// SPDX-License-Identifier: MIT

/// Keeps the resources around a focused position in an ordered list loaded
/// and ready, and lets the rest go.
///
/// Call `focus(on:in:)` whenever the focused position changes, for example
/// when the user moves to another card. The prefetcher starts loading every
/// key inside the window that is not already loading or ready, nearest first,
/// cancels loads for keys that have left the window, and drops ready values
/// for them. Then read a value with `value(for:)`, which waits for a load in
/// progress rather than starting a second one.
///
/// Loading has two stages. The source's `fetch(_:)` runs off the main actor
/// and returns a `Sendable` resource. `prepare` then runs on the main actor
/// and turns it into the value you use, which need not be `Sendable`. For
/// audio, the source returns a file URL and `prepare` builds the player and
/// calls `prepareToPlay()`, so playback starts without delay.
///
/// Keys, not positions, identify resources. A list can be reordered or
/// shuffled between calls, and a key that appears twice is loaded once.
@MainActor
public final class Prefetcher<Source: PrefetchSource, Value> {
    public typealias Key = Source.Key

    /// Where a key stands. A key that is not loading or ready is `idle`,
    /// whether it was never requested, has left the window, or failed.
    public enum Status: Hashable, Sendable {
        case idle
        case loading
        case ready
    }

    private enum Entry {
        // The ticket tells a load apart from an earlier one for the same key,
        // so a load that finishes after its key was dropped and requested
        // again cannot overwrite the newer entry.
        case loading(ticket: Int, task: Task<Void, any Error>)
        case ready(Value)
    }

    public let window: PrefetchWindow
    private let source: Source
    private let prepare: @MainActor (Source.Resource) throws -> Value
    private var entries: [Key: Entry] = [:]
    private var nextTicket = 0

    public init(
        source: Source,
        window: PrefetchWindow = .standard,
        prepare: @escaping @MainActor (Source.Resource) throws -> Value
    ) {
        self.source = source
        self.window = window
        self.prepare = prepare
    }

    isolated deinit {
        for entry in entries.values {
            if case .loading(_, let task) = entry {
                task.cancel()
            }
        }
    }

    /// Moves the window to `position` in `keys`: loads what has come into
    /// it and lets go of what has left it.
    ///
    /// A position near either end gives a smaller window, and a position
    /// outside `keys` gives an empty one, which lets go of everything.
    public func focus(on position: Int, in keys: [Key]) {
        var wanted: [Key] = []
        var wantedSet: Set<Key> = []
        for index in window.positions(around: position, within: keys.indices)
        where wantedSet.insert(keys[index]).inserted {
            wanted.append(keys[index])
        }

        for key in Array(entries.keys) where !wantedSet.contains(key) {
            drop(key)
        }
        for key in wanted where entries[key] == nil {
            startLoading(key)
        }
    }

    /// The value for `key`, waiting for it to load if needed.
    ///
    /// A key that is loading is awaited, not fetched again. A key that is
    /// idle starts loading, even outside the window; the next `focus(on:in:)`
    /// lets it go again if it is still outside.
    ///
    /// - Throws: The error from the source or from `prepare`, or
    ///   `CancellationError` when the key leaves the window before its value
    ///   is ready.
    public func value(for key: Key) async throws -> Value {
        switch entries[key] {
        case .ready(let value):
            return value
        case .loading(_, let task):
            try await task.value
        case nil:
            try await startLoading(key).value
        }
        guard case .ready(let value) = entries[key] else {
            throw CancellationError()
        }
        return value
    }

    /// The value for `key` if it is ready now, without waiting or loading.
    public func readyValue(for key: Key) -> Value? {
        guard case .ready(let value) = entries[key] else { return nil }
        return value
    }

    public func status(of key: Key) -> Status {
        switch entries[key] {
        case nil: .idle
        case .loading: .loading
        case .ready: .ready
        }
    }

    @discardableResult
    private func startLoading(_ key: Key) -> Task<Void, any Error> {
        let ticket = nextTicket
        nextTicket += 1
        let task = Task { [weak self, source] in
            do {
                let resource = try await source.fetch(key)
                guard let self else { throw CancellationError() }
                try self.finish(key, ticket: ticket, with: resource)
            } catch {
                self?.discard(key, ticket: ticket)
                throw error
            }
        }
        entries[key] = .loading(ticket: ticket, task: task)
        return task
    }

    private func finish(_ key: Key, ticket: Int, with resource: Source.Resource) throws {
        guard isCurrent(ticket, for: key) else { throw CancellationError() }
        entries[key] = .ready(try prepare(resource))
    }

    private func discard(_ key: Key, ticket: Int) {
        if isCurrent(ticket, for: key) {
            entries[key] = nil
        }
    }

    private func isCurrent(_ ticket: Int, for key: Key) -> Bool {
        guard case .loading(let current, _) = entries[key] else { return false }
        return current == ticket
    }

    private func drop(_ key: Key) {
        if case .loading(_, let task) = entries[key] {
            task.cancel()
        }
        entries[key] = nil
    }
}

extension Prefetcher where Value == Source.Resource {
    /// A prefetcher whose values are the source's resources, unchanged.
    public convenience init(source: Source, window: PrefetchWindow = .standard) {
        self.init(source: source, window: window) { $0 }
    }
}
