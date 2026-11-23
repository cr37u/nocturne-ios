import SwiftUI
import WidgetKit

/// The extension only hosts the Live Activity (optional, Setări → Sistem).
@main
struct NocturneWidgetBundle: WidgetBundle {
    init() {
        FontRegistry.registerIfNeeded()
        L10n.applyStored()
    }

    var body: some Widget {
        NocturneLiveActivity()
    }
}
