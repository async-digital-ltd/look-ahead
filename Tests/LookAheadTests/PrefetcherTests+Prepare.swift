// Copyright (c) 2026 Async Digital Ltd
// SPDX-License-Identifier: MIT

import LookAhead
import Testing

extension PrefetcherTests {
    // MARK: - Prepare

    @Test
    func prepareTurnsTheResourceIntoTheValue() async throws {
        let window = try #require(PrefetchWindow(behind: 0, ahead: 0))
        let prefetcher = Prefetcher(source: source, window: window) { resource in
            resource.count
        }
        prefetcher.focus(on: 0, in: deck)
        await eventually { source.pendingKeys == ["a"] }

        source.succeed("a", with: "12345")

        #expect(try await outcome(of: Task { try await prefetcher.value(for: "a") }) == 5)
    }

    @Test
    func prepareRunsOnTheMainActor() async throws {
        let window = try #require(PrefetchWindow(behind: 0, ahead: 0))
        let prefetcher = Prefetcher(source: source, window: window) { _ in
            MainActor.assertIsolated()
            return true
        }
        let waiting = Task { try await prefetcher.value(for: "a") }
        await eventually { source.pendingKeys == ["a"] }
        source.succeed("a")

        #expect(try await outcome(of: waiting))
    }

    @Test
    func aThrowingPrepareReachesTheCallerAndLeavesTheKeyIdle() async throws {
        struct PrepareFailure: Error {}
        let window = try #require(PrefetchWindow(behind: 0, ahead: 0))
        let prefetcher = Prefetcher(source: source, window: window) { _ -> Int in
            throw PrepareFailure()
        }
        let waiting = Task { try await prefetcher.value(for: "a") }
        await eventually { source.pendingKeys == ["a"] }

        source.succeed("a")

        await #expect(throws: PrepareFailure.self) {
            try await outcome(of: waiting)
        }
        #expect(prefetcher.status(of: "a") == .idle)
    }

    @Test
    func prepareIsNotRunForAKeyThatLeftTheWindow() async throws {
        let slowSource = ControlledSource(honoursCancellation: false)
        let window = try #require(PrefetchWindow(behind: 0, ahead: 0))
        var prepared: [String] = []
        let prefetcher = Prefetcher(source: slowSource, window: window) { resource in
            prepared.append(resource)
            return resource
        }
        prefetcher.focus(on: 0, in: deck)
        await eventually { slowSource.pendingKeys == ["a"] }
        prefetcher.focus(on: 3, in: deck)

        slowSource.succeed("a")
        await eventually { slowSource.pendingKeys == ["d"] }
        try await Task.sleep(for: .milliseconds(20))

        #expect(prepared.isEmpty)
        #expect(prefetcher.status(of: "a") == .idle)
    }

    // MARK: - Stale loads

    @Test
    func aStaleLoadCannotOverwriteANewerOne() async throws {
        let slowSource = ControlledSource(honoursCancellation: false)
        let prefetcher = try makePrefetcher(source: slowSource, behind: 0, ahead: 0)
        prefetcher.focus(on: 0, in: deck)
        await eventually { slowSource.pendingKeys == ["a"] }

        // "a" leaves and comes back while its first fetch is still running.
        prefetcher.focus(on: 3, in: deck)
        prefetcher.focus(on: 0, in: deck)
        await eventually { slowSource.pendingKeys.filter { $0 == "a" }.count == 2 }

        slowSource.succeed("a", with: "stale")
        try await Task.sleep(for: .milliseconds(20))
        #expect(prefetcher.status(of: "a") == .loading)

        slowSource.succeed("a", with: "fresh")
        await eventually { prefetcher.status(of: "a") == .ready }
        #expect(prefetcher.readyValue(for: "a") == "fresh")
    }

    @Test
    func aStaleFailureCannotClearANewerLoad() async throws {
        let slowSource = ControlledSource(honoursCancellation: false)
        let prefetcher = try makePrefetcher(source: slowSource, behind: 0, ahead: 0)
        prefetcher.focus(on: 0, in: deck)
        await eventually { slowSource.pendingKeys == ["a"] }
        prefetcher.focus(on: 3, in: deck)
        prefetcher.focus(on: 0, in: deck)
        await eventually { slowSource.pendingKeys.filter { $0 == "a" }.count == 2 }

        slowSource.fail("a")
        try await Task.sleep(for: .milliseconds(20))

        #expect(prefetcher.status(of: "a") == .loading)
    }

    // MARK: - Lifetime

    @Test
    func releasingThePrefetcherCancelsItsLoads() async throws {
        var prefetcher: Prefetcher<ControlledSource, String>? = try makePrefetcher()
        prefetcher?.focus(on: 0, in: deck)
        await eventually { source.pendingKeys.count == 3 }

        prefetcher = nil

        await eventually { source.pendingKeys.isEmpty }
        #expect(Set(source.cancellations) == ["a", "b", "c"])
    }
}
