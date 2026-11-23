import SwiftUI
import WidgetKit
import UIKit
import AppIntents

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

/// Static equalizer (Live Activities cannot run continuous animations).
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

/// Play/pause/next/previous: interactive App Intent button on iOS 17+, deep link on iOS 16.
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
