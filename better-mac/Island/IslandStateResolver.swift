import Foundation

/// Pure, stateless resolver that maps the two inputs the island cares about
/// (whether the cursor is in the hot zone, and whether a track is loaded)
/// into the single `IslandState` the window controller renders from.
///
/// Extracted into its own type so the mapping is one call and one test
/// surface, without forcing the controller to re-derive it in multiple
/// places.
enum IslandStateResolver {
    /// Resolve the island state from its two independent inputs.
    ///
    /// - Parameters:
    ///   - hovering: `true` while the cursor is inside the hot zone.
    ///   - hasTrack: `true` while `NowPlayingStore` has a current track.
    /// - Returns: `.expanded` when hovering, `.playing` when a track is
    ///   loaded, `.idle` otherwise. Hover always wins over `hasTrack`.
    nonisolated static func resolve(hovering: Bool, hasTrack: Bool) -> IslandState {
        if hovering { return .expanded }
        return hasTrack ? .playing : .idle
    }
}
