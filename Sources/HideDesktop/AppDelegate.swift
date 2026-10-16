import AppKit
import Carbon.HIToolbox
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let settings = Settings.shared
    private let hider = DesktopHider()
    private let menu = NSMenu()
    private var statusItem: NSStatusItem!
    private var hotKey: HotKey?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(statusItemClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        menu.delegate = self

        hider.onChange = { [weak self] in self?.updateIcon() }
        hider.startWatching()
        hider.apply()
        updateHotKey()
        updateIcon()

        if hider.lastError != nil { showDesktopAccessAlert() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if settings.restoreOnQuit { hider.apply(forceShow: true) }
    }

    // MARK: Status item

    private var pendingToggle: DispatchWorkItem?
    private var lastToggleTime: TimeInterval = 0

    /// Click = hide/show, double-click / right-click / ⌥-click = menu.
    @objc private func statusItemClicked() {
        let event = NSApp.currentEvent
        let flags = event?.modifierFlags ?? []
        let forceMenu = !settings.clickToToggle
            || event?.type == .rightMouseUp
            || flags.contains(.option) || flags.contains(.control)

        if forceMenu {
            openMenu()
        } else if (event?.clickCount ?? 1) >= 2 {
            // Second click of a double-click: cancel the toggle (or undo it if it already ran).
            if let pending = pendingToggle {
                pending.cancel()
                pendingToggle = nil
            } else if ProcessInfo.processInfo.systemUptime - lastToggleTime < NSEvent.doubleClickInterval {
                toggleHiding()
            }
            openMenu()
        } else {
            // Wait briefly to see if this becomes a double-click. Capped so a single click still feels instant.
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.pendingToggle = nil
                self.lastToggleTime = ProcessInfo.processInfo.systemUptime
                self.toggleHiding()
            }
            pendingToggle?.cancel()
            pendingToggle = work
            DispatchQueue.main.asyncAfter(deadline: .now() + min(NSEvent.doubleClickInterval, 0.25), execute: work)
        }
    }

    private func openMenu() {
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
    }

    func menuDidClose(_ menu: NSMenu) {
        // Detach so the next left click reaches statusItemClicked again.
        statusItem.menu = nil
    }

    private func updateIcon() {
        let name = settings.isHiding ? "eye.slash" : "eye"
        let image = NSImage(systemSymbolName: name, accessibilityDescription: settings.isHiding
            ? "Desktop icons hidden" : "Desktop icons visible")
        image?.isTemplate = true
        statusItem.button?.image = image
        statusItem.button?.toolTip = settings.isHiding
            ? "Desktop icons hidden (\(hider.hiddenCount))" : "Desktop icons visible"
    }

    // MARK: Hot key  (⌃⌥⌘H)

    private func updateHotKey() {
        hotKey = nil
        guard settings.hotKeyEnabled else { return }
        hotKey = HotKey(keyCode: kVK_ANSI_H, modifiers: controlKey | optionKey | cmdKey) { [weak self] in
            self?.toggleHiding()
        }
    }

    // MARK: Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let items = hider.scan()
        let counts = Dictionary(grouping: items, by: \.category).mapValues(\.count)
        let enabled = settings.enabledCategories

        let main = item(settings.isHiding ? "Show Desktop Icons" : "Hide Desktop Icons",
                        #selector(toggleHiding), symbol: settings.isHiding ? "eye" : "eye.slash")
        main.keyEquivalent = "h"
        main.keyEquivalentModifierMask = [.control, .option, .command]
        menu.addItem(main)

        let status: String
        if let error = hider.lastError {
            status = "Can't read Desktop: \(error)"
        } else if settings.isHiding {
            status = "\(hider.hiddenCount) of \(items.count) items hidden"
        } else {
            status = "\(items.count) items on Desktop"
        }
        menu.addItem(disabled(status))

        menu.addItem(.separator())
        menu.addItem(header("What to Hide"))

        // Common path up front, the fine-grained choices one level deeper.
        let isEverything = enabled == Set(Category.allCases)

        let everything = item("Everything", #selector(selectEverything), symbol: "square.stack.3d.up.slash")
        everything.state = isEverything ? .on : .off
        menu.addItem(everything)

        let types = NSMenu()
        types.addItem(header("File Types"))
        for category in Category.allCases {
            let count = counts[category] ?? 0
            let mi = item("\(category.title)  (\(count))", #selector(toggleCategory(_:)), symbol: category.symbol)
            mi.representedObject = category.rawValue
            mi.state = enabled.contains(category) ? .on : .off
            types.addItem(mi)
        }

        types.addItem(.separator())
        types.addItem(header("Quick Picks"))
        types.addItem(presetItem("Only Folders", [.folders]))
        types.addItem(presetItem("Only Files (keep folders visible)",
                                 Set(Category.allCases).subtracting([.folders])))
        types.addItem(presetItem("Only Screenshots & Recordings", [.screenshots]))
        types.addItem(presetItem("Only Photos, Screenshots & Videos", [.images, .screenshots, .media]))
        types.addItem(presetItem("Everything except Apps & Aliases",
                                 Set(Category.allCases).subtracting([.apps])))

        let chooser = item("Choose Types", nil, symbol: "line.3.horizontal.decrease.circle")
        chooser.state = isEverything ? .off : .on
        chooser.submenu = types
        if #available(macOS 14.4, *), !isEverything { chooser.subtitle = summary(of: enabled) }
        menu.addItem(chooser)

        let drives = item("Also Hide Disks & Servers", #selector(toggleDrives), symbol: "externaldrive")
        drives.state = settings.hideDrives ? .on : .off
        drives.toolTip = "Uses Finder's own setting. Finder relaunches when this changes."
        menu.addItem(drives)

        menu.addItem(.separator())
        menu.addItem(header("Options"))
        menu.addItem(option("Auto-hide new items (screenshots, downloads…)", settings.autoHideNew,
                            #selector(toggleAutoHide)))
        menu.addItem(option("Global shortcut ⌃⌥⌘H", settings.hotKeyEnabled, #selector(toggleHotKey)))
        menu.addItem(option("Click icon to hide · double-click for menu", settings.clickToToggle,
                            #selector(toggleClickMode)))
        menu.addItem(option("Show icons again when quitting", settings.restoreOnQuit,
                            #selector(toggleRestoreOnQuit)))
        menu.addItem(option("Launch at login", SMAppService.mainApp.status == .enabled,
                            #selector(toggleLaunchAtLogin)))

        menu.addItem(.separator())
        menu.addItem(item("Open Desktop Folder", #selector(openDesktop), symbol: "folder"))
        menu.addItem(disabled("HideDesktop — free & open source"))
        let quit = item("Quit HideDesktop", #selector(quit), symbol: "power")
        quit.keyEquivalent = "q"
        menu.addItem(quit)
    }

    private func item(_ title: String, _ action: Selector?, symbol: String? = nil) -> NSMenuItem {
        let mi = NSMenuItem(title: title, action: action, keyEquivalent: "")
        mi.target = self
        if let symbol { mi.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) }
        return mi
    }

    /// "Folders, Screenshots & Recordings +2" style summary for the Choose Types row.
    private func summary(of enabled: Set<Category>) -> String {
        let picked = Category.allCases.filter(enabled.contains).map(\.title)
        guard !picked.isEmpty else { return "Nothing selected" }
        let shown = picked.prefix(2).joined(separator: ", ")
        return picked.count > 2 ? "\(shown) +\(picked.count - 2)" : shown
    }

    private func option(_ title: String, _ on: Bool, _ action: Selector) -> NSMenuItem {
        let mi = item(title, action)
        mi.state = on ? .on : .off
        return mi
    }

    private func presetItem(_ title: String, _ categories: Set<Category>) -> NSMenuItem {
        let mi = item(title, #selector(applyPreset(_:)))
        mi.representedObject = categories.map(\.rawValue)
        mi.state = settings.enabledCategories == categories ? .on : .off
        return mi
    }

    private func disabled(_ title: String) -> NSMenuItem {
        let mi = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        mi.isEnabled = false
        return mi
    }

    private func header(_ title: String) -> NSMenuItem {
        if #available(macOS 14.0, *) { return .sectionHeader(title: title) }
        return disabled(title.uppercased())
    }

    // MARK: Actions

    @objc private func toggleHiding() {
        settings.isHiding.toggle()
        // Turning hiding on with nothing selected would do nothing; default to everything.
        if settings.isHiding && settings.enabledCategories.isEmpty && !settings.hideDrives {
            settings.enabledCategories = Set(Category.allCases)
        }
        hider.apply()
    }

    @objc private func selectEverything() {
        settings.enabledCategories = Set(Category.allCases)
        settings.isHiding = true
        hider.apply()
    }

    @objc private func toggleCategory(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let category = Category(rawValue: raw) else { return }
        var enabled = settings.enabledCategories
        if enabled.contains(category) { enabled.remove(category) } else { enabled.insert(category) }
        settings.enabledCategories = enabled
        hider.apply()
    }

    @objc private func applyPreset(_ sender: NSMenuItem) {
        guard let raws = sender.representedObject as? [String] else { return }
        settings.enabledCategories = Set(raws.compactMap(Category.init(rawValue:)))
        settings.isHiding = true
        hider.apply()
    }

    @objc private func toggleDrives() {
        settings.hideDrives.toggle()
        hider.apply()
    }

    @objc private func toggleAutoHide() {
        settings.autoHideNew.toggle()
        if settings.autoHideNew { hider.apply() }
    }

    @objc private func toggleHotKey() {
        settings.hotKeyEnabled.toggle()
        updateHotKey()
    }

    @objc private func toggleClickMode() { settings.clickToToggle.toggle() }

    @objc private func toggleRestoreOnQuit() { settings.restoreOnQuit.toggle() }

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Couldn't change Launch at Login"
            alert.informativeText = "\(error.localizedDescription)\n\nTip: move HideDesktop.app into /Applications first."
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
    }

    @objc private func openDesktop() { NSWorkspace.shared.open(hider.desktop) }

    @objc private func quit() { NSApp.terminate(nil) }

    private func showDesktopAccessAlert() {
        let alert = NSAlert()
        alert.messageText = "HideDesktop can't access your Desktop folder"
        alert.informativeText = "Allow it in System Settings → Privacy & Security → Files & Folders → HideDesktop → Desktop Folder, then try again."
        alert.addButton(withTitle: "Open Privacy Settings")
        alert.addButton(withTitle: "Later")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders") {
            NSWorkspace.shared.open(url)
        }
    }
}
