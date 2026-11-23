import SwiftUI
import WidgetKit
import UIKit
import AppIntents

struct NowPlayingEntry: TimelineEntry {
    let date: Date
    let snapshot: NowPlayingSnapshot?
    /// False when the App Group is unavailable → "Deschide Nocturne".
    let groupAvailable: Bool

    var hasTrack: Bool { snapshot?.hasTrack == true }
    var progress: Double { snapshot?.progress(at: date) ?? 0 }
}

struct NowPlayingProvider: TimelineProvider {
    func placeholder(in context: Context) -> NowPlayingEntry {
        NowPlayingEntry(date: Date(), snapshot: .preview, groupAvailable: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (NowPlayingEntry) -> Void) {
        FontRegistry.registerIfNeeded()
        L10n.applyStored()
        let snap = NowPlayingSnapshot.load()
        completion(NowPlayingEntry(date: Date(), snapshot: context.isPreview && snap == nil ? .preview : snap,
                                   groupAvailable: AppGroup.isAvailable || context.isPreview))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NowPlayingEntry>) -> Void) {
        FontRegistry.registerIfNeeded()
        L10n.applyStored()
        let snap = NowPlayingSnapshot.load()
        let now = Date()
        var entries = [NowPlayingEntry(date: now, snapshot: snap, groupAvailable: AppGroup.isAvailable)]
        if let snap, snap.isPlaying, snap.duration > 0 {
            // Advance the progress bar while playing (the app reloads on every real change).
            let remaining = max(0, snap.duration - snap.position(at: now))
            var t: TimeInterval = 15
            while t < min(remaining, 300) {
                entries.append(NowPlayingEntry(date: now.addingTimeInterval(t), snapshot: snap, groupAvailable: true))
                t += 15
            }
            completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(min(remaining + 2, 300)))))
        } else {
            completion(Timeline(entries: entries, policy: .never))
        }
    }
}

extension NowPlayingSnapshot {
    static let preview = NowPlayingSnapshot(
        trackId: "preview", title: "Lumini de oraș", artist: "Aria Vale", playlist: "Noaptea târziu",
        isPlaying: true, position: 102, duration: 238, updatedAt: Date(), shuffle: false, repeatMode: 1,
        nextTitle: "Midnight Drive", nextArtist: "Neon Harbor", artworkFile: nil
    )

    var artworkImage: UIImage? {
        guard let url = Self.artworkURL(artworkFile) else { return nil }
        return UIImage(contentsOfFile: url.path)
    }
}

// MARK: - Shared widget pieces

struct WidgetArtwork: View {
    let image: UIImage?
    var size: CGFloat?
    var radius: CGFloat
    var iconScale: CGFloat = 0.42

    var body: some View {
        GeometryReader { geo in
            let side = size ?? min(geo.size.width, geo.size.height)
            ZStack {
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    NC.artwork
                    IconView(icon: .moon, size: side * iconScale, lineWidth: 1.6).foregroundStyle(NC.text.opacity(0.9))
                }
            }
            .frame(width: side, height: side)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        }
        .frame(width: size, height: size)
    }
}

struct WidgetProgressBar: View {
    let fraction: Double
    var height: CGFloat = 4
    var track: Color = NC.text.opacity(0.22)
    var fill: AnyShapeStyle = AnyShapeStyle(NC.text)

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(track)
                Capsule().fill(fill).frame(width: max(height, geo.size.width * CGFloat(fraction)))
            }
        }
        .frame(height: height)
    }
}

/// Static equalizer (Live Activities and widgets cannot run continuous animations).
struct StaticEqualizer: View {
    let playing: Bool
    var heights: [CGFloat] = [10, 15, 12, 8]
    var barWidth: CGFloat = 3
    var spacing: CGFloat = 3
    var color: Color = NC.amber

    var body: some View {
        HStack(alignment: .bottom, spacing: spacing) {
            ForEach(Array(heights.enumerated()), id: \.offset) { _, h in
                Capsule().fill(color).frame(width: barWidth, height: playing ? h : max(barWidth, h * 0.35))
            }
        }
        .frame(height: heights.max() ?? 16, alignment: .bottom)
    }
}

/// Play/pause/next/… control: interactive App Intent button on iOS 17+, deep link on iOS 16.
struct WidgetControl<Label: View>: View {
    let command: PlayerCommand
    @ViewBuilder let label: () -> Label

    var body: some View {
        if #available(iOS 17.0, *) {
            switch command {
            case .toggle: Button(intent: TogglePlaybackIntent()) { label() }.buttonStyle(.plain)
            case .next: Button(intent: NextTrackIntent()) { label() }.buttonStyle(.plain)
            case .previous: Button(intent: PreviousTrackIntent()) { label() }.buttonStyle(.plain)
            case .shuffle: Button(intent: ToggleShuffleIntent()) { label() }.buttonStyle(.plain)
            case .cycleRepeat: Button(intent: CycleRepeatIntent()) { label() }.buttonStyle(.plain)
            }
        } else {
            Link(destination: URL(string: "nocturne://player")!) { label() }
        }
    }
}

extension View {
    @ViewBuilder
    func widgetBackground<B: View>(@ViewBuilder _ background: () -> B) -> some View {
        if #available(iOS 17.0, *) {
            self.containerBackground(for: .widget) { background() }
        } else {
            self.background(background())
        }
    }

    /// iOS 17+ adds content margins itself; iOS 16 needs explicit padding.
    @ViewBuilder
    func legacyWidgetPadding(_ value: CGFloat = 16) -> some View {
        if #available(iOS 17.0, *) {
            self
        } else {
            self.padding(value)
        }
    }
}

/// "Deschide Nocturne" / "Nu se redă nimic" state.
struct WidgetEmptyView: View {
    let groupAvailable: Bool
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous).fill(NC.primary)
                IconView(icon: .moon, size: 16).foregroundStyle(NC.text)
            }
            .frame(width: 32, height: 32)
            Spacer(minLength: 0)
            Text(groupAvailable ? L10n.t("widget_nothing_playing") : L10n.t("widget_open_app"))
                .font(.manropeFixed(compact ? 14 : 16, .extraBold))
                .foregroundStyle(NC.text)
                .lineLimit(2)
            if groupAvailable {
                Text(L10n.t("widget_pick_song"))
                    .font(.manropeFixed(12, .regular))
                    .foregroundStyle(NC.onGradient)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}
