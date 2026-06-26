import Foundation

/// Returns `desired` if it isn't already taken (case-insensitive), otherwise appends the
/// lowest free " N" suffix — e.g. "untitled profile" → "untitled profile 2" → "untitled profile 3".
func uniqueName(_ desired: String, taken: [String]) -> String {
    let lowered = Set(taken.map { $0.lowercased() })
    if !lowered.contains(desired.lowercased()) { return desired }
    var n = 2
    while lowered.contains("\(desired) \(n)".lowercased()) { n += 1 }
    return "\(desired) \(n)"
}
