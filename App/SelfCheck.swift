import Foundation
import PiccoloSystem

/// Headless diagnostic mode: `Piccolo --self-check <path>` writes a JSON report to
/// `<path>` and exits. `scripts/self-check.sh` launches it through LaunchServices
/// so that Piccolo itself, not the calling terminal, is the process whose
/// Accessibility trust is checked.
enum SelfCheck {
    static let flag = "--self-check"

    enum Request: Equatable {
        /// Normal launch.
        case none
        /// Self-check mode with the output path.
        case write(path: String)
        /// The flag was given without a path.
        case missingPath
    }

    struct Report: Encodable, Equatable {
        let axTrusted: Bool
        let bundleID: String
        let version: String
        let build: String
        let bundlePath: String
    }

    static func request(from arguments: [String]) -> Request {
        guard let index = arguments.firstIndex(of: flag) else { return .none }
        let next = arguments.index(after: index)
        guard next < arguments.endIndex else { return .missingPath }
        return .write(path: arguments[next])
    }

    static func makeReport(
        bundle: Bundle = .main,
        permission: AccessibilityPermission = AccessibilityPermission()
    ) -> Report {
        Report(
            axTrusted: permission.isTrusted,
            bundleID: bundle.bundleIdentifier ?? "",
            version: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "",
            build: bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "",
            bundlePath: bundle.bundlePath
        )
    }

    static func encode(_ report: Report) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(report)
    }

    /// Writes the report to `path`. Returns the process exit code.
    static func run(writingTo path: String) -> Int32 {
        do {
            try encode(makeReport()).write(to: URL(fileURLWithPath: path), options: .atomic)
            return 0
        } catch {
            FileHandle.standardError.write(Data("self-check failed: \(error)\n".utf8))
            return 1
        }
    }
}
