import Foundation
import CoreText
#if canImport(AppKit) && os(macOS)
import AppKit
#endif
#if canImport(UIKit)
import UIKit
#endif

/// Bundled subtitle fonts + VLC-style system font discovery for mpv/libass.
public enum SubtitleFontRegistry {
    /// Stored preference id for mpv's built-in default (not a family name).
    public static let systemDefaultID = "system"
    public static let vazirmatnFamilyName = "Vazirmatn"

    private static let bundledFontFileNames = [
        "Vazirmatn-Regular.ttf",
        "Vazirmatn-Bold.ttf"
    ]

    private static var didRegister = false

    /// Register bundled fonts with Core Text and expose their directory to mpv.
    @discardableResult
    public static func prepare() -> URL? {
        registerBundledFontsIfNeeded()
        return ensureMPVFontsDirectory()
    }

    public static func registerBundledFontsIfNeeded() {
        guard !didRegister else { return }
        didRegister = true

        for fileName in bundledFontFileNames {
            guard let url = Bundle.module.url(forResource: fileName, withExtension: nil, subdirectory: "Fonts")
                    ?? Bundle.module.url(forResource: fileName.replacingOccurrences(of: ".ttf", with: ""), withExtension: "ttf", subdirectory: "Fonts")
                    ?? Bundle.module.url(forResource: fileName, withExtension: nil) else {
                continue
            }
            var error: Unmanaged<CFError>?
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
        }
    }

    /// Directory of font files for mpv `--sub-fonts-dir` (works without system install).
    public static func ensureMPVFontsDirectory() -> URL? {
        let fm = FileManager.default
        guard let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return bundledFontsDirectoryURL()
        }
        let fontsDir = appSupport
            .appendingPathComponent("Kinema", isDirectory: true)
            .appendingPathComponent("fonts", isDirectory: true)

        do {
            try fm.createDirectory(at: fontsDir, withIntermediateDirectories: true)
            for fileName in bundledFontFileNames {
                guard let source = Bundle.module.url(forResource: fileName, withExtension: nil, subdirectory: "Fonts")
                        ?? Bundle.module.url(forResource: fileName.replacingOccurrences(of: ".ttf", with: ""), withExtension: "ttf", subdirectory: "Fonts")
                        ?? Bundle.module.url(forResource: fileName, withExtension: nil) else {
                    continue
                }
                let destination = fontsDir.appendingPathComponent(fileName)
                if fm.fileExists(atPath: destination.path) {
                    // Refresh if bundle copy is newer / different size.
                    let srcAttrs = try fm.attributesOfItem(atPath: source.path)
                    let dstAttrs = try fm.attributesOfItem(atPath: destination.path)
                    let srcSize = srcAttrs[.size] as? NSNumber
                    let dstSize = dstAttrs[.size] as? NSNumber
                    if srcSize == dstSize { continue }
                    try fm.removeItem(at: destination)
                }
                try fm.copyItem(at: source, to: destination)
            }
            return fontsDir
        } catch {
            return bundledFontsDirectoryURL()
        }
    }

    public static func bundledFontsDirectoryURL() -> URL? {
        if let url = Bundle.module.resourceURL?.appendingPathComponent("Fonts", isDirectory: true),
           FileManager.default.fileExists(atPath: url.path) {
            return url
        }
        // Fallback: directory containing any bundled font file.
        if let file = Bundle.module.url(forResource: "Vazirmatn-Regular", withExtension: "ttf", subdirectory: "Fonts")
            ?? Bundle.module.url(forResource: "Vazirmatn-Regular", withExtension: "ttf") {
            return file.deletingLastPathComponent()
        }
        return nil
    }

    /// VLC-style list: system fonts available to the process, with Vazirmatn guaranteed.
    public static func availableFontFamilies() -> [SubtitleFontOption] {
        registerBundledFontsIfNeeded()

        var families = Set(platformFontFamilies())
        families.insert(vazirmatnFamilyName)

        let sorted = families.sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }

        var options: [SubtitleFontOption] = [
            SubtitleFontOption(
                id: systemDefaultID,
                displayName: "System Default",
                mpvFontName: ""
            )
        ]

        // Keep bundled Vazirmatn near the top for discoverability.
        options.append(
            SubtitleFontOption(
                id: vazirmatnFamilyName,
                displayName: "\(vazirmatnFamilyName) (Bundled)",
                mpvFontName: vazirmatnFamilyName
            )
        )

        for family in sorted where family != vazirmatnFamilyName {
            options.append(
                SubtitleFontOption(
                    id: family,
                    displayName: family,
                    mpvFontName: family
                )
            )
        }
        return options
    }

    public static func resolveStoredFontSelection(_ stored: String) -> SubtitleFontOption {
        let migrated = migrateLegacyFontID(stored)
        let options = availableFontFamilies()
        if migrated.isEmpty || migrated == systemDefaultID {
            return options[0]
        }
        if let match = options.first(where: { $0.id == migrated || $0.mpvFontName == migrated }) {
            return match
        }
        // Keep a custom/unknown family name rather than silently dropping it.
        return SubtitleFontOption(id: migrated, displayName: migrated, mpvFontName: migrated)
    }

    public static func migrateLegacyFontID(_ stored: String) -> String {
        switch stored {
        case "system", "":
            return systemDefaultID
        case "vazirmatn":
            return vazirmatnFamilyName
        case "noto-sans":
            return "Noto Sans"
        case "noto-sans-arabic":
            return "Noto Sans Arabic"
        case "roboto":
            return "Roboto"
        case "open-sans":
            return "Open Sans"
        case "inter":
            return "Inter"
        case "source-sans-3":
            return "Source Sans 3"
        case "ibm-plex-sans":
            return "IBM Plex Sans"
        case "rubik":
            return "Rubik"
        case "cairo":
            return "Cairo"
        case "pt-sans":
            return "PT Sans"
        case "merriweather":
            return "Merriweather"
        default:
            return stored
        }
    }

    private static func platformFontFamilies() -> [String] {
        #if os(macOS)
        return NSFontManager.shared.availableFontFamilies
        #elseif canImport(UIKit)
        return UIFont.familyNames
        #else
        return []
        #endif
    }
}
