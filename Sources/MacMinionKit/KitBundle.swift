import Foundation

/// Finder for the kit string catalog. Prefer `Bundle.kit` over SPM's `Bundle.module`.
///
/// CI `swift build` embeds a native SPM accessor that only probes
/// `Bundle.main.bundleURL/MacMinion_MacMinionKit.bundle` (the app root). That path cannot be
/// sealed by codesign (`unsealed contents present in the bundle root`). `build.sh` installs the
/// catalog under `Contents/Resources`, which this locator uses.
enum KitBundle {
    static let name = "MacMinion_MacMinionKit.bundle"

    static let bundle: Bundle = {
        let candidates: [URL?] = [
            Bundle.main.resourceURL?.appending(path: name),
            Bundle(for: BundleFinder.self).resourceURL?.appending(path: name),
            Bundle.main.bundleURL.appending(path: name),
        ]
        for url in candidates.compactMap({ $0 }) {
            if let bundle = Bundle(url: url) { return bundle }
        }
        // Last resort: SPM's generated accessor (works next to the scratch binary during `swift test`).
        return Bundle.module
    }()
}

private final class BundleFinder: NSObject {}

extension Bundle {
    /// MacMinionKit localized strings. Use instead of `Bundle.module` in kit code.
    public static var kit: Bundle { KitBundle.bundle }
}
