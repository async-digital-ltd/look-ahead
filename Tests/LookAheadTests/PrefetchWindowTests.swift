// Copyright (c) 2026 Async Digital Ltd
// SPDX-License-Identifier: MIT

import LookAhead
import Testing

struct PrefetchWindowTests {
    private func window(behind: Int, ahead: Int) throws -> PrefetchWindow {
        try #require(PrefetchWindow(behind: behind, ahead: ahead))
    }

    @Test
    func standardWindowIsOneBehindTwoAhead() {
        #expect(PrefetchWindow.standard.behind == 1)
        #expect(PrefetchWindow.standard.ahead == 2)
    }

    @Test(arguments: [(-1, 0), (0, -1), (-3, -3)])
    func negativeCountsAreRejected(behind: Int, ahead: Int) {
        #expect(PrefetchWindow(behind: behind, ahead: ahead) == nil)
    }

    @Test
    func zeroCountsAreAllowed() throws {
        let window = try window(behind: 0, ahead: 0)
        #expect(window.positions(around: 3, within: 0..<10) == [3])
    }

    @Test
    func positionsAreNearestFirstWithAheadBeforeBehind() throws {
        let window = try window(behind: 2, ahead: 3)
        #expect(window.positions(around: 5, within: 0..<10) == [5, 6, 7, 8, 4, 3])
    }

    @Test
    func windowIsClippedAtTheStart() throws {
        let window = try window(behind: 2, ahead: 1)
        #expect(window.positions(around: 0, within: 0..<10) == [0, 1])
    }

    @Test
    func windowIsClippedAtTheEnd() throws {
        let window = try window(behind: 1, ahead: 3)
        #expect(window.positions(around: 9, within: 0..<10) == [9, 8])
    }

    // -1 and 10 sit where the window would still reach inside the bounds.
    @Test(arguments: [-1, -5, 10, 42])
    func focusOutsideTheBoundsGivesNoPositions(focus: Int) throws {
        let window = try window(behind: 1, ahead: 2)
        #expect(window.positions(around: focus, within: 0..<10).isEmpty)
    }

    @Test
    func emptyBoundsGiveNoPositions() throws {
        let window = try window(behind: 1, ahead: 2)
        #expect(window.positions(around: 0, within: 0..<0).isEmpty)
    }
}
