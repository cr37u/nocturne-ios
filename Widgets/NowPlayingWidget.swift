import SwiftUI
import UIKit
import WidgetKit

/// Home-screen widget, same design as the Android widgets (small / medium / large).
struct NowPlayingWidget: Widget {
    let kind = "NocturneNowPlaying"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: NowPlayingProvider()) { entry in
            NowPlayingWidgetView(entry: entry)
        }
        .configurationDisplayName("Nocturne")
        .description(L10n.t("widget_description"))
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct NowPlayingWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: NowPlayingEntry

    var body: some View {
        switch family {
        case .systemSmall: SmallView(entry: entry)
        case .systemLarge: LargeView(entry: entry)
        default: MediumView(entry: entry)
        }
    }
}

// MARK: Small — full-bleed artwork, bottom fade, title + artist, white circular play/pause

private struct SmallView: View {
    let entry: NowPlayingEntry

    var body: some View {
        let snap = entry.snapshot
        Group {
            if entry.hasTrack, let snap {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Spacer()
                        WidgetControl(command: .toggle) {
                            ZStack {
                                Circle().fill(NC.text)
                                IconView(icon: snap.isPlaying ? .pause : .play, size: 15).foregroundStyle(NC.playIcon)
                            }
                            .frame(width: 38, height: 38)
                        }
                    }
                    Spacer(minLength: 0)
                    Text(snap.title)
                        .font(.manropeFixed(15, .extraBold))
                        .foregroundStyle(NC.text)
                        .lineLimit(2)
                    Text(snap.artist)
                        .font(.manropeFixed(12, .semibold))
                        .foregroundStyle(NC.onGradient)
                        .lineLimit(1)
                }
                .legacyWidgetPadding(14)
            } else {
                WidgetEmptyView(groupAvailable: entry.groupAvailable, compact: true)
                    .legacyWidgetPadding(14)
            }
        }
        .widgetBackground {
            ZStack {
                if entry.hasTrack {
                    if let image = snap?.artworkImage {
                        Image(uiImage: image).resizable().scaledToFill()
                    } else {
                        NC.artwork
                        IconView(icon: .moonWave, size: 54, lineWidth: 1.2)
                            .foregroundStyle(NC.text.opacity(0.85))
                            .offset(y: -14)
                    }
                    LinearGradient(stops: [
                        .init(color: .clear, location: 0.35),
                        .init(color: NC.bg.opacity(0.9), location: 1),
                    ], startPoint: .top, endPoint: .bottom)
                } else {
                    NC.primary
                }
            }
        }
        .widgetURL(URL(string: entry.hasTrack ? "nocturne://player" : "nocturne://open"))
    }
}

// MARK: Medium — gradient bg, artwork left, title, artist, progress, previous · play/pause · next

private struct MediumView: View {
    let entry: NowPlayingEntry

    var body: some View {
        Group {
            if entry.hasTrack, let snap = entry.snapshot {
                HStack(spacing: 14) {
                    WidgetArtwork(image: snap.artworkImage, size: 110, radius: 18)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(snap.title)
                            .font(.manropeFixed(16, .extraBold))
                            .foregroundStyle(NC.text)
                            .lineLimit(1)
                        Text(snap.artist)
                            .font(.manropeFixed(13, .regular))
                            .foregroundStyle(NC.onGradient)
                            .lineLimit(1)
                            .padding(.top, 2)
                        Spacer(minLength: 6)
                        WidgetProgressBar(fraction: entry.progress)
                        Spacer(minLength: 6)
                        HStack {
                            WidgetControl(command: .previous) {
                                IconView(icon: .previous, size: 22).foregroundStyle(NC.text).frame(width: 40, height: 40)
                            }
                            Spacer(minLength: 0)
                            WidgetControl(command: .toggle) {
                                ZStack {
                                    Circle().fill(NC.text)
                                    IconView(icon: snap.isPlaying ? .pause : .play, size: 18).foregroundStyle(NC.playIcon)
                                }
                                .frame(width: 44, height: 44)
                            }
                            Spacer(minLength: 0)
                            WidgetControl(command: .next) {
                                IconView(icon: .next, size: 22).foregroundStyle(NC.text).frame(width: 40, height: 40)
                            }
                        }
                    }
                }
                .legacyWidgetPadding()
            } else {
                WidgetEmptyView(groupAvailable: entry.groupAvailable).legacyWidgetPadding()
            }
        }
        .widgetBackground { NC.primary }
        .widgetURL(URL(string: "nocturne://player"))
    }
}

// MARK: Large — header + "Adaugă link", artwork + title, progress, 5 controls, "URMEAZĂ"

private struct LargeView: View {
    let entry: NowPlayingEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous).fill(NC.text.opacity(0.14))
                    IconView(icon: .moon, size: 15).foregroundStyle(NC.text)
                }
                .frame(width: 28, height: 28)
                Text(verbatim: "Nocturne")
                    .font(.manropeFixed(17, .extraBold))
                    .foregroundStyle(NC.text)
                Spacer()
                Link(destination: URL(string: "nocturne://add")!) {
                    HStack(spacing: 5) {
                        IconView(icon: .plus, size: 13, lineWidth: 2.6)
                        Text(L10n.t("widget_add_link")).font(.manropeFixed(12, .bold)).lineLimit(1)
                    }
                    .foregroundStyle(NC.text)
                    .padding(.horizontal, 12)
                    .frame(height: 30)
                    .background(NC.text.opacity(0.14), in: Capsule())
                }
            }
            if entry.hasTrack, let snap = entry.snapshot {
                HStack(spacing: 14) {
                    WidgetArtwork(image: snap.artworkImage, size: 96, radius: 18)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(snap.title)
                            .font(.manropeFixed(18, .extraBold))
                            .foregroundStyle(NC.text)
                            .lineLimit(2)
                        Text(snap.artist)
                            .font(.manropeFixed(14, .regular))
                            .foregroundStyle(NC.onGradient)
                            .lineLimit(1)
                        if let p = snap.playlist {
                            Text(p).font(.manropeFixed(12, .semibold)).foregroundStyle(NC.onGradient.opacity(0.8)).lineLimit(1)
                        }
                    }
                }
                VStack(spacing: 6) {
                    WidgetProgressBar(fraction: entry.progress, height: 5)
                    HStack {
                        Text(Fmt.clock(snap.position(at: entry.date)))
                        Spacer()
                        Text(Fmt.clock(snap.duration))
                    }
                    .font(.manropeFixed(11, .semibold))
                    .foregroundStyle(NC.onGradient)
                }
                HStack {
                    WidgetControl(command: .shuffle) { toggleIcon(.shuffle, on: snap.shuffle) }
                    Spacer(minLength: 0)
                    WidgetControl(command: .previous) {
                        IconView(icon: .previous, size: 24).foregroundStyle(NC.text).frame(width: 44, height: 44)
                    }
                    Spacer(minLength: 0)
                    WidgetControl(command: .toggle) {
                        ZStack {
                            Circle().fill(NC.text)
                            IconView(icon: snap.isPlaying ? .pause : .play, size: 20).foregroundStyle(NC.playIcon)
                        }
                        .frame(width: 52, height: 52)
                    }
                    Spacer(minLength: 0)
                    WidgetControl(command: .next) {
                        IconView(icon: .next, size: 24).foregroundStyle(NC.text).frame(width: 44, height: 44)
                    }
                    Spacer(minLength: 0)
                    WidgetControl(command: .cycleRepeat) {
                        ZStack(alignment: .topTrailing) {
                            toggleIcon(.repeat, on: snap.repeatMode != 0)
                            if snap.repeatMode == 2 {
                                Text(verbatim: "1").font(.manropeFixed(9, .extraBold)).foregroundStyle(NC.bg)
                                    .frame(width: 14, height: 14).background(NC.amber, in: Circle()).offset(x: 2, y: -2)
                            }
                        }
                    }
                }
                Spacer(minLength: 0)
                if let next = snap.nextTitle {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(L10n.t("widget_up_next"))
                            .font(.manropeFixed(11, .bold))
                            .tracking(1.2)
                            .foregroundStyle(NC.onGradient)
                        Text(snap.nextArtist.map { "\(next) · \($0)" } ?? next)
                            .font(.manropeFixed(13, .semibold))
                            .foregroundStyle(NC.text)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(NC.bg.opacity(0.28), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            } else {
                WidgetEmptyView(groupAvailable: entry.groupAvailable)
            }
        }
        .legacyWidgetPadding()
        .widgetBackground { NC.primary }
        .widgetURL(URL(string: "nocturne://player"))
    }

    private func toggleIcon(_ icon: Icon, on: Bool) -> some View {
        IconView(icon: icon, size: 19)
            .foregroundStyle(on ? NC.amber : NC.text)
            .frame(width: 40, height: 40)
            .background(on ? NC.amberBg : Color.clear, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: Lock Screen widgets

struct LockScreenWidget: Widget {
    let kind = "NocturneLockScreen"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: NowPlayingProvider()) { entry in
            LockScreenWidgetView(entry: entry)
        }
        .configurationDisplayName("Nocturne")
        .description(L10n.t("widget_lock_description"))
        .supportedFamilies([.accessoryRectangular, .accessoryCircular, .accessoryInline])
    }
}

struct LockScreenWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: NowPlayingEntry

    var body: some View {
        let snap = entry.snapshot
        Group {
            switch family {
            case .accessoryCircular:
                Gauge(value: entry.progress) {
                    IconView(icon: .moon, size: 10)
                } currentValueLabel: {
                    IconView(icon: snap?.isPlaying == true ? .pause : .moon, size: 16, filled: snap?.isPlaying == true)
                }
                .gaugeStyle(.accessoryCircularCapacity)
            case .accessoryInline:
                Text(entry.hasTrack ? "♪ \(snap?.title ?? "")" : "Nocturne")
            default:
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        IconView(icon: .moon, size: 11)
                        Text(verbatim: "Nocturne").font(.manropeFixed(11, .bold))
                    }
                    .opacity(0.8)
                    Text(entry.hasTrack ? (snap?.title ?? "") : (entry.groupAvailable ? L10n.t("widget_nothing_playing") : L10n.t("widget_open_app")))
                        .font(.manropeFixed(14, .extraBold))
                        .lineLimit(1)
                    if entry.hasTrack {
                        Text(snap?.artist ?? "").font(.manropeFixed(12, .regular)).lineLimit(1)
                        ProgressView(value: entry.progress).tint(.white)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .widgetBackground { Color.clear }
        .widgetURL(URL(string: "nocturne://player"))
    }
}
