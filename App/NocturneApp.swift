import SwiftUI
import UIKit
import UserNotifications

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        FontRegistry.registerIfNeeded()
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    /// Background download session events (downloads finished while the app was suspended).
    func application(_ application: UIApplication, handleEventsForBackgroundURLSession identifier: String, completionHandler: @escaping () -> Void) {
        DownloadManager.shared.backgroundCompletionHandler = completionHandler
        DownloadManager.shared.start()
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner])
    }
}

@main
struct NocturneApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase

    @StateObject private var library = Library.shared
    @StateObject private var engine = PlayerEngine.shared
    @StateObject private var downloads = DownloadManager.shared
    @StateObject private var lang = LanguageManager.shared
    @StateObject private var app = AppState.shared

    init() {
        FontRegistry.registerIfNeeded()
        let engine = PlayerEngine.shared
        if ProcessInfo.processInfo.arguments.contains("-demoData") {
            DemoData.install()
        } else {
            engine.configureAudioSession()
            engine.restore()
        }
        IntentBridge.handler = { command in PlayerEngine.shared.handle(command) }
        SystemSurfaces.shared.start()
        DownloadManager.shared.start()
        FolderWatcher.shared.start()
        UIScrollView.appearance().keyboardDismissMode = .interactive
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(library)
                .environmentObject(engine)
                .environmentObject(downloads)
                .environmentObject(lang)
                .environmentObject(app)
                .environment(\.locale, lang.locale)
                .preferredColorScheme(.dark)
                .onOpenURL { app.handle(url: $0) }
        }
        .onChange(of: scenePhase) { phase in
            switch phase {
            case .active:
                lang.refreshSystemLanguage()
                FolderWatcher.shared.check()
                consumePendingLinks()
                detectClipboard()
                DownloadManager.shared.pump()
                SystemSurfaces.shared.refreshAll()
            case .background:
                PlayerEngine.shared.savePosition()
            default:
                break
            }
        }
    }

    /// Links sent with Share → Nocturne while the app was closed.
    private func consumePendingLinks() {
        let links = AppGroup.popPendingLinks()
        if let first = links.first { app.openAdd(first) }
    }

    /// Clipboard detection on open (no paste prompt until the user taps "Adaugă").
    private func detectClipboard() {
        let pb = UIPasteboard.general
        guard pb.hasStrings || pb.hasURLs else { return }
        let change = pb.changeCount
        guard UserDefaults.standard.integer(forKey: "clipboardSeen") != change else { return }
        UserDefaults.standard.set(change, forKey: "clipboardSeen")
        pb.detectPatterns(for: [.probableWebURL]) { result in
            guard case .success(let patterns) = result, patterns.contains(.probableWebURL) else { return }
            Task { @MainActor in
                AppState.shared.clipboardLink = ""
            }
        }
    }
}

/// Library navigation + floating mini-player (safe-area inset) + Now Playing overlay + sheets.
struct RootView: View {
    @EnvironmentObject private var engine: PlayerEngine
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var library: Library
    @EnvironmentObject private var lang: LanguageManager
    @Namespace private var heroNamespace

    var body: some View {
        GeometryReader { geo in
            let metrics = Metrics(
                profile: DeviceProfile.classify(safeTop: geo.safeAreaInsets.top, safeBottom: geo.safeAreaInsets.bottom, width: geo.size.width),
                width: geo.size.width,
                safeTop: geo.safeAreaInsets.top,
                safeBottom: geo.safeAreaInsets.bottom
            )
            ZStack(alignment: .bottom) {
                NC.bg.ignoresSafeArea()
                NavigationStack(path: $app.path) {
                    LibraryView()
                        .navigationDestination(for: Route.self) { route in
                            switch route {
                            case .playlist(let id): PlaylistDetailView(playlistId: id)
                            case .favorites: PlaylistDetailView(playlistId: nil)
                            case .settings: SettingsView()
                            case .add(let link): AddMusicView(initialLink: link)
                            }
                        }
                }
                .tint(NC.brightStart)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    miniPlayerInset(metrics)
                }

                if app.nowPlayingOpen && engine.hasTrack {
                    NowPlayingView(namespace: heroNamespace)
                        .transition(.asymmetric(insertion: .opacity.combined(with: .move(edge: .bottom)), removal: .move(edge: .bottom).combined(with: .opacity)))
                        .zIndex(2)
                }

                if let toast = app.toast {
                    ToastView(text: toast)
                        .padding(.bottom, (engine.hasTrack && !app.nowPlayingOpen ? 96 : 24) + metrics.safeBottom)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .zIndex(3)
                }
            }
            .environment(\.metrics, metrics)
            .ignoresSafeArea(.keyboard, edges: .bottom)
        }
        .dynamicTypeSize(.xSmall ... .xxLarge)
        .sheet(item: $app.playlistPickerTrack) { track in
            PlaylistPickerSheet(track: track).presentationDetents([.medium, .large])
        }
        .sheet(item: $app.editTrack) { track in
            EditDetailsSheet(track: track).presentationDetents([.height(340)])
        }
        .sheet(isPresented: $app.queueOpen) {
            QueueSheet().presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $app.lyricsOpen) {
            if let track = engine.current {
                LyricsSheet(track: track).presentationDetents([.medium, .large])
            }
        }
        .confirmationDialog(
            L10n.t("delete_track_title"),
            isPresented: Binding(get: { app.deleteTrack != nil }, set: { if !$0 { app.deleteTrack = nil } }),
            titleVisibility: .visible,
            presenting: app.deleteTrack
        ) { track in
            Button(L10n.t("delete"), role: .destructive) {
                library.delete(track)
                app.showToast(L10n.t("track_deleted"))
            }
            Button(L10n.t("cancel"), role: .cancel) {}
        } message: { track in
            Text(L10n.f("delete_track_body", track.title))
        }
    }

    @ViewBuilder
    private func miniPlayerInset(_ m: Metrics) -> some View {
        if engine.hasTrack && !app.nowPlayingOpen {
            MiniPlayer(namespace: heroNamespace)
                .padding(.horizontal, m.miniSide)
                .padding(.bottom, max(0, m.miniBottomFromScreen - m.safeBottom))
                .padding(.top, 8)
                .background(alignment: .bottom) {
                    // Fade above the mini-player so the list dissolves behind it.
                    LinearGradient(stops: [
                        .init(color: NC.bg.opacity(0), location: 0),
                        .init(color: NC.bg, location: 0.55),
                    ], startPoint: .top, endPoint: .bottom)
                    .frame(height: m.fadeHeight)
                    .ignoresSafeArea(edges: .bottom)
                    .allowsHitTesting(false)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}

/// Keeps the swipe-back gesture with hidden navigation bars.
extension UINavigationController: UIGestureRecognizerDelegate {
    override open func viewDidLoad() {
        super.viewDidLoad()
        interactivePopGestureRecognizer?.delegate = self
    }

    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        viewControllers.count > 1
    }
}
