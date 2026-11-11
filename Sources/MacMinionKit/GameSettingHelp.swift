import Foundation

extension GameSettingsFile {
    /// Hover help for a Game Settings row when MacMinion knows the key. Nil for unknown keys.
    public static func help(for field: Field, kind: Kind) -> String? {
        if kind == .addOns, field.section != nil {
            return L("Loads this addon for this character (or Default). Off keeps it installed but not loaded.")
        }
        switch field.key {
        case "LastRealm":
            return L("Which megaserver the client last used: NA Megaserver, EU Megaserver, or PTS.")
        case "Language.2":
            return L("Client UI language (en, de, fr, es, ru, jp, zh). The game may overwrite this while running.")
        case "LastValidLanguage":
            return L("Last language the client accepted as valid. Usually matches Language.2.")
        case "LastPlatformLanguage":
            return L("Language last reported from the platform or launcher.")
        case "Version":
            return L("API version this AddOnSettings.txt was written under. Pick the update name that matches your game build.")
        case "AcknowledgedOutOfDateAddonsVersion":
            return L("API version for which you last dismissed the out-of-date addons warning.")
        case "AddOnsEnabled":
            return L("Master switch for loading addons. Off loads none, even if a character's list is on.")
        case "USE_BACKGROUND_FPS_LIMIT":
            return L("On: cap frame rate while the game is in the background. Off: uncapped in the background (uses more power).")
        case "BACKGROUND_FPS_LIMIT":
            return L("Target FPS while in the background when USE_BACKGROUND_FPS_LIMIT is on.")
        case "MinFrameTime.2":
            return L("Minimum seconds per frame (about 1 ÷ target FPS). Example: 0.01 ≈ 100 FPS, 0.0167 ≈ 60 FPS.")
        case "VSYNC":
            return L("On: sync frames to the display refresh to reduce tearing. Off: uncapped by vsync (can tear).")
        case "VSYNC_INTERVAL":
            return L("How many refresh intervals per frame when VSYNC is on (1 = every refresh, 2 = half rate).")
        case "FULLSCREEN":
            return L("On: run full screen. Off: windowed. Pair with PreferExclusiveFullscreen and PreferMaximizedWindow.")
        case "PreferExclusiveFullscreen":
            return L("On: prefer exclusive full screen when FULLSCREEN is on. Off: prefer borderless where available.")
        case "PreferMaximizedWindow":
            return L("On: prefer a maximized window when not in exclusive full screen.")
        case "FullscreenWidth":
            return L("Horizontal resolution in full-screen mode (pixels).")
        case "FullscreenHeight":
            return L("Vertical resolution in full-screen mode (pixels).")
        case "WindowedWidth":
            return L("Window width when not full screen (pixels).")
        case "WindowedHeight":
            return L("Window height when not full screen (pixels).")
        case "ScreenshotFormat.2":
            return L("File format for screenshots (for example PNG or JPG), as the client writes it.")
        case "ANTIALIASING_TYPE":
            return L("Anti-aliasing method index the client uses. Higher quality usually costs more GPU time.")
        case "FSR_MODE":
            return L("AMD FidelityFX Super Resolution mode. 0 is typically off; higher values are stronger upscaling presets.")
        case "DLSS_MODE":
            return L("NVIDIA DLSS mode when supported. 0 is typically off; higher values are stronger upscaling presets.")
        case "SHADOWS":
            return L("Shadow quality level. Higher values look sharper and cost more GPU time.")
        case "HDR_ENABLED":
            return L("On: use HDR output when the display supports it. Off: standard dynamic range.")
        case "InvertMouseY":
            return L("On: invert vertical look. Off: normal vertical look.")
        case "InvertMouseX":
            return L("On: invert horizontal look. Off: normal horizontal look.")
        case "InvertMouseWheel":
            return L("On: invert mouse-wheel zoom direction. Off: normal zoom.")
        case "AUDIO_ENABLED":
            return L("Master audio on/off for the client.")
        case "MUSIC_ENABLED":
            return L("On: play game music. Off: mute music only.")
        case "BACKGROUND_AUDIO":
            return L("On: keep playing audio while the game is in the background. Off: silence in the background.")
        case "SubtitlesForVideosEnabled":
            return L("On: show subtitles for cinematics and videos. Off: hide them.")
        case "SUBTITLES_ENABLED":
            return L("On: show subtitles. Off: hide them.")
        case "TerrainShadowsEnabled":
            return L("On: draw terrain shadows. Off: skip them (faster, flatter lighting).")
        case "OverlaysEnabled":
            return L("On: enable renderer overlays. Off: disable them.")
        case "PPFXOverlaysEnabled":
            return L("On: enable post-process effect overlays. Off: disable them.")
        case "RLSEnabled":
            return L("On: enable the RLS renderer feature. Off: disable it.")
        case "COLOR_PICKER":
            return L("Renderer color-picker flag used by the client (0 or 1 as written in MachineSettings).")
        case "BlobShadowsEnabled":
            return L("On: draw simple blob shadows under characters. Off: no blob shadows.")
        case "RESOLUTION":
            return L("Display resolution as width×height (for example 5120x1440). The game may overwrite this while running.")
        default:
            return nil
        }
    }
}

private func L(_ key: String.LocalizationValue) -> String {
    String(localized: key, bundle: .module)
}
