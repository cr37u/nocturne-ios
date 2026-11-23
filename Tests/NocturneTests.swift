import XCTest
@testable import Nocturne

final class YouTubeLinksTests: XCTestCase {
    func testVideoForms() {
        XCTAssertEqual(YouTubeLinks.parse("https://www.youtube.com/watch?v=dQw4w9WgXcQ"), .video("dQw4w9WgXcQ"))
        XCTAssertEqual(YouTubeLinks.parse("https://youtu.be/dQw4w9WgXcQ?si=abc"), .video("dQw4w9WgXcQ"))
        XCTAssertEqual(YouTubeLinks.parse("https://music.youtube.com/watch?v=dQw4w9WgXcQ&feature=share"), .video("dQw4w9WgXcQ"))
        XCTAssertEqual(YouTubeLinks.parse("https://www.youtube.com/shorts/dQw4w9WgXcQ"), .video("dQw4w9WgXcQ"))
        XCTAssertEqual(YouTubeLinks.parse("m.youtube.com/watch?v=dQw4w9WgXcQ"), .video("dQw4w9WgXcQ"))
        XCTAssertEqual(YouTubeLinks.parse("https://www.youtube.com/live/dQw4w9WgXcQ"), .video("dQw4w9WgXcQ"))
    }

    func testPlaylistForms() {
        XCTAssertEqual(YouTubeLinks.parse("https://www.youtube.com/playlist?list=PLx0sYbCqOb8TBPRdmBHs5Iftvv9TPboYG"),
                       .playlist("PLx0sYbCqOb8TBPRdmBHs5Iftvv9TPboYG"))
        XCTAssertEqual(YouTubeLinks.parse("https://www.youtube.com/watch?v=dQw4w9WgXcQ&list=PLx0sYbCqOb8TBPRdmBHs5Iftvv9TPboYG"),
                       .playlist("PLx0sYbCqOb8TBPRdmBHs5Iftvv9TPboYG"))
        let mix = YouTubeLinks.parse("https://www.youtube.com/watch?v=dQw4w9WgXcQ&list=RDdQw4w9WgXcQ")
        XCTAssertEqual(mix, .playlist("RDdQw4w9WgXcQ"))
        XCTAssertTrue(mix?.isMix == true)
        XCTAssertEqual(mix?.mixSeed, "dQw4w9WgXcQ")
    }

    func testRejects() {
        XCTAssertNil(YouTubeLinks.parse("https://vimeo.com/123"))
        XCTAssertNil(YouTubeLinks.parse("https://www.youtube.com/watch?v=short"))
        XCTAssertNil(YouTubeLinks.parse(""))
    }

    func testExtractFromSharedText() {
        XCTAssertEqual(YouTubeLinks.extractURL(from: "Ascultă asta – https://youtu.be/dQw4w9WgXcQ."), "https://youtu.be/dQw4w9WgXcQ")
        XCTAssertEqual(YouTubeLinks.extractURL(from: "youtu.be/dQw4w9WgXcQ"), "https://youtu.be/dQw4w9WgXcQ")
        XCTAssertNil(YouTubeLinks.extractURL(from: "nimic aici"))
    }
}

final class SearchKeyTests: XCTestCase {
    func testDiacriticsAndCase() {
        XCTAssertEqual(SearchKey.normalize("Lumini de Oraș"), "lumini de oras")
        XCTAssertEqual(SearchKey.normalize("ŞŢĂÂÎ  ţară"), "staai tara")
        XCTAssertEqual(SearchKey.normalize("Горы Ёлка"), "горы елка")
    }

    func testLibrarySearch() {
        let lib = Library.shared
        let t = Track(id: "abcdefghijk", title: "Lumini de oraș", artist: "Aria Vale", durationMs: 1000, fileName: "x.m4a",
                      artworkFile: nil, sizeBytes: 0, format: "m4a", addedAt: Date(), isFavorite: false, sourceUrl: "",
                      userEdited: false, searchKey: SearchKey.of("Lumini de oraș", "Aria Vale"))
        XCTAssertEqual(lib.search("ORAS", in: [t]).count, 1)
        XCTAssertEqual(lib.search("aria oraș", in: [t]).count, 1)
        XCTAssertEqual(lib.search("drive", in: [t]).count, 0)
    }
}

final class LyricsParsingTests: XCTestCase {
    func testLrc() {
        let lines = Lrc.parse("[00:12.50] Prima\n[00:05.1][01:00.123] Refren\nfără timp")
        XCTAssertEqual(lines.map(\.text), ["Refren", "Prima", "Refren"])
        XCTAssertEqual(lines[0].time, 5.1, accuracy: 0.001)
        XCTAssertEqual(lines[2].time, 60.123, accuracy: 0.001)
    }

    func testSongQuery() {
        let (a, t) = SongQuery.from(title: "Kavinsky - Nightcall (Official Audio)", channel: "KavinskyVEVO")
        XCTAssertEqual(a, "Kavinsky")
        XCTAssertEqual(t, "Nightcall")
        let (a2, t2) = SongQuery.from(title: "Song ft. Someone", channel: "Artist - Topic")
        XCTAssertEqual(a2, "Artist")
        XCTAssertEqual(t2, "Song")
    }
}

final class LocalizationTests: XCTestCase {
    override func tearDown() { L10n.apply(.ro) }

    func testRomanianPlurals() {
        L10n.apply(.ro)
        XCTAssertEqual(L10n.p("songs_count", 1), "1 melodie")
        XCTAssertEqual(L10n.p("songs_count", 2), "2 melodii")
        XCTAssertEqual(L10n.p("songs_count", 20), "20 de melodii")
        XCTAssertEqual(L10n.t("tab_songs"), "Melodii")
    }

    func testRussianPlurals() {
        L10n.apply(.ru)
        XCTAssertEqual(L10n.p("songs_count", 1), "1 песня")
        XCTAssertEqual(L10n.p("songs_count", 2), "2 песни")
        XCTAssertEqual(L10n.p("songs_count", 5), "5 песен")
    }

    func testEnglish() {
        L10n.apply(.en)
        XCTAssertEqual(L10n.p("songs_count", 1), "1 song")
        XCTAssertEqual(L10n.p("songs_count", 2), "2 songs")
        XCTAssertEqual(L10n.t("tab_songs"), "Songs")
    }

    func testSpeedFormatting() {
        L10n.apply(.ro)
        XCTAssertEqual(Fmt.speed(4.2 * 1_048_576), "4,2 MB/s")
        L10n.apply(.en)
        XCTAssertEqual(Fmt.speed(4.2 * 1_048_576), "4.2 MB/s")
    }

    func testClock() {
        XCTAssertEqual(Fmt.clock(238), "3:58")
        XCTAssertEqual(Fmt.clock(3723), "1:02:03")
    }
}

final class LayoutTests: XCTestCase {
    func testDeviceProfiles() {
        XCTAssertEqual(DeviceProfile.classify(safeTop: 20, safeBottom: 0, width: 375), .homeButton)
        XCTAssertEqual(DeviceProfile.classify(safeTop: 47, safeBottom: 34, width: 390), .notch)
        XCTAssertEqual(DeviceProfile.classify(safeTop: 59, safeBottom: 34, width: 393), .dynamicIsland)
        XCTAssertEqual(DeviceProfile.classify(safeTop: 59, safeBottom: 34, width: 430), .large)
        XCTAssertEqual(DeviceProfile.classify(safeTop: 62, safeBottom: 34, width: 402), .dynamicIsland)
    }

    func testArtworkScalesWithWidth() {
        let notch = Metrics(profile: .notch, width: 390, safeTop: 47, safeBottom: 34)
        XCTAssertEqual(notch.npArtwork(availableHeight: 763), 342)
        let island = Metrics(profile: .dynamicIsland, width: 393, safeTop: 59, safeBottom: 34)
        XCTAssertEqual(island.npArtwork(availableHeight: 759), 345)
        let se = Metrics(profile: .homeButton, width: 375, safeTop: 20, safeBottom: 0)
        XCTAssertLessThan(se.npArtwork(availableHeight: 647), 327)
    }

    func testSVGParser() {
        let path = SVGPath.parse("M20 14.5A8 8 0 1 1 9.5 4a6.5 6.5 0 0 0 10.5 10.5z")
        let box = path.boundingRect
        XCTAssertGreaterThan(box.width, 10)
        XCTAssertLessThan(box.maxX, 24.5)
        XCTAssertEqual(SVGPath.tokenize("m5 4 10 8-10 8z"), ["m", "5", "4", "10", "8", "-10", "8", "z"])
        XCTAssertEqual(SVGPath.tokenize("c-1.8 0-3 .5-4.5 2"), ["c", "-1.8", "0", "-3", ".5", "-4.5", "2"])
    }
}
