import Foundation

extension GameSettingsFile {
    /// Hover help for a Game Settings row when MacMinion knows the key. Nil for unknown keys.
    /// Localized strings are resolved once and reused so large AddOnSettings forms do not re-localize on every body pass.
    public static func help(for field: Field, kind: Kind) -> String? {
        if kind == .addOns, field.section != nil {
            return TipCache.string(id: "addon-row",
                                   "Loads this addon for this character (or Default). Off keeps it installed but not loaded.")
        }
        switch field.key {
        case "LastRealm":
            return TipCache.string(id: field.key, "Which megaserver the client last used: NA Megaserver, EU Megaserver, or PTS.")
        case "Language.2":
            return TipCache.string(id: field.key, "Client UI language (en, de, fr, es, ru, jp, zh). The game may overwrite this while running.")
        case "LastValidLanguage":
            return TipCache.string(id: field.key, "Last language the client accepted as valid. Usually matches Language.2.")
        case "LastPlatformLanguage":
            return TipCache.string(id: field.key, "Language last reported from the platform or launcher.")
        case "Version":
            return TipCache.string(id: field.key, "API version this AddOnSettings.txt was written under. Pick the update name that matches your game build.")
        case "AcknowledgedOutOfDateAddonsVersion":
            return TipCache.string(id: field.key, "API version for which you last dismissed the out-of-date addons warning.")
        case "AddOnsEnabled":
            return TipCache.string(id: field.key, "Master switch for loading addons. Off loads none, even if a character's list is on.")
        case "USE_BACKGROUND_FPS_LIMIT":
            return TipCache.string(id: field.key, "On: cap frame rate while the game is in the background. Off: uncapped in the background (uses more power).")
        case "BACKGROUND_FPS_LIMIT":
            return TipCache.string(id: field.key, "Target FPS while in the background when USE_BACKGROUND_FPS_LIMIT is on.")
        case "MinFrameTime.2":
            return TipCache.string(id: field.key, "Minimum seconds per frame (about 1 ÷ target FPS). Example: 0.01 ≈ 100 FPS, 0.0167 ≈ 60 FPS.")
        case "VSYNC":
            return TipCache.string(id: field.key, "On: sync frames to the display refresh to reduce tearing. Off: uncapped by vsync (can tear).")
        case "VSYNC_INTERVAL":
            return TipCache.string(id: field.key, "How many refresh intervals per frame when VSYNC is on (1 = every refresh, 2 = half rate).")
        case "FULLSCREEN":
            return TipCache.string(id: field.key, "On: run full screen. Off: windowed. Pair with PreferExclusiveFullscreen and PreferMaximizedWindow.")
        case "PreferExclusiveFullscreen":
            return TipCache.string(id: field.key, "On: prefer exclusive full screen when FULLSCREEN is on. Off: prefer borderless where available.")
        case "PreferMaximizedWindow":
            return TipCache.string(id: field.key, "On: prefer a maximized window when not in exclusive full screen.")
        case "FullscreenWidth":
            return TipCache.string(id: field.key, "Horizontal resolution in full-screen mode (pixels).")
        case "FullscreenHeight":
            return TipCache.string(id: field.key, "Vertical resolution in full-screen mode (pixels).")
        case "WindowedWidth":
            return TipCache.string(id: field.key, "Window width when not full screen (pixels).")
        case "WindowedHeight":
            return TipCache.string(id: field.key, "Window height when not full screen (pixels).")
        case "ScreenshotFormat.2":
            return TipCache.string(id: field.key, "File format for screenshots (for example PNG or JPG), as the client writes it.")
        case "ANTIALIASING_TYPE":
            return TipCache.string(id: field.key, "Anti-aliasing method index the client uses. Higher quality usually costs more GPU time.")
        case "FSR_MODE":
            return TipCache.string(id: field.key, "AMD FidelityFX Super Resolution mode. 0 is typically off; higher values are stronger upscaling presets.")
        case "DLSS_MODE":
            return TipCache.string(id: field.key, "NVIDIA DLSS mode when supported. 0 is typically off; higher values are stronger upscaling presets.")
        case "SHADOWS":
            return TipCache.string(id: field.key, "Shadow quality level. Higher values look sharper and cost more GPU time.")
        case "HDR_ENABLED":
            return TipCache.string(id: field.key, "On: use HDR output when the display supports it. Off: standard dynamic range.")
        case "InvertMouseY":
            return TipCache.string(id: field.key, "On: invert vertical look. Off: normal vertical look.")
        case "InvertMouseX":
            return TipCache.string(id: field.key, "On: invert horizontal look. Off: normal horizontal look.")
        case "InvertMouseWheel":
            return TipCache.string(id: field.key, "On: invert mouse-wheel zoom direction. Off: normal zoom.")
        case "AUDIO_ENABLED":
            return TipCache.string(id: field.key, "Master audio on/off for the client.")
        case "MUSIC_ENABLED":
            return TipCache.string(id: field.key, "On: play game music. Off: mute music only.")
        case "BACKGROUND_AUDIO":
            return TipCache.string(id: field.key, "On: keep playing audio while the game is in the background. Off: silence in the background.")
        case "SubtitlesForVideosEnabled":
            return TipCache.string(id: field.key, "On: show subtitles for cinematics and videos. Off: hide them.")
        case "SUBTITLES_ENABLED":
            return TipCache.string(id: field.key, "On: show subtitles. Off: hide them.")
        case "TerrainShadowsEnabled":
            return TipCache.string(id: field.key, "On: draw terrain shadows. Off: skip them (faster, flatter lighting).")
        case "OverlaysEnabled":
            return TipCache.string(id: field.key, "On: enable renderer overlays. Off: disable them.")
        case "PPFXOverlaysEnabled":
            return TipCache.string(id: field.key, "On: enable post-process effect overlays. Off: disable them.")
        case "RLSEnabled":
            return TipCache.string(id: field.key, "On: enable the RLS renderer feature. Off: disable it.")
        case "COLOR_PICKER":
            return TipCache.string(id: field.key, "Renderer color-picker flag used by the client (0 or 1 as written in MachineSettings).")
        case "BlobShadowsEnabled":
            return TipCache.string(id: field.key, "On: draw simple blob shadows under characters. Off: no blob shadows.")
        case "RESOLUTION":
            return TipCache.string(id: field.key, "Display resolution as width×height (for example 5120x1440). The game may overwrite this while running.")
        default:
            return nil
        }
    }
}

/// Localized tip strings, resolved once per id so Form body passes do not pay String Catalog lookup again.
private final class TipCache: @unchecked Sendable {
    static let shared = TipCache()
    private let lock = NSLock()
    private var strings: [String: String] = [:]

    static func string(id: String, _ key: String.LocalizationValue) -> String {
        shared.string(id: id, key)
    }

    private func string(id: String, _ key: String.LocalizationValue) -> String {
        lock.lock()
        if let cached = strings[id] {
            lock.unlock()
            return cached
        }
        lock.unlock()
        let value = String(localized: key, bundle: .module)
        lock.lock()
        strings[id] = value
        lock.unlock()
        return value
    }
}
