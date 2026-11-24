import SwiftUI

/// Put at the end of every scrolling list: lets the last row scroll above the floating mini-player.
struct MiniPlayerSpacer: View {
    @EnvironmentObject private var engine: PlayerEngine
    @Environment(\.metrics) private var m

    var body: some View {
        Color.clear
            .frame(height: engine.hasTrack ? m.miniPlayerClearance : 16)
            .accessibilityHidden(true)
    }
}

extension View {
    /// List variant: an invisible last row.
    func miniPlayerSpacerRow() -> some View {
        MiniPlayerSpacer()
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }
}
