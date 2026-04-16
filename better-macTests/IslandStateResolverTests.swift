import XCTest
@testable import better_mac

final class IslandStateResolverTests: XCTestCase {
    func testIdleWhenNoHoverAndNoTrack() {
        XCTAssertEqual(IslandStateResolver.resolve(hovering: false, hasTrack: false), .idle)
    }

    func testPlayingWhenNoHoverAndTrack() {
        XCTAssertEqual(IslandStateResolver.resolve(hovering: false, hasTrack: true), .playing)
    }

    func testExpandedWhenHoveringWithTrack() {
        XCTAssertEqual(IslandStateResolver.resolve(hovering: true, hasTrack: true), .expanded)
    }

    func testExpandedWhenHoveringWithoutTrack() {
        XCTAssertEqual(IslandStateResolver.resolve(hovering: true, hasTrack: false), .expanded)
    }

    /// Table-driven coverage of every transition the user can trigger so a
    /// regression in the resolve rules fails loudly.
    func testTransitionTable() {
        struct Case {
            let from: (Bool, Bool)
            let to: (Bool, Bool)
            let expectedFromState: IslandState
            let expectedToState: IslandState
            let label: String
        }

        let cases: [Case] = [
            Case(from: (false, false), to: (false, true),
                 expectedFromState: .idle, expectedToState: .playing,
                 label: "idle → playing when track arrives"),
            Case(from: (false, true), to: (false, false),
                 expectedFromState: .playing, expectedToState: .idle,
                 label: "playing → idle when track clears"),
            Case(from: (false, false), to: (true, false),
                 expectedFromState: .idle, expectedToState: .expanded,
                 label: "idle → expanded on hover"),
            Case(from: (false, true), to: (true, true),
                 expectedFromState: .playing, expectedToState: .expanded,
                 label: "playing → expanded on hover"),
            Case(from: (true, true), to: (false, true),
                 expectedFromState: .expanded, expectedToState: .playing,
                 label: "expanded → playing on hover-out while track loaded"),
            Case(from: (true, false), to: (false, false),
                 expectedFromState: .expanded, expectedToState: .idle,
                 label: "expanded → idle on hover-out without track"),
            Case(from: (true, true), to: (true, false),
                 expectedFromState: .expanded, expectedToState: .expanded,
                 label: "expanded stays expanded even if track clears under the cursor"),
        ]

        for c in cases {
            XCTAssertEqual(
                IslandStateResolver.resolve(hovering: c.from.0, hasTrack: c.from.1),
                c.expectedFromState,
                "start state mismatch: \(c.label)"
            )
            XCTAssertEqual(
                IslandStateResolver.resolve(hovering: c.to.0, hasTrack: c.to.1),
                c.expectedToState,
                "end state mismatch: \(c.label)"
            )
        }
    }
}
