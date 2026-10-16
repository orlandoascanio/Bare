import Foundation

/// The kinds of Desktop items you can choose to hide.
enum Category: String, CaseIterable {
    case folders
    case screenshots
    case images
    case media
    case documents
    case archives
    case apps
    case other

    var title: String {
        switch self {
        case .folders: return "Folders"
        case .screenshots: return "Screenshots & Recordings"
        case .images: return "Images & Photos"
        case .media: return "Videos & Audio"
        case .documents: return "Documents"
        case .archives: return "Archives, DMGs & Installers"
        case .apps: return "Apps & Aliases"
        case .other: return "Other Files"
        }
    }

    var symbol: String {
        switch self {
        case .folders: return "folder"
        case .screenshots: return "camera.viewfinder"
        case .images: return "photo"
        case .media: return "film"
        case .documents: return "doc.text"
        case .archives: return "archivebox"
        case .apps: return "app.badge"
        case .other: return "doc"
        }
    }
}

/// Persistent preferences, stored in the app's own UserDefaults domain.
final class Settings {
    static let shared = Settings()
    private let d = UserDefaults.standard

    private init() {
        d.register(defaults: [
            "isHiding": false,
            "enabledCategories": Category.allCases.map(\.rawValue),
            "hideDrives": false,
            "autoHideNew": true,
            "restoreOnQuit": true,
            "clickToToggle": false,
            "hotKeyEnabled": true,
        ])
    }

    var isHiding: Bool {
        get { d.bool(forKey: "isHiding") }
        set { d.set(newValue, forKey: "isHiding") }
    }

    var enabledCategories: Set<Category> {
        get { Set((d.stringArray(forKey: "enabledCategories") ?? []).compactMap(Category.init(rawValue:))) }
        set { d.set(newValue.map(\.rawValue).sorted(), forKey: "enabledCategories") }
    }

    /// Hide hard disks, external drives, removable media and servers (needs a Finder relaunch).
    var hideDrives: Bool {
        get { d.bool(forKey: "hideDrives") }
        set { d.set(newValue, forKey: "hideDrives") }
    }

    var autoHideNew: Bool {
        get { d.bool(forKey: "autoHideNew") }
        set { d.set(newValue, forKey: "autoHideNew") }
    }

    var restoreOnQuit: Bool {
        get { d.bool(forKey: "restoreOnQuit") }
        set { d.set(newValue, forKey: "restoreOnQuit") }
    }

    var clickToToggle: Bool {
        get { d.bool(forKey: "clickToToggle") }
        set { d.set(newValue, forKey: "clickToToggle") }
    }

    var hotKeyEnabled: Bool {
        get { d.bool(forKey: "hotKeyEnabled") }
        set { d.set(newValue, forKey: "hotKeyEnabled") }
    }

    // MARK: Internal bookkeeping

    /// Names of Desktop items *this app* hid, so we only ever un-hide those
    /// and never touch items you hid yourself.
    var trackedNames: Set<String> {
        get { Set(d.stringArray(forKey: "trackedNames") ?? []) }
        set { d.set(newValue.sorted(), forKey: "trackedNames") }
    }

    var drivesHiddenByUs: Bool {
        get { d.bool(forKey: "drivesHiddenByUs") }
        set { d.set(newValue, forKey: "drivesHiddenByUs") }
    }

    /// Finder's original drive settings, saved before we changed them.
    var savedDriveValues: [String: Bool] {
        get { (d.dictionary(forKey: "savedDriveValues") as? [String: Bool]) ?? [:] }
        set { d.set(newValue, forKey: "savedDriveValues") }
    }
}
