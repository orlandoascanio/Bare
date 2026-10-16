import AppKit

/// Hides Desktop items by setting the standard macOS "hidden" file flag (the same
/// thing `chflags hidden` does). Files are never moved, renamed or deleted, and
/// Finder picks up the change instantly without a restart.
final class DesktopHider {
    struct Item {
        let url: URL
        let name: String
        let category: Category
        let isHidden: Bool
    }

    let desktop: URL

    init(desktop: URL? = nil) {
        self.desktop = desktop
            ?? FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop", isDirectory: true)
    }

    var onChange: (() -> Void)?
    private(set) var lastError: String?

    private let settings = Settings.shared
    private var watcher: DispatchSourceFileSystemObject?
    private var pendingApply: DispatchWorkItem?

    // MARK: Scanning

    func scan() -> [Item] {
        let urls: [URL]
        do {
            urls = try FileManager.default.contentsOfDirectory(
                at: desktop, includingPropertiesForKeys: Classifier.keys, options: [])
            lastError = nil
        } catch {
            lastError = error.localizedDescription
            return []
        }

        return urls.compactMap { url in
            let name = url.lastPathComponent
            // Dotfiles (.DS_Store, .localized…) are always invisible; leave them alone.
            guard !name.hasPrefix("."),
                  let values = try? url.resourceValues(forKeys: Set(Classifier.keys)),
                  let flags = Self.fileFlags(url)
            else { return nil }
            return Item(
                url: url, name: name,
                category: Classifier.category(of: url, values: values),
                isHidden: flags & UInt32(UF_HIDDEN) != 0)
        }
    }

    // MARK: Applying

    /// Brings the Desktop in line with the current settings. Safe to call any time.
    /// - Parameter forceShow: show everything we hid without changing the saved settings (used on quit).
    func apply(forceShow: Bool = false) {
        let items = scan()
        let wanted: Set<Category> = (settings.isHiding && !forceShow) ? settings.enabledCategories : []
        var tracked = settings.trackedNames
        var changed = false

        for item in items {
            let ours = tracked.contains(item.name)
            // Hidden by you (not by us): never touch it.
            if item.isHidden && !ours { continue }

            let shouldHide = wanted.contains(item.category)
            if shouldHide {
                if !item.isHidden {
                    if setHidden(item.url, true) { changed = true } else { continue }
                }
                tracked.insert(item.name)
            } else if ours {
                if item.isHidden {
                    if setHidden(item.url, false) { changed = true } else { continue }
                }
                tracked.remove(item.name)
            }
        }

        // Forget items that were deleted/moved off the Desktop (only if the scan worked).
        if lastError == nil {
            tracked.formIntersection(items.map(\.name))
        }
        settings.trackedNames = tracked

        if changed { NSWorkspace.shared.noteFileSystemChanged(desktop.path) }
        applyDrives(hide: settings.isHiding && settings.hideDrives && !forceShow)
        onChange?()
    }

    var hiddenCount: Int { settings.trackedNames.count }

    private func setHidden(_ url: URL, _ hidden: Bool) -> Bool {
        // lchflags so a symlink on the Desktop is hidden itself, never its target.
        let ok = url.withUnsafeFileSystemRepresentation { path -> Bool in
            guard let path else { return false }
            var st = stat()
            guard lstat(path, &st) == 0 else { return false }
            var flags = st.st_flags
            if hidden { flags |= UInt32(UF_HIDDEN) } else { flags &= ~UInt32(UF_HIDDEN) }
            return lchflags(path, flags) == 0
        }
        if !ok { lastError = "Couldn't change \(url.lastPathComponent): \(String(cString: strerror(errno)))" }
        return ok
    }

    private static func fileFlags(_ url: URL) -> UInt32? {
        url.withUnsafeFileSystemRepresentation { path -> UInt32? in
            guard let path else { return nil }
            var st = stat()
            return lstat(path, &st) == 0 ? st.st_flags : nil
        }
    }

    // MARK: Disks & servers

    private static let finder = "com.apple.finder" as CFString
    private static let driveKeys = [
        "ShowHardDrivesOnDesktop", "ShowExternalHardDrivesOnDesktop",
        "ShowRemovableMediaOnDesktop", "ShowMountedServersOnDesktop",
    ]

    private func applyDrives(hide: Bool) {
        guard hide != settings.drivesHiddenByUs else { return }

        if hide {
            var saved: [String: Bool] = [:]
            for key in Self.driveKeys {
                if let v = CFPreferencesCopyAppValue(key as CFString, Self.finder) as? Bool { saved[key] = v }
                CFPreferencesSetAppValue(key as CFString, kCFBooleanFalse, Self.finder)
            }
            settings.savedDriveValues = saved
        } else {
            let saved = settings.savedDriveValues
            for key in Self.driveKeys {
                let value: CFPropertyList? = saved[key].map { $0 ? kCFBooleanTrue : kCFBooleanFalse }
                CFPreferencesSetAppValue(key as CFString, value, Self.finder)
            }
        }
        CFPreferencesAppSynchronize(Self.finder)
        settings.drivesHiddenByUs = hide
        relaunchFinder()
    }

    private func relaunchFinder() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        p.arguments = ["Finder"]
        try? p.run()
        p.waitUntilExit()
    }

    // MARK: Watching for new files

    func startWatching() {
        stopWatching()
        let fd = open(desktop.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .rename, .delete, .link], queue: .main)
        source.setEventHandler { [weak self] in self?.desktopChanged() }
        source.setCancelHandler { close(fd) }
        source.resume()
        watcher = source
    }

    func stopWatching() {
        watcher?.cancel()
        watcher = nil
    }

    private func desktopChanged() {
        guard settings.isHiding, settings.autoHideNew else { return }
        // Debounce: screenshots and downloads land as a burst of events.
        pendingApply?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.apply() }
        pendingApply = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }
}
