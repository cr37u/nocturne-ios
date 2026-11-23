import Foundation

/// Watches Documents/Music/Nocturne: when songs are deleted in the Files app, they disappear
/// from the library too (also checked every time the app comes to the foreground).
final class FolderWatcher {
    static let shared = FolderWatcher()

    private var source: DispatchSourceFileSystemObject?
    private var pending: DispatchWorkItem?

    func start() {
        guard source == nil, !ProcessInfo.processInfo.arguments.contains("-demoData") else { return }
        let fd = open(Storage.musicDir.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .delete, .rename], queue: .main)
        src.setEventHandler { [weak self] in self?.scheduleCheck() }
        src.setCancelHandler { close(fd) }
        src.resume()
        source = src
        check()
    }

    private func scheduleCheck() {
        pending?.cancel()
        let work = DispatchWorkItem { FolderWatcher.shared.check() }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: work)
    }

    func check() {
        guard !ProcessInfo.processInfo.arguments.contains("-demoData") else { return }
        Library.shared.pruneMissingFiles()
    }
}
