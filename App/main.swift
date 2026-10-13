import Foundation

// Entry point. Self-check mode is handled here, before SwiftUI starts, so that it
// never creates a menu bar item, a window or an Accessibility prompt.
switch SelfCheck.request(from: CommandLine.arguments) {
case .none:
    PiccoloApp.main()
case .write(let path):
    exit(SelfCheck.run(writingTo: path))
case .missingPath:
    FileHandle.standardError.write(Data("Usage: Piccolo --self-check <path>\n".utf8))
    exit(2)
}
