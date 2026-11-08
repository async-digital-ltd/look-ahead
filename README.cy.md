# LookAhead

[![Fersiynau Swift](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fasync-digital-ltd%2Flook-ahead%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/async-digital-ltd/look-ahead) [![Platfformau](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fasync-digital-ltd%2Flook-ahead%2Fbadge%3Ftype%3Dplatforms&label=Platfformau)](https://swiftpackageindex.com/async-digital-ltd/look-ahead) [![Trwydded: MIT](https://img.shields.io/badge/Trwydded-MIT-blue.svg)](LICENSE)

[Read in English](README.md)

Pecyn Swift bach sy'n cadw'r adnoddau o gwmpas y safle presennol mewn rhestr drefnedig wedi'u llwytho ac yn barod, fel bod yr un nesaf yno cyn i neb ofyn amdano.

Cafodd ei ysgrifennu ar gyfer cardiau fflach: tra bo'r dysgwr ar un cerdyn, mae'r sain ar gyfer y cardiau bob ochr iddo wedi'i llwytho'n barod a'i chwaraewr wedi'i baratoi, felly mae tap yn chwarae'r sain ar unwaith. Does dim byd ynddo sy'n benodol i sain nac i gardiau fflach.

[Gwylio fideo byr](https://vimeo.com/1243701453) · [Watch the demo in English](https://vimeo.com/1243691688)

## Beth mae'n ei wneud

- **Ffenestr o gwmpas y ffocws.** Dywedwch wrth y rhaglwythwr pa safle sydd dan ffocws, ac mae'n llwytho pob allwedd o fewn y ffenestr (un y tu ôl a dau o'r blaen yn ddiofyn), yr agosaf yn gyntaf.
- **Yn gollwng y gweddill.** Mae llwythiadau ar gyfer allweddi sy'n gadael y ffenestr yn cael eu canslo, ac mae gwerthoedd parod ar eu cyfer yn cael eu gollwng.
- **Un llwythiad i bob allwedd.** Mae gofyn am werth sy'n dal i lwytho yn aros am y llwythiad hwnnw yn hytrach na dechrau un arall. Mae allwedd sy'n ymddangos ddwywaith yn y rhestr yn cael ei llwytho unwaith.
- **Dau gam.** Mae eich ffynhonnell yn nôl adnodd `Sendable` oddi ar y prif actor, fel URL ffeil. Yna mae cam `prepare` dewisol yn rhedeg ar y prif actor ac yn ei droi'n werth rydych chi'n ei ddefnyddio, nad oes rhaid iddo fod yn `Sendable`, fel chwaraewr sain.
- **Allweddi, nid safleoedd.** Gallwch aildrefnu neu gymysgu'r rhestr rhwng galwadau.
- **Dim dibyniaethau.**

## Gofynion

- iOS, macOS, tvOS, visionOS neu watchOS 26 neu'n ddiweddarach
- Swift 6.2 neu'n ddiweddarach

## Gosod

Ychwanegwch y pecyn at eich `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/async-digital-ltd/look-ahead.git", from: "1.0.0")
]
```

Yna ychwanegwch y cynnyrch `LookAhead` fel dibyniaeth i unrhyw darged sydd ei angen. Yn Xcode, defnyddiwch File > Add Package Dependencies gyda'r un URL.

## Enghraifft

Mae ffynhonnell yn darparu'r adnodd ar gyfer allwedd. Yma mae'n dod o hyd i recordiad gair ym mwndel yr ap:

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

Mae'r rhaglwythwr yn adeiladu chwaraewr sy'n barod i chwarae ar gyfer pob gair yn y ffenestr:

```swift
@MainActor
final class Pronunciation {
    private let players = Prefetcher(source: BundledRecordings()) { url in
        let player = try AVAudioPlayer(contentsOf: url)
        player.prepareToPlay()
        return player
    }

    /// Galwch hwn bob tro y bydd y cerdyn presennol yn newid.
    func show(_ position: Int, in words: [String]) {
        players.focus(on: position, in: words)
    }

    /// Yn chwarae ar unwaith os yw'r chwaraewr yn barod, neu cyn gynted ag y bydd.
    func play(_ word: String) async throws {
        try await players.value(for: word).play()
    }
}
```

Mae `readyValue(for:)` yn dychwelyd gwerth dim ond os yw'n barod nawr, ac mae `status(of:)` yn dweud a yw allwedd yn segur, yn llwytho neu'n barod. I gael ffenestr wahanol, rhowch un i mewn: mae `PrefetchWindow(behind: 0, ahead: 3)` yn dychwelyd `nil` os yw'r naill gyfrif neu'r llall yn negatif.

## Trwydded

MIT. Gweler [LICENSE](LICENSE).
