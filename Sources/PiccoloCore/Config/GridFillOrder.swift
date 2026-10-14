import Foundation

/// Where the windows of a grid go when there are fewer windows than cells. The raw values are the
/// vocabulary of the config file (`gridFillOrder`).
public enum GridFillOrder: String, Codable, CaseIterable, Sendable {
    /// Row by row: the first row is filled before the second begins.
    case rows
    /// Column by column: the first column is filled before the second begins.
    case columns
}
