import Foundation
import UniformTypeIdentifiers

enum Classifier {
    static let keys: [URLResourceKey] = [
        .isDirectoryKey, .isPackageKey, .isAliasFileKey, .isSymbolicLinkKey, .contentTypeKey,
    ]

    static func category(of url: URL, values: URLResourceValues) -> Category {
        if values.isAliasFile == true || values.isSymbolicLink == true { return .apps }

        let type = values.contentType
        if let t = type, t.conforms(to: .application) || t.conforms(to: .applicationBundle) {
            return .apps
        }
        if values.isDirectory == true && values.isPackage != true { return .folders }
        if isScreenCapture(url) { return .screenshots }

        guard let t = type else { return .other }
        if t.conforms(to: .image) { return .images }
        if t.conforms(to: .audiovisualContent) { return .media }
        if t.conforms(to: .archive) || t.conforms(to: .diskImage)
            || t.identifier == "com.apple.installer-package-archive" {
            return .archives
        }
        if t.conforms(to: .content) || t.conforms(to: .compositeContent) || t.conforms(to: .text) {
            return .documents
        }
        return .other
    }

    private static let screenCapturePrefixes = [
        "Screenshot", "Screen Shot", "Screen Recording",
        "Simulator Screenshot", "Simulator Screen Recording", "CleanShot",
    ]

    /// macOS tags screenshots/recordings with a metadata xattr; fall back to the default file names.
    static func isScreenCapture(_ url: URL) -> Bool {
        let size = url.withUnsafeFileSystemRepresentation { path -> Int in
            guard let path else { return -1 }
            return getxattr(path, "com.apple.metadata:kMDItemIsScreenCapture", nil, 0, 0, XATTR_NOFOLLOW)
        }
        if size >= 0 { return true }
        let name = url.lastPathComponent
        return screenCapturePrefixes.contains { name.hasPrefix($0) }
    }
}
