import AppKit
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Model

final class OnboardingModel: ObservableObject {
    @Published var enabled: Set<Category> {
        didSet { settings.enabledCategories = enabled; applyRealDesktop() }
    }
    @Published var clickToToggle: Bool {
        didSet { settings.clickToToggle = clickToToggle }
    }
    @Published var launchAtLogin: Bool
    @Published private(set) var isHidingReal: Bool

    let counts: [Category: Int]
    private let settings = Settings.shared
    private let applyRealDesktop: () -> Void
    private let toggleRealDesktop: () -> Void

    init(counts: [Category: Int], apply: @escaping () -> Void, toggle: @escaping () -> Void) {
        self.counts = counts
        applyRealDesktop = apply
        toggleRealDesktop = toggle
        enabled = Settings.shared.enabledCategories
        clickToToggle = Settings.shared.clickToToggle
        launchAtLogin = SMAppService.mainApp.status == .enabled
        isHidingReal = Settings.shared.isHiding
    }

    func toggleReal() {
        toggleRealDesktop()
        isHidingReal = settings.isHiding
    }

    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {}
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}

// MARK: - Flow

struct OnboardingView: View {
    @ObservedObject var model: OnboardingModel
    var onDone: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var page = 0
    @State private var forward = true
    @State private var demoHidden = false
    @State private var triedEye = false

    private let pageCount = 3

    var body: some View {
        VStack(spacing: 0) {
            MiniDesktop(hidden: previewHidden, hiddenCategories: previewCategories,
                        pulseEye: page == 0 && !triedEye && !reduceMotion) {
                guard page == 0 else { return }
                triedEye = true
                demoHidden.toggle()
            }
            .frame(height: 230)
            .padding(.horizontal, 24)
            .padding(.top, 38)

            ZStack(alignment: .top) {
                pageContent
                    .id(page)
                    .transition(pageTransition)
            }
            .frame(height: 290, alignment: .top)
            .padding(.horizontal, 40)
            .padding(.top, 24)
            .clipped()

            footer
                .padding(.horizontal, 24)
                .padding(.bottom, 22)
        }
        .frame(width: 600)
        .background(VisualEffect().ignoresSafeArea())
        .tint(.brand)
    }

    // What the mini desktop shows on each step.
    private var previewHidden: Bool {
        switch page {
        case 0: return demoHidden
        case 1: return true
        default: return false
        }
    }

    private var previewCategories: Set<Category> {
        page == 1 ? model.enabled : Set(Category.allCases)
    }

    @ViewBuilder private var pageContent: some View {
        switch page {
        case 0: TryItPage(model: model, triedEye: triedEye)
        case 1: ChooseTypesPage(model: model)
        default: MakeItYoursPage(model: model)
        }
    }

    private var pageTransition: AnyTransition {
        if reduceMotion { return .opacity }
        let inEdge: Edge = forward ? .trailing : .leading
        let outEdge: Edge = forward ? .leading : .trailing
        return .asymmetric(
            insertion: .move(edge: inEdge).combined(with: .opacity),
            removal: .move(edge: outEdge).combined(with: .opacity))
    }

    private func go(to newPage: Int) {
        forward = newPage > page
        withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.42, dampingFraction: 1)) {
            page = newPage
        }
    }

    private var footer: some View {
        HStack {
            Button("Back") { go(to: page - 1) }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .opacity(page == 0 ? 0 : 1)
                .disabled(page == 0)
                .frame(width: 140, alignment: .leading)

            Spacer()
            PageDots(count: pageCount, current: page)
            Spacer()

            Button {
                if page < pageCount - 1 { go(to: page + 1) } else { onDone() }
            } label: {
                Text(page < pageCount - 1 ? "Continue" : "Start Using Bare")
            }
            .buttonStyle(PrimaryButtonStyle())
            .keyboardShortcut(.defaultAction)
            .frame(width: 200, alignment: .trailing)
        }
    }
}

// MARK: - Pages

private struct PageHeader: View {
    var eyebrow: String? = nil
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 8) {
            if let eyebrow {
                Text(eyebrow)
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(1.2)
                    .foregroundStyle(.tint)
            }
            Text(title)
                .font(.system(size: 26, weight: .bold))
                .tracking(-0.4)
            Text(subtitle)
                .font(.system(size: 13.5))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct TryItPage: View {
    @ObservedObject var model: OnboardingModel
    let triedEye: Bool

    var body: some View {
        VStack(spacing: 22) {
            PageHeader(eyebrow: "WELCOME TO BARE", title: "Your Desktop, out of sight.",
                       subtitle: "Click the eye in the menu bar to hide every icon.\nClick it again and they're back. Try it above.")

            HStack(spacing: 10) {
                GestureHint(symbol: "cursorarrow.click", action: "Click", result: "Hide or show")
                GestureHint(symbol: "cursorarrow.click.2", action: "Double-click", result: "Open the menu")
            }

            Button(action: model.toggleReal) {
                Label(model.isHidingReal ? "Bring back my real Desktop" : "Now try it on your real Desktop",
                      systemImage: model.isHidingReal ? "eye" : "eye.slash")
            }
            .buttonStyle(.link)
            .opacity(triedEye || model.isHidingReal ? 1 : 0)
            .animation(.easeOut(duration: 0.25), value: triedEye)
        }
    }
}

private struct GestureHint: View {
    let symbol: String
    let action: String
    let result: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(.tint)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(action).font(.system(size: 12.5, weight: .semibold))
                Text(result).font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .frame(width: 170, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct ChooseTypesPage: View {
    @ObservedObject var model: OnboardingModel
    private let columns = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]

    var body: some View {
        VStack(spacing: 16) {
            PageHeader(title: "Choose what disappears.",
                       subtitle: "Hide everything, or just the clutter. Change it any time from the menu.")

            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(Category.allCases, id: \.self) { category in
                    CategoryCard(category: category, count: model.counts[category] ?? 0,
                                 isOn: model.enabled.contains(category)) {
                        withAnimation(.spring(response: 0.3, dampingFraction: 1)) {
                            if model.enabled.contains(category) {
                                model.enabled.remove(category)
                            } else {
                                model.enabled.insert(category)
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct CategoryCard: View {
    let category: Category
    let count: Int
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(nsImage: FileIcons.icon(for: category))
                    .resizable()
                    .frame(width: 20, height: 20)
                Text(category.shortTitle)
                    .font(.system(size: 12.5, weight: .medium))
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text("\(count)")
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(.secondary)
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 15))
                    .foregroundStyle(isOn ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
            }
            .padding(.horizontal, 11)
            .frame(height: 34)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(isOn ? AnyShapeStyle(Color.brand.opacity(0.12)) : AnyShapeStyle(.quaternary.opacity(0.5))))
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(isOn ? Color.brand.opacity(0.45) : .clear, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
    }
}

private struct MakeItYoursPage: View {
    @ObservedObject var model: OnboardingModel

    var body: some View {
        VStack(spacing: 16) {
            PageHeader(title: "Make it yours.",
                       subtitle: "A few small choices. All of them live in the menu later.")

            VStack(spacing: 0) {
                SettingRow(symbol: "keyboard", title: "Keyboard shortcut", detail: "Hide or show from any app") {
                    ShortcutRecorder(compact: true)
                }
                Divider().padding(.leading, 46)
                SettingRow(symbol: "cursorarrow.click", title: "Single-click to hide",
                           detail: "Double-click the eye opens the menu") {
                    Toggle("", isOn: $model.clickToToggle).toggleStyle(.switch).labelsHidden()
                }
                Divider().padding(.leading, 46)
                SettingRow(symbol: "power", title: "Launch at login", detail: "Keep your Desktop clean after restarts") {
                    Toggle("", isOn: Binding(get: { model.launchAtLogin }, set: model.setLaunchAtLogin))
                        .toggleStyle(.switch).labelsHidden()
                }
            }
            .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            Label("Nothing is ever moved or deleted. Bare only flips macOS's own “hidden” flag.",
                  systemImage: "lock.shield")
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
        }
    }
}

private struct SettingRow<Trailing: View>: View {
    let symbol: String
    let title: String
    let detail: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(Color.brand.gradient, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 13, weight: .medium))
                Text(detail).font(.system(size: 11.5)).foregroundStyle(.secondary)
            }
            Spacer()
            trailing
        }
        .padding(.horizontal, 10)
        .frame(height: 50)
    }
}

// MARK: - Mini desktop preview

/// A small, live mock of a Mac Desktop using the real system file icons.
private struct MiniDesktop: View {
    let hidden: Bool
    let hiddenCategories: Set<Category>
    let pulseEye: Bool
    let onEye: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct Item: Identifiable {
        let id: String
        let type: UTType
        let category: Category
    }

    private static let items: [Item] = [
        Item(id: "Projects", type: .folder, category: .folders),
        Item(id: "Screenshot 1", type: .png, category: .screenshots),
        Item(id: "Vacation.jpg", type: .jpeg, category: .images),
        Item(id: "Invoices", type: .folder, category: .folders),
        Item(id: "Screenshot 2", type: .png, category: .screenshots),
        Item(id: "Demo.mov", type: .quickTimeMovie, category: .media),
        Item(id: "Old Stuff", type: .folder, category: .folders),
        Item(id: "Report.pdf", type: .pdf, category: .documents),
        Item(id: "Installer.dmg", type: .diskImage, category: .archives),
    ]

    var body: some View {
        ZStack(alignment: .top) {
            Wallpaper()

            // Icons stack in columns from the top-right, like Finder does.
            HStack(alignment: .top, spacing: 4) {
                Spacer()
                ForEach(0..<3) { column in
                    VStack(spacing: 4) {
                        ForEach(0..<3) { row in
                            let index = (2 - column) * 3 + row
                            icon(Self.items[index], index: index)
                        }
                    }
                }
            }
            .padding(.top, 34)
            .padding(.trailing, 12)

            MenuBarMock(hidden: hidden, pulse: pulseEye, onEye: onEye)
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.black.opacity(0.12), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.18), radius: 14, y: 6)
    }

    private func icon(_ item: Item, index: Int) -> some View {
        let isHidden = hidden && hiddenCategories.contains(item.category)
        return VStack(spacing: 2) {
            Image(nsImage: NSWorkspace.shared.icon(for: item.type))
                .resizable()
                .frame(width: 38, height: 38)
                .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
            Text(item.id)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.6), radius: 1.5, y: 0.5)
                .lineLimit(1)
        }
        .frame(width: 70, height: 60)
        .scaleEffect(isHidden ? 0.55 : 1)
        .blur(radius: isHidden && !reduceMotion ? 6 : 0)
        .opacity(isHidden ? 0 : 1)
        .animation(reduceMotion
                   ? .easeOut(duration: 0.2)
                   : .spring(response: 0.38, dampingFraction: 1).delay(Double(index) * 0.025),
                   value: isHidden)
    }
}

private struct MenuBarMock: View {
    let hidden: Bool
    let pulse: Bool
    let onEye: () -> Void
    @State private var ring = false

    var body: some View {
        HStack(spacing: 13) {
            Image(systemName: "apple.logo").font(.system(size: 11, weight: .semibold))
            Text("Finder").font(.system(size: 11, weight: .bold))
            ForEach(["File", "Edit", "View", "Go"], id: \.self) {
                Text($0).font(.system(size: 11))
            }
            Spacer()

            Button(action: onEye) {
                ZStack {
                    if pulse {
                        Circle()
                            .stroke(.white.opacity(0.9), lineWidth: 1.5)
                            .frame(width: 22, height: 22)
                            .scaleEffect(ring ? 1.7 : 0.9)
                            .opacity(ring ? 0 : 0.9)
                            .animation(.easeOut(duration: 1.3).repeatForever(autoreverses: false), value: ring)
                            .onAppear { ring = true }
                    }
                    Image(systemName: hidden ? "eye.slash" : "eye")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 26, height: 18)
                        .background(.white.opacity(pulse ? 0.25 : 0), in: RoundedRectangle(cornerRadius: 4))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle())
            .help("Click to try it")

            Image(systemName: "wifi").font(.system(size: 11, weight: .semibold))
            Text("9:41").font(.system(size: 11, weight: .medium)).monospacedDigit()
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .frame(height: 24)
        .background(.black.opacity(0.18))
        .background(.ultraThinMaterial.opacity(0.6))
    }
}

/// A soft macOS-style wallpaper built from layered gradients.
private struct Wallpaper: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.22, green: 0.20, blue: 0.55), Color(red: 0.55, green: 0.25, blue: 0.55)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            RadialGradient(colors: [Color(red: 1.0, green: 0.55, blue: 0.35).opacity(0.85), .clear],
                           center: UnitPoint(x: 0.15, y: 1.0), startRadius: 0, endRadius: 330)
            RadialGradient(colors: [Color(red: 0.30, green: 0.65, blue: 1.0).opacity(0.7), .clear],
                           center: UnitPoint(x: 0.9, y: 0.0), startRadius: 0, endRadius: 300)
            RadialGradient(colors: [Color(red: 0.95, green: 0.35, blue: 0.6).opacity(0.55), .clear],
                           center: UnitPoint(x: 0.55, y: 0.75), startRadius: 0, endRadius: 220)
        }
    }
}

// MARK: - Bits

extension Color {
    /// Bare's lilac. Deeper in light mode so white button text stays readable, softer in dark mode.
    static let brand = Color(nsColor: NSColor(name: "BareLilac") { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 0.69, green: 0.58, blue: 1.0, alpha: 1)   // #B094FF
            : NSColor(srgbRed: 0.55, green: 0.39, blue: 0.90, alpha: 1)  // #8C63E6
    })
}

private struct PageDots: View {
    let count: Int
    let current: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { i in
                Capsule()
                    .fill(i == current ? AnyShapeStyle(Color.brand) : AnyShapeStyle(.tertiary))
                    .frame(width: i == current ? 18 : 6, height: 6)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 1), value: current)
    }
}

/// The filled lilac call-to-action. Stays lilac even when the window isn't focused.
struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13.5, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 20)
            .frame(height: 36)
            .background(Color.brand.gradient, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .shadow(color: Color.brand.opacity(configuration.isPressed ? 0.2 : 0.4),
                    radius: configuration.isPressed ? 2 : 7, y: configuration.isPressed ? 1 : 3)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .brightness(configuration.isPressed ? -0.06 : 0)
            .animation(.spring(response: 0.2, dampingFraction: 1), value: configuration.isPressed)
            .contentShape(Rectangle())
    }
}

/// Secondary lilac button: tinted text on a soft lilac fill.
struct TintedButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Color.brand)
            .padding(.horizontal, 12)
            .frame(height: 28)
            .background(Color.brand.opacity(configuration.isPressed ? 0.24 : 0.14),
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.2, dampingFraction: 1), value: configuration.isPressed)
            .contentShape(Rectangle())
    }
}

/// Instant press feedback: shrinks on mouse-down, springs back on release.
private struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.2, dampingFraction: 1), value: configuration.isPressed)
    }
}

private struct VisualEffect: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .underWindowBackground
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

enum FileIcons {
    static func icon(for category: Category) -> NSImage {
        let type: UTType
        switch category {
        case .folders: type = .folder
        case .screenshots: type = .png
        case .images: type = .jpeg
        case .media: type = .quickTimeMovie
        case .documents: type = .pdf
        case .archives: type = .diskImage
        case .apps: type = .applicationBundle
        case .other: type = .data
        }
        return NSWorkspace.shared.icon(for: type)
    }
}
