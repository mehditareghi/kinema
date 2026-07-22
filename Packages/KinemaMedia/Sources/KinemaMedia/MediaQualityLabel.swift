import Foundation

public enum MediaQualityLabel {
    /// VLC-style quality badges based on the shorter display axis (handles anamorphic sizes).
    public static func make(width: Int, height: Int) -> String? {
        guard width > 0, height > 0 else { return nil }

        let shortSide = min(width, height)
        let longSide = max(width, height)

        if shortSide >= 2160 || longSide >= 3840 {
            return "4K"
        }
        if shortSide >= 1080 || longSide >= 1920 {
            return "1080p"
        }
        if shortSide >= 720 || longSide >= 1280 {
            return "HD"
        }
        if shortSide >= 576 {
            return "SD"
        }
        if shortSide >= 480 {
            return "480p"
        }
        return nil
    }
}
