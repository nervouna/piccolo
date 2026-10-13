import Foundation

// All output is one line of JSON on stdout. The exit code is 0 only on success.
let outcome = Commands.run(arguments: Array(CommandLine.arguments.dropFirst()))
FileHandle.standardOutput.write(Data((outcome.output + "\n").utf8))
exit(outcome.exitCode)
