// Copyright (c) 2026 Async Digital Ltd
// SPDX-License-Identifier: MIT

/// How many positions either side of the focused one to keep loaded.
///
/// A window of one behind and two ahead, focused on position 5, keeps
/// positions 4 to 7 loaded and lets everything else go.
public struct PrefetchWindow: Hashable, Sendable {
    public let behind: Int
    public let ahead: Int

    /// One behind, so stepping back is instant, and two ahead, so a quick
    /// double step forward is still covered.
    public static let standard = Self(uncheckedBehind: 1, ahead: 2)

    /// Returns `nil` when either count is negative.
    public init?(behind: Int, ahead: Int) {
        guard behind >= 0, ahead >= 0 else { return nil }
        self.init(uncheckedBehind: behind, ahead: ahead)
    }

    private init(uncheckedBehind behind: Int, ahead: Int) {
        self.behind = behind
        self.ahead = ahead
    }

    /// The positions inside the window, nearest first: the focused position,
    /// then the positions ahead in order, then the positions behind in order.
    ///
    /// The order is the order loads start in. Positions outside `bounds` are
    /// left out, so a window near either end is smaller. A focus outside
    /// `bounds` gives no positions, even when the window would reach inside.
    public func positions(around focus: Int, within bounds: Range<Int>) -> [Int] {
        guard bounds.contains(focus) else { return [] }
        let ahead = (0...ahead).map { focus + $0 }
        let behind = (0..<behind).map { focus - 1 - $0 }
        return (ahead + behind).filter(bounds.contains)
    }
}
