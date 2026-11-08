# LookAhead

[![Licence: MIT](https://img.shields.io/badge/Licence-MIT-blue.svg)](LICENSE)

[Darllen yn Gymraeg](README.cy.md)

A small Swift package that keeps the resources around the current position in an ordered list loaded and ready, so the next one is there before it is asked for.

It was written for flashcards: while the learner is on one card, the audio for the cards either side is already loaded and its player prepared, so a tap sounds at once. Nothing in it is specific to audio or to flashcards.

[Watch a short demo](https://vimeo.com/1243691688) · [Gwylio'r fideo yn Gymraeg](https://vimeo.com/1243701453)

## What it does

- **A window around the focus.** Tell the prefetcher which position is focused, and it loads every key within the window (by default one behind and two ahead), nearest first.
- **Lets go of the rest.** Loads for keys that leave the window are cancelled, and ready values for them are dropped.
- **One load per key.** Asking for a value that is still loading waits for that load rather than starting another. A key that appears twice in the list is loaded once.
- **Two stages.** Your source fetches a `Sendable` resource off the main actor, such as a file URL. An optional `prepare` step then runs on the main actor and turns it into the value you use, which need not be `Sendable`, such as an audio player.
- **Keys, not positions.** The list can be reordered or shuffled between calls.
- **No dependencies.**

## Requirements

- iOS, macOS, tvOS, visionOS or watchOS 26 or later
- Swift 6.2 or later

## Installation

Add the package to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/async-digital-ltd/look-ahead.git", from: "1.0.0")
]
```

Then depend on the `LookAhead` product from any target that needs it. In Xcode, use File > Add Package Dependencies with the same URL.

## Example

A source supplies the resource for a key. Here it finds a word's recording in the app bundle:

```swift
import AVFoundation
import LookAhead

struct MissingRecording: Error {}

struct BundledRecordings: PrefetchSource {
    func fetch(_ word: String) async throws -> URL {
        guard let url = Bundle.main.url(forResource: word, withExtension: "m4a") else {
            throw MissingRecording()
        }
        return url
    }
}
```

The prefetcher builds a ready-to-play player for each word in the window:

```swift
@MainActor
final class Pronunciation {
    private let players = Prefetcher(source: BundledRecordings()) { url in
        let player = try AVAudioPlayer(contentsOf: url)
        player.prepareToPlay()
        return player
    }

    /// Call whenever the current card changes.
    func show(_ position: Int, in words: [String]) {
        players.focus(on: position, in: words)
    }

    /// Plays at once if the player is ready, or as soon as it is.
    func play(_ word: String) async throws {
        try await players.value(for: word).play()
    }
}
```

`readyValue(for:)` returns a value only if it is ready now, and `status(of:)` reports whether a key is idle, loading or ready. For a different window, pass one in: `PrefetchWindow(behind: 0, ahead: 3)` returns `nil` if either count is negative.

## Licence

MIT. See [LICENSE](LICENSE).
