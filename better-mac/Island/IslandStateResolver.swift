import Foundation

/// Three-level hover signal emitted by `IslandHotZone`. Shared between the
/// hot zone and the resolver so both layers speak the same vocabulary.
///
/// - `none`: cursor outside the hot zone.
/// - `peek`: cursor inside the hot zone, dwell timer not yet elapsed.
/// - `full`: cursor inside the hot zone and the dwell timer fired.
enum HoverLevel: Equatable { case none, peek, full }

/// Pure, stateless resolver that maps the two inputs the island cares about
/// (how intensely the cursor is hovering, and whether a track is loaded)
/// into the single `IslandState` the window controller renders from.
enum IslandStateResolver {
    /// Resolve the island state from its two independent inputs.
    ///
    /// - `hover.none` falls through to the track-presence check.
    /// - `hover.peek` always returns `.peek`; content differences between
    ///   "peek with track" and "peek without track" live in the view layer,
    ///   not here.
    /// - `hover.full` always returns `.expanded`.
    nonisolated static func resolve(hover: HoverLevel, hasTrack: Bool) -> IslandState {
        switch hover {
        case .none: return hasTrack ? .playing : .idle
        case .peek: return .peek
        case .full: return .expanded
        }
    }
}
