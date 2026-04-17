import XCTest
@testable import better_mac

final class IslandStateResolverTests: XCTestCase {
    func testIdleWhenNoHoverAndNoTrack() {
        XCTAssertEqual(IslandStateResolver.resolve(hover: .none, hasTrack: false), .idle)
    }

    func testPlayingWhenNoHoverAndTrack() {
        XCTAssertEqual(IslandStateResolver.resolve(hover: .none, hasTrack: true), .playing)
    }

    func testPeekIgnoresTrack() {
        XCTAssertEqual(IslandStateResolver.resolve(hover: .peek, hasTrack: false), .peek)
        XCTAssertEqual(IslandStateResolver.resolve(hover: .peek, hasTrack: true), .peek)
    }

    func testExpandedWhenFullHoverWithTrack() {
        XCTAssertEqual(IslandStateResolver.resolve(hover: .full, hasTrack: true), .expanded)
    }

    func testExpandedWhenFullHoverWithoutTrack() {
        XCTAssertEqual(IslandStateResolver.resolve(hover: .full, hasTrack: false), .expanded)
    }

    /// Table-driven coverage of every transition the user can trigger so a
    /// regression in the resolve rules fails loudly.
    func testTransitionTable() {
        struct Case {
            let from: (HoverLevel, Bool)
            let to: (HoverLevel, Bool)
            let expectedFromState: IslandState
            let expectedToState: IslandState
            let label: String
        }

        let cases: [Case] = [
            Case(from: (.none, false), to: (.none, true),
                 expectedFromState: .idle, expectedToState: .playing,
                 label: "idle → playing when track arrives"),
            Case(from: (.none, true), to: (.none, false),
                 expectedFromState: .playing, expectedToState: .idle,
                 label: "playing → idle when track clears"),
            Case(from: (.none, false), to: (.peek, false),
                 expectedFromState: .idle, expectedToState: .peek,
                 label: "idle → peek on hover entry"),
            Case(from: (.none, true), to: (.peek, true),
                 expectedFromState: .playing, expectedToState: .peek,
                 label: "playing → peek on hover entry"),
            Case(from: (.peek, false), to: (.full, false),
                 expectedFromState: .peek, expectedToState: .expanded,
                 label: "peek → expanded after dwell timer without track"),
            Case(from: (.peek, true), to: (.full, true),
                 expectedFromState: .peek, expectedToState: .expanded,
                 label: "peek → expanded after dwell timer with track"),
            Case(from: (.peek, false), to: (.none, false),
                 expectedFromState: .peek, expectedToState: .idle,
                 label: "peek → idle on early exit without track"),
            Case(from: (.peek, true), to: (.none, true),
                 expectedFromState: .peek, expectedToState: .playing,
                 label: "peek → playing on early exit with track"),
            Case(from: (.full, true), to: (.none, true),
                 expectedFromState: .expanded, expectedToState: .playing,
                 label: "expanded → playing on hover-out while track loaded"),
            Case(from: (.full, false), to: (.none, false),
                 expectedFromState: .expanded, expectedToState: .idle,
                 label: "expanded → idle on hover-out without track"),
            Case(from: (.full, true), to: (.full, false),
                 expectedFromState: .expanded, expectedToState: .expanded,
                 label: "expanded stays expanded even if track clears under the cursor"),
            Case(from: (.peek, true), to: (.peek, false),
                 expectedFromState: .peek, expectedToState: .peek,
                 label: "peek stays peek even if track clears mid-dwell"),
        ]

        for c in cases {
            XCTAssertEqual(
                IslandStateResolver.resolve(hover: c.from.0, hasTrack: c.from.1),
                c.expectedFromState,
                "start state mismatch: \(c.label)"
            )
            XCTAssertEqual(
                IslandStateResolver.resolve(hover: c.to.0, hasTrack: c.to.1),
                c.expectedToState,
                "end state mismatch: \(c.label)"
            )
        }
    }
}
