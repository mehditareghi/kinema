import Foundation
import KinemaCore

@main
struct KinemaCLI {
    static func main() {
        let args = Array(CommandLine.arguments.dropFirst())
        guard !args.isEmpty else {
            printUsage()
            exit(1)
        }

        var mediaPaths: [String] = []
        var newWindow = false

        var i = 0
        while i < args.count {
            let arg = args[i]
            switch arg {
            case "--help", "-h":
                printUsage()
                exit(0)
            case "--new-window":
                newWindow = true
            case "--separate-windows":
                newWindow = true
            default:
                if arg.hasPrefix("--") {
                    fputs("Unknown option: \(arg)\n", stderr)
                    exit(1)
                } else {
                    mediaPaths.append(arg)
                }
            }
            i += 1
        }

        guard let first = mediaPaths.first else {
            printUsage()
            exit(1)
        }

        let url: URL
        if first.hasPrefix("http://") || first.hasPrefix("https://") {
            url = URL(string: first)!
        } else {
            url = URL(fileURLWithPath: (first as NSString).expandingTildeInPath)
        }

        var components = URLComponents()
        components.scheme = "kinema"
        components.host = "open"
        components.queryItems = [
            URLQueryItem(name: "url", value: url.absoluteString),
            URLQueryItem(name: "new_window", value: newWindow ? "1" : "0")
        ]

        guard let deepLink = components.url else {
            fputs("Failed to build kinema:// URL\n", stderr)
            exit(1)
        }

        #if os(macOS)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = [deepLink.absoluteString]
        try? process.run()
        process.waitUntilExit()
        exit(process.terminationStatus)
        #else
        print(deepLink.absoluteString)
        #endif
    }

    static func printUsage() {
        print("""
        kinema-cli — open media in Kinema

        Usage: kinema-cli [options] <file|url> [more files...]

        Options:
          --new-window       Open in a new window / session
          -h, --help         Show this help

        Builds a kinema://open URL and hands it to the Kinema app (macOS).
        """)
    }
}
