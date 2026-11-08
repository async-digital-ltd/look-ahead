// Copyright (c) 2026 Async Digital Ltd
// SPDX-License-Identifier: MIT

import LookAhead
import Testing

@MainActor
struct PrefetcherTests {
    let deck = ["a", "b", "c", "d", "e", "f"]
    let source = ControlledSource()

    func makePrefetcher(
        source: ControlledSource? = nil,
        behind: Int = 1,
        ahead: Int = 2
    ) throws -> Prefetcher<ControlledSource, String> {
        let window = try #require(PrefetchWindow(behind: behind, ahead: ahead))
        return Prefetcher(source: source ?? self.source, window: window)
    }

    // MARK: - Focus

    @Test
    func focusLoadsEveryKeyInTheWindow() async throws {
        let prefetcher = try makePrefetcher()
        prefetcher.focus(on: 2, in: deck)

        await eventually { source.pendingKeys.count == 4 }
        #expect(Set(source.requests) == ["b", "c", "d", "e"])
        for key in ["b", "c", "d", "e"] {
            #expect(prefetcher.status(of: key) == .loading)
        }
        for key in ["a", "f"] {
            #expect(prefetcher.status(of: key) == .idle)
        }
    }

    @Test
    func loadedKeysBecomeReady() async throws {
        let prefetcher = try makePrefetcher(behind: 0, ahead: 0)
        prefetcher.focus(on: 0, in: deck)
        await eventually { source.pendingKeys == ["a"] }

        source.succeed("a")
        await eventually { prefetcher.status(of: "a") == .ready }
        #expect(prefetcher.readyValue(for: "a") == "resource:a")
    }

    @Test
    func focusingTwiceOnTheSamePositionFetchesEachKeyOnce() async throws {
        let prefetcher = try makePrefetcher()
        prefetcher.focus(on: 2, in: deck)
        prefetcher.focus(on: 2, in: deck)
        await eventually { source.pendingKeys.count == 4 }

        prefetcher.focus(on: 2, in: deck)
        try await Task.sleep(for: .milliseconds(20))
        #expect(source.requests.count == 4)
    }

    @Test
    func steppingForwardFetchesOnlyTheNewKey() async throws {
        let prefetcher = try makePrefetcher()
        prefetcher.focus(on: 1, in: deck)
        await eventually { source.pendingKeys.count == 4 }
        for key in ["a", "b", "c", "d"] {
            source.succeed(key)
        }
        await eventually { prefetcher.status(of: "d") == .ready }

        prefetcher.focus(on: 2, in: deck)
        await eventually { source.pendingKeys == ["e"] }
        #expect(source.requests.count == 5)
        for key in ["b", "c", "d"] {
            #expect(prefetcher.status(of: key) == .ready)
        }
    }

    @Test
    func keysLeavingTheWindowAreCancelledOrDropped() async throws {
        let prefetcher = try makePrefetcher(behind: 0, ahead: 1)
        prefetcher.focus(on: 0, in: deck)
        await eventually { source.pendingKeys.count == 2 }
        source.succeed("a")
        await eventually { prefetcher.status(of: "a") == .ready }

        // "a" is ready and "b" still loading; both leave the window.
        prefetcher.focus(on: 4, in: deck)

        #expect(prefetcher.status(of: "a") == .idle)
        #expect(prefetcher.readyValue(for: "a") == nil)
        #expect(prefetcher.status(of: "b") == .idle)
        await eventually { source.cancellations == ["b"] }
        await eventually { Set(source.pendingKeys) == ["e", "f"] }
    }

    @Test
    func aKeyThatReentersIsFetchedAgain() async throws {
        let prefetcher = try makePrefetcher(behind: 0, ahead: 0)
        prefetcher.focus(on: 0, in: deck)
        await eventually { source.pendingKeys == ["a"] }
        source.succeed("a")
        await eventually { prefetcher.status(of: "a") == .ready }

        prefetcher.focus(on: 3, in: deck)
        prefetcher.focus(on: 0, in: deck)

        #expect(prefetcher.status(of: "a") == .loading)
        await eventually { source.requests.filter { $0 == "a" }.count == 2 }
    }

    @Test
    func aDuplicatedKeyIsFetchedOnce() async throws {
        let prefetcher = try makePrefetcher(behind: 1, ahead: 2)
        prefetcher.focus(on: 1, in: ["x", "y", "x", "y"])

        await eventually { source.pendingKeys.count == 2 }
        try await Task.sleep(for: .milliseconds(20))
        #expect(source.requests.sorted() == ["x", "y"])
    }

    @Test(arguments: [-1, 6, 100])
    func focusOutsideTheListLetsGoOfEverything(position: Int) async throws {
        let prefetcher = try makePrefetcher()
        prefetcher.focus(on: 2, in: deck)
        await eventually { source.pendingKeys.count == 4 }

        prefetcher.focus(on: position, in: deck)

        await eventually { source.pendingKeys.isEmpty }
        for key in deck {
            #expect(prefetcher.status(of: key) == .idle)
        }
    }

    @Test
    func anEmptyListLetsGoOfEverything() async throws {
        let prefetcher = try makePrefetcher()
        prefetcher.focus(on: 0, in: deck)
        await eventually { source.pendingKeys.count == 3 }

        prefetcher.focus(on: 0, in: [])

        await eventually { source.pendingKeys.isEmpty }
        #expect(Set(source.cancellations) == ["a", "b", "c"])
    }

    @Test
    func aReorderedListKeepsWhatIsStillInTheWindow() async throws {
        let prefetcher = try makePrefetcher(behind: 0, ahead: 1)
        prefetcher.focus(on: 0, in: deck)
        await eventually { source.pendingKeys.count == 2 }
        source.succeed("a")
        source.succeed("b")
        await eventually { prefetcher.status(of: "b") == .ready }

        // Shuffled: "b" is still in the window at its new position.
        prefetcher.focus(on: 0, in: ["f", "b", "a", "c", "d", "e"])

        #expect(prefetcher.status(of: "b") == .ready)
        #expect(prefetcher.status(of: "a") == .idle)
        await eventually { source.pendingKeys == ["f"] }
    }

    // MARK: - Value

    @Test
    func valueOfAReadyKeyReturnsWithoutFetching() async throws {
        let prefetcher = try makePrefetcher(behind: 0, ahead: 0)
        prefetcher.focus(on: 0, in: deck)
        await eventually { source.pendingKeys == ["a"] }
        source.succeed("a")
        await eventually { prefetcher.status(of: "a") == .ready }

        let value = try await outcome(of: Task { try await prefetcher.value(for: "a") })

        #expect(value == "resource:a")
        #expect(source.requests == ["a"])
    }

    @Test
    func valueWaitsForALoadInProgressRatherThanFetchingAgain() async throws {
        let prefetcher = try makePrefetcher(behind: 0, ahead: 0)
        prefetcher.focus(on: 0, in: deck)
        await eventually { source.pendingKeys == ["a"] }

        let waiting = Task { try await prefetcher.value(for: "a") }
        try await Task.sleep(for: .milliseconds(20))
        source.succeed("a")

        #expect(try await outcome(of: waiting) == "resource:a")
        #expect(source.requests == ["a"])
    }

    @Test
    func severalCallersShareOneLoad() async throws {
        let prefetcher = try makePrefetcher(behind: 0, ahead: 0)
        let first = Task { try await prefetcher.value(for: "c") }
        let second = Task { try await prefetcher.value(for: "c") }
        await eventually { source.pendingKeys == ["c"] }

        source.succeed("c")

        #expect(try await outcome(of: first) == "resource:c")
        #expect(try await outcome(of: second) == "resource:c")
        #expect(source.requests == ["c"])
    }

    @Test
    func valueOfAnIdleKeyStartsLoadingIt() async throws {
        let prefetcher = try makePrefetcher()
        let waiting = Task { try await prefetcher.value(for: "z") }
        await eventually { source.pendingKeys == ["z"] }
        #expect(prefetcher.status(of: "z") == .loading)

        source.succeed("z")

        #expect(try await outcome(of: waiting) == "resource:z")
        #expect(prefetcher.status(of: "z") == .ready)
    }

    @Test
    func aKeyLoadedOutsideTheWindowIsLetGoAtTheNextFocus() async throws {
        let prefetcher = try makePrefetcher(behind: 0, ahead: 0)
        let waiting = Task { try await prefetcher.value(for: "f") }
        await eventually { source.pendingKeys == ["f"] }
        source.succeed("f")
        _ = try await outcome(of: waiting)

        prefetcher.focus(on: 0, in: deck)

        #expect(prefetcher.status(of: "f") == .idle)
    }

    @Test
    func valueThrowsCancellationWhenTheKeyLeavesTheWindow() async throws {
        let prefetcher = try makePrefetcher(behind: 0, ahead: 0)
        prefetcher.focus(on: 0, in: deck)
        await eventually { source.pendingKeys == ["a"] }
        let waiting = Task { try await prefetcher.value(for: "a") }
        try await Task.sleep(for: .milliseconds(20))

        prefetcher.focus(on: 3, in: deck)

        await #expect(throws: CancellationError.self) {
            try await outcome(of: waiting)
        }
    }

    // MARK: - Failure

    @Test
    func aFailedFetchReachesTheCallerAndLeavesTheKeyIdle() async throws {
        let prefetcher = try makePrefetcher(behind: 0, ahead: 0)
        prefetcher.focus(on: 0, in: deck)
        await eventually { source.pendingKeys == ["a"] }
        let waiting = Task { try await prefetcher.value(for: "a") }
        try await Task.sleep(for: .milliseconds(20))

        source.fail("a")

        await #expect(throws: ControlledSource.Failure(key: "a")) {
            try await outcome(of: waiting)
        }
        #expect(prefetcher.status(of: "a") == .idle)
    }

    @Test
    func theNextFocusRetriesAFailedKey() async throws {
        let prefetcher = try makePrefetcher(behind: 0, ahead: 0)
        prefetcher.focus(on: 0, in: deck)
        await eventually { source.pendingKeys == ["a"] }
        source.fail("a")
        await eventually { prefetcher.status(of: "a") == .idle }

        prefetcher.focus(on: 0, in: deck)

        await eventually { source.pendingKeys == ["a"] }
        #expect(source.requests == ["a", "a"])
    }
}
