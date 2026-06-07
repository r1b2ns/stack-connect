import Foundation

extension Array {
    /// Foundation-pure equivalent of SwiftUI's
    /// `RangeReplaceableCollection.move(fromOffsets:toOffset:)`.
    ///
    /// The core `HomeViewModel` cannot depend on SwiftUI (US-010 AC-4), so this
    /// reproduces the exact reordering semantics the iOS baseline relied on:
    /// elements at `source` are removed and re-inserted so they land *before*
    /// the element originally at `destination` (a `toOffset` of `count` appends
    /// to the end). Mirrors the standard library's own implementation.
    ///
    /// Tolerates degenerate inputs without crashing: a same-position move is a
    /// no-op (TC-080) and out-of-range offsets are clamped (TC-081).
    mutating func moveElements(fromOffsets source: IndexSet, toOffset destination: Int) {
        guard !source.isEmpty else { return }

        // Clamp destination into the valid insertion range [0, count].
        let clampedDestination = Swift.max(0, Swift.min(destination, count))

        // Pull out the moved elements (in their original order), keeping the
        // remainder intact.
        let validSource = source.filter { $0 >= 0 && $0 < count }
        guard !validSource.isEmpty else { return }

        let moved = validSource.map { self[$0] }
        // Insertion index shifts down by the number of removed elements that sat
        // before the destination.
        let removedBeforeDestination = validSource.filter { $0 < clampedDestination }.count
        let insertionIndex = clampedDestination - removedBeforeDestination

        // Remove from highest index down so earlier indices stay valid.
        for index in validSource.sorted(by: >) {
            remove(at: index)
        }
        insert(contentsOf: moved, at: Swift.min(insertionIndex, count))
    }
}
