import AppKit
import Carbon.HIToolbox
import ServiceManagement
import SwiftUI

enum Links {
    static let website = URL(string: "https://www.orlandoascanio.com/products/hidedesktop")!
}

// MARK: - Window presenting

/// Shows small SwiftUI windows from a menu bar-only app.
enum WindowPresenter {
    private static var windows: [String: NSWindow] = [:]

    static func show<Content: View>(id: String, title: String, @ViewBuilder content: () -> Content) {
        if let window = windows[id] {
            bringToFront(window)
            return
        }
        let host = NSHostingController(rootView: content())
        host.sizingOptions = [.preferredContentSize]
        let window = NSWindow(contentViewController: host)
        window.title = title
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.center()
        windows[id] = window
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window,
                                               queue: .main) { _ in windows[id] = nil }
        bringToFront(window)
    }

    static func close(id: String) { windows[id]?.close() }

    private static func bringToFront(_ window: NSWindow) {
        if #available(macOS 14.0, *) { NSApp.activate() } else { NSApp.activate(ignoringOtherApps: true) }
        window.makeKeyAndOrderFront(nil)
    }
}

// MARK: - Shortcut recorder

final class ShortcutRecorderModel: ObservableObject {
    @Published private(set) var shortcut = HotKeyManager.shared.shortcut
    @Published private(set) var isRecording = false
    @Published private(set) var liveModifiers = ""
    @Published private(set) var message: String?
    private var monitor: Any?

    func toggle() { isRecording ? stop() : start() }

    func start() {
        guard !isRecording else { return }
        isRecording = true
        message = nil
        liveModifiers = ""
        HotKeyManager.shared.pause()
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            self?.handle(event)
            return nil
        }
    }

    func stop() {
        guard isRecording else { return }
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        isRecording = false
        liveModifiers = ""
        HotKeyManager.shared.reload()
    }

    func clear() {
        stop()
        HotKeyManager.shared.set(nil)
        shortcut = nil
        message = nil
    }

    private func handle(_ event: NSEvent) {
        if event.type == .flagsChanged {
            liveModifiers = Shortcut.symbols(forCarbon: Shortcut.carbon(from: event.modifierFlags))
            return
        }
        if Int(event.keyCode) == kVK_Escape && Shortcut.carbon(from: event.modifierFlags) == 0 {
            stop()
            return
        }
        guard let new = Shortcut(event: event) else {
            message = "Include ⌘, ⌥ or ⌃ in the shortcut."
            NSSound.beep()
            return
        }
        if HotKeyManager.shared.set(new) {
            shortcut = new
            message = nil
            stop()
        } else {
            message = "\(new.display) can't be used. Try another."
            NSSound.beep()
        }
    }

    deinit {
        if let monitor { NSEvent.removeMonitor(monitor) }
    }
}

struct ShortcutRecorder: View {
    @StateObject private var model = ShortcutRecorderModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Button(action: model.toggle) {
                    Text(label)
                        .monospacedDigit()
                        .foregroundStyle(model.isRecording && model.liveModifiers.isEmpty ? .secondary : .primary)
                        .frame(minWidth: 120)
                }
                .controlSize(.large)

                if model.shortcut != nil && !model.isRecording {
                    Button(action: model.clear) {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .help("Turn off the shortcut")
                }
            }
            Group {
                if let message = model.message {
                    Text(message).foregroundStyle(.red)
                } else if model.isRecording {
                    Text("Press the new keys · Esc to cancel").foregroundStyle(.secondary)
                } else {
                    Text(model.shortcut == nil ? "No shortcut set" : "Click to change").foregroundStyle(.secondary)
                }
            }
            .font(.caption)
        }
        .onDisappear { model.stop() }
    }

    private var label: String {
        if model.isRecording { return model.liveModifiers.isEmpty ? "Type shortcut…" : model.liveModifiers }
        return model.shortcut?.display ?? "Record Shortcut"
    }
}

struct ShortcutSettingsView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "keyboard")
                .font(.system(size: 34, weight: .regular))
                .foregroundStyle(.tint)
            VStack(spacing: 4) {
                Text("Keyboard Shortcut").font(.title3.weight(.semibold))
                Text("Hide or show Desktop icons from any app.")
                    .foregroundStyle(.secondary)
            }
            ShortcutRecorder()
        }
        .padding(.horizontal, 36)
        .padding(.top, 34)
        .padding(.bottom, 26)
        .frame(width: 340)
    }
}

// MARK: - Onboarding

struct OnboardingView: View {
    var onDone: () -> Void
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                Image(systemName: "eye.slash.circle.fill")
                    .font(.system(size: 60))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.tint)
                Text("Welcome to HideDesktop")
                    .font(.system(size: 26, weight: .bold))
                    .tracking(-0.3)
                Text("A clean Desktop, one click away. Free and open source.")
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 26)

            VStack(alignment: .leading, spacing: 18) {
                TipRow(symbol: "cursorarrow.click", title: "Click the eye in the menu bar",
                       detail: "Hides your Desktop icons. Click again to bring them back.")
                TipRow(symbol: "cursorarrow.click.2", title: "Double-click for the menu",
                       detail: "Pick what to hide: folders, screenshots, photos and more. Right-click works too.")
                TipRow(symbol: "keyboard", title: "Or press a shortcut, from any app",
                       detail: nil) {
                    ShortcutRecorder().padding(.top, 4)
                }
                TipRow(symbol: "lock.shield", title: "Your files stay where they are",
                       detail: "Nothing is moved or deleted. If macOS asks for access to your Desktop folder, click Allow.")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 24)

            Divider().padding(.bottom, 16)

            HStack {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin, perform: setLaunchAtLogin)
                Spacer()
                Link("Website", destination: Links.website)
                    .padding(.trailing, 8)
                Button("Get Started", action: onDone)
                    .keyboardShortcut(.defaultAction)
                    .controlSize(.large)
            }
        }
        .padding(.horizontal, 36)
        .padding(.top, 40)
        .padding(.bottom, 24)
        .frame(width: 480)
    }

    private func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}

private struct TipRow<Accessory: View>: View {
    let symbol: String
    let title: String
    let detail: String?
    @ViewBuilder var accessory: Accessory

    init(symbol: String, title: String, detail: String?, @ViewBuilder accessory: () -> Accessory = { EmptyView() }) {
        self.symbol = symbol
        self.title = title
        self.detail = detail
        self.accessory = accessory()
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 20))
                .foregroundStyle(.tint)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                if let detail {
                    Text(detail)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                accessory
            }
        }
    }
}
