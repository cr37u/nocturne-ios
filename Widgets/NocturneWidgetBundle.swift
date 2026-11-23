import SwiftUI
import WidgetKit

@main
struct NocturneWidgetBundle: WidgetBundle {
    init() {
        FontRegistry.registerIfNeeded()
        L10n.applyStored()
    }

    var body: some Widget {
        NowPlayingWidget()
        LockScreenWidget()
        NocturneLiveActivity()
    }
}
