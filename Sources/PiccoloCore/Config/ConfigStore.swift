import Foundation

/// The outcome of `ConfigStore.load()`: a usable config and what was skipped, repaired or moved aside.
public struct LoadResult: Equatable, Sendable {
    public let config: Config
    /// Human-readable notes, one per problem. Empty when the file was clean or missing.
    public let issues: [String]
}

public enum ConfigStoreError: Error, Equatable, Sendable {
    /// The config failed validation. Nothing was written.
    case invalid(ValidationError)
    /// The file on disk uses a newer format version. It was left untouched.
    case newerFileVersion(Int)
}

/// Loads and saves the config file at `url`. The caller decides where the file lives.
public struct ConfigStore: Sendable {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    /// Loads the config. Bad content never throws: it is reported in `issues` and the usable
    /// part is kept. Only I/O failures throw.
    ///
    /// - A missing file gives `Config.default` and writes nothing.
    /// - A file that is not JSON, or whose top level is unusable, is moved aside next to the
    ///   original as `<stem>.corrupt-<yyyyMMdd-HHmmss>.<ext>`, and `Config.default` is returned.
    /// - A file with a version above `Config.currentVersion` is left untouched, `Config.default`
    ///   is returned, and `save(_:)` refuses to overwrite it.
    /// - An undecodable or invalid binding is skipped. Of several bindings sharing an ID, the
    ///   first valid one is kept; invalid bindings never claim an ID.
    /// - An invalid `resizeStep` is replaced by the default.
    public func load() throws -> LoadResult {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return LoadResult(config: .default, issues: [])
        }
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()

        // The version is read first, so a newer file is recognised whatever else it contains.
        let version: Int
        do {
            version = try decoder.decode(VersionProbe.self, from: data).version
        } catch {
            return try quarantine(reason: describeFailure(error))
        }
        guard version >= 1 else {
            return try quarantine(reason: "version \(version) is not a valid version")
        }
        guard version <= Config.currentVersion else {
            return LoadResult(
                config: .default,
                issues: [
                    "\(url.lastPathComponent) has version \(version), which this build cannot read; "
                        + "it was left untouched and the defaults were loaded"
                ])
        }

        let file: StoredFile
        do {
            file = try decoder.decode(StoredFile.self, from: data)
        } catch {
            return try quarantine(reason: describeFailure(error))
        }

        var issues: [String] = []

        var resizeStep = Config.defaultResizeStep
        if let stored = file.resizeStep {
            switch stored.result {
            case .success(let value):
                do {
                    try Config.validateResizeStep(value)
                    resizeStep = value
                } catch {
                    issues.append("\(error); using the default \(Config.defaultResizeStep)")
                }
            case .failure(let error):
                issues.append(
                    "resizeStep could not be read (\(describeFailure(error))); "
                        + "using the default \(Config.defaultResizeStep)")
            }
        }

        var bindings: [Binding] = []
        var seen: Set<UUID> = []
        for (index, slot) in file.bindings.enumerated() {
            let binding: Binding
            switch slot.result {
            case .success(let value):
                binding = value
            case .failure(let error):
                issues.append("bindings[\(index)] skipped: \(describeFailure(error))")
                continue
            }
            do {
                try binding.validate()
            } catch {
                issues.append("bindings[\(index)] skipped: \(error)")
                continue
            }
            guard seen.insert(binding.id).inserted else {
                issues.append("bindings[\(index)] skipped: duplicate id \(binding.id.uuidString)")
                continue
            }
            bindings.append(binding)
        }

        return LoadResult(
            config: Config(resizeStep: resizeStep, bindings: bindings),
            issues: issues)
    }

    /// Validates, creates the parent directory and writes atomically.
    ///
    /// Throws `ConfigStoreError.invalid` for an invalid config and
    /// `ConfigStoreError.newerFileVersion` when the file on disk is from a newer version.
    public func save(_ config: Config) throws {
        do {
            try config.validate()
        } catch {
            throw ConfigStoreError.invalid(error)
        }
        if let onDisk = try versionOnDisk(), onDisk > Config.currentVersion {
            throw ConfigStoreError.newerFileVersion(onDisk)
        }
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try ConfigJSON.data(for: config).write(to: url, options: .atomic)
    }

    /// The version of the file on disk, or `nil` when there is no file or it has no readable version.
    private func versionOnDisk() throws -> Int? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        return try? JSONDecoder().decode(VersionProbe.self, from: data).version
    }

    /// Moves an unusable file aside and reports it. Never overwrites an earlier copy.
    private func quarantine(reason: String) throws -> LoadResult {
        let destination = corruptCopyURL(for: Date())
        try FileManager.default.moveItem(at: url, to: destination)
        return LoadResult(
            config: .default,
            issues: [
                "\(url.lastPathComponent) could not be used (\(reason)); "
                    + "moved it to \(destination.lastPathComponent) and loaded the defaults"
            ])
    }

    private func corruptCopyURL(for date: Date) -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let stamp = formatter.string(from: date)
        let stem = url.deletingPathExtension().lastPathComponent
        let fileExtension = url.pathExtension
        let directory = url.deletingLastPathComponent()

        var attempt = 1
        while true {
            var name = "\(stem).corrupt-\(stamp)"
            if attempt > 1 {
                name += "-\(attempt)"
            }
            if !fileExtension.isEmpty {
                name += ".\(fileExtension)"
            }
            let candidate = directory.appending(path: name)
            if !FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
            attempt += 1
        }
    }
}

/// Reads only the version, so that a newer file is recognised whatever else it contains.
private struct VersionProbe: Decodable {
    let version: Int
}

/// The top level of the file. Each binding and the step decode separately, so that one bad
/// entry does not discard the others.
private struct StoredFile: Decodable {
    let resizeStep: Lenient<Double>?
    let bindings: [Lenient<Binding>]
}

/// Decodes a value or keeps the error, so that a failure stays inside its container.
private struct Lenient<Value: Decodable>: Decodable {
    let result: Result<Value, any Error>

    init(from decoder: any Decoder) throws {
        result = Result { try Value(from: decoder) }
    }
}

private enum ConfigJSON {
    /// The file text for `config`: pretty-printed with sorted keys, ending in a newline.
    static func data(for config: Config) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let json = String(decoding: try encoder.encode(config), as: UTF8.self)
        // Foundation writes an empty array as "[", a blank line and "]". Write it as "[]" instead.
        // A raw newline cannot occur inside a JSON string, so this only matches empty arrays.
        let text = json.replacing(#/\[\n\n *\]/#, with: "[]")
        return Data((text + "\n").utf8)
    }
}

/// A short reason for a decoding failure, for an issue line.
private func describeFailure(_ error: any Error) -> String {
    guard let decodingError = error as? DecodingError else {
        return "\(error)"
    }
    switch decodingError {
    case .keyNotFound(let key, _):
        return "missing key \"\(key.stringValue)\""
    case .typeMismatch(_, let context), .valueNotFound(_, let context), .dataCorrupted(let context):
        return context.debugDescription
    @unknown default:
        return "\(error)"
    }
}
