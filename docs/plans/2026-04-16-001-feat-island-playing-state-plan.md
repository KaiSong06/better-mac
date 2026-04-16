---
title: "feat: Island playing-state with album thumb + waveform"
type: feat
status: active
date: 2026-04-16
---

# Island playing-state with album thumb + waveform

## Overview

Introduce a third visual state for the Dynamic Island — a compact "playing" look — that appears whenever `NowPlayingStore` has a current track. The collapsed notch grows horizontally into a pill that shows the album thumbnail on the left and a stylised sound-wave animation on the right. Hovering the pill still expands into the full media UI; pausing freezes the waveform; clearing the track collapses back to the plain black notch.

## Problem Frame

Today the island has only two states: an idle black rectangle that sits in the notch, and a full-size expanded panel that requires a hover. A user glancing at their Mac has no way to tell from the island alone whether anything is playing, what it is, or whether it's still going. iPhone's Dynamic Island solves this with an activity-indicator look the moment a track starts; `better-mac` should mirror that.

## Requirements Trace

- **R1.** When `NowPlayingStore.hasTrack == true` and the island is not being hovered, the island renders in a new "playing" state: wider than the notch, black background, album thumbnail on the left, waveform on the right.
- **R2.** When no track is available, the island returns to the plain black notch rectangle (idle).
- **R3.** When `isPlaying == true`, the waveform animates smoothly. When `isPlaying == false` (paused but still has a track), the waveform freezes at rest position; the album thumbnail remains.
- **R4.** Hovering the playing state still expands into the full media UI (current hover behavior preserved).
- **R5.** Missing artwork falls back to a generic `music.note` glyph in the thumbnail slot.
- **R6.** All transitions (idle ↔ playing, playing → expanded → playing) animate smoothly without flicker.
- **R7.** When the user disables the island via the menu (`islandEnabled = false`), the playing state is also hidden — it does not bypass the toggle.

## Scope Boundaries

- No real audio-reactive visualisation. The waveform is a simulated animated path, not driven by actual audio samples (would require a virtual audio device or CoreAudio process tap, which is out of scope).
- No new media sources. Continue to rely on the existing MediaRemote + Spotify fallback plumbing.
- No new transport controls inside the playing state. The compact pill is look-only; the expanded hover UI remains the single home for play/pause/skip/seek.
- No changes to the volume HUD or its suppression behavior.
- No persistence for a "keep visible" mode — the playing pill only shows while there's an active track.

## Context & Research

### Relevant code and patterns

- `better-mac/Island/IslandView.swift` — today renders `IslandState.collapsed` (black rounded rect) and `IslandState.expanded` (full SwiftUI content). The new playing state adds a third branch inside the same `ZStack` + `switch` pattern.
- `better-mac/Island/IslandWindowController.swift` — owns `ObservableContainer.state` (`IslandState`) and animates the panel frame between `collapsedRect()` and `expandedRect(from:)`. The new state needs a third rect (`playingRect(from:)`) and an observer on the `NowPlayingStore` so state flips on track changes.
- `better-mac/Media/NowPlayingStore.swift` — already publishes `hasTrack`, `isPlaying`, and `artworkImage`. No changes needed; this plan only consumes these.
- `better-mac/Island/IslandView.swift` (ArtworkView) — already implements the fallback-to-`music.note` pattern for missing artwork. The new compact thumbnail should reuse the same visual treatment.
- `better-mac/Support/NSScreen+Notch.swift` — provides `notchRect` and `fallbackPillRect(width:height:)`. The playing rect is computed from the notch position but with a wider width, mirroring the expanded-rect math.
- `better-mac/Island/SeekBarView.swift` — precedent for pulling pure math into a testable `enum` (`SeekBarMath`). Apply the same pattern here with an `IslandStateResolver` enum.

### Institutional learnings

No prior `docs/solutions/` entries apply — this repo has none yet.

### External references

Not needed. The pattern is a direct extension of the existing SwiftUI + AppKit panel setup and mirrors iPhone's well-known "compact live activity" shape.

## Key Technical Decisions

- **Three-state model.** Replace the two-case `IslandState` enum with three cases: `.idle`, `.playing`, `.expanded`. The playing case is dependent purely on `NowPlayingStore.hasTrack`; `isPlaying` only toggles the waveform animation within that state, not the state itself.
- **Purely additive to the controller.** `IslandWindowController` gains a third rect (`playingRect`), one new observer (on `NowPlayingStore`), and a small state-resolution helper. The hover machinery and existing expanded-rect math are unchanged.
- **Pure state resolution.** The mapping `(hovering: Bool, hasTrack: Bool) -> IslandState` lives in a `nonisolated static` helper so it can be unit-tested without any AppKit dependency. Hover always wins over hasTrack (hover → `.expanded`).
- **Waveform: `TimelineView` + `Canvas`.** SwiftUI's `TimelineView(.animation)` drives a per-frame `Canvas` that draws a compact sine-path with time-varying phase. Freezes cleanly by passing `isAnimating: false` (TimelineView pauses) and rendering the same phase-0 path. No `Timer`, no `CADisplayLink`, no manual frame accounting.
- **Playing rect geometry.** Width 340 pt, height 36 pt, top-flush with the menu bar. Same center x as the notch. Bottom corners more rounded (18) than the notch's (10) so the pill reads as distinct from the expanded panel's 22-corner.
- **Animation: same NSAnimationContext rig.** Reuse the existing 0.24 s ease-out controller animation for all three directions (idle ↔ playing ↔ expanded). No new animation primitives.
- **No new settings.** The feature rides on the existing `islandEnabled` toggle.

## Open Questions

### Resolved During Planning

- **Widened collapsed vs. notch-sized?** → Widened. Playing rect is 340×36, wider than the notch.
- **Waveform vs. equalizer bars?** → Stylised waveform via `Canvas` + `TimelineView`.
- **Paused behavior?** → Same state, frozen waveform at rest.
- **Hover during playing state?** → Unchanged; still expands to the full UI.
- **State enum shape?** → `.idle / .playing / .expanded` (three cases).

### Deferred to Implementation

- **Exact waveform amplitude and frequency** — start with amplitude ≈ 30 % of slot height and a slow-ish frequency; tune once visible on device.
- **Thumbnail corner radius and padding** — aim for ~6 pt radius and ~4 pt inner padding; tune in place.
- **Whether the pill should expose any other indicator when `sourceBundleID` is known** — maybe a tiny app-source dot in a follow-up; not in scope for v1.

## High-Level Technical Design

> *This illustrates the intended approach and is directional guidance for review, not implementation specification. The implementing agent should treat it as context, not code to reproduce.*

State resolution:

```
IslandStateResolver.resolve(hovering:, hasTrack:)
  hovering=true, hasTrack=*       → .expanded
  hovering=false, hasTrack=true   → .playing
  hovering=false, hasTrack=false  → .idle
```

Frame resolution:

```
IslandWindowController.frame(for state)
  .idle     → notch rect      (pure black notch, small)
  .playing  → playing rect    (wider pill, top-flush, below menu bar)
  .expanded → expanded rect   (full 420×140 panel below menu bar)
```

Trigger graph:

```
 NowPlayingStore.hasTrack changes        IslandHotZone.state changes
         │                                       │
         └──────────► IslandStateResolver ◄──────┘
                              │
                              ▼
                IslandWindowController.setState(...)
                              │
                              ▼
              ┌───────── animate frame ─────────┐
              ▼                                  ▼
      container.state = ...          IslandView renders matching branch
                                               │
                             ┌─────────────────┴─────────────────┐
                             ▼                 ▼                 ▼
                         idle view       playing view        expanded view
                         (black rect)   (thumb + wave)    (full media UI)
```

## Implementation Units

- [ ] **Unit 1: Three-state island model + pure state resolver**

**Goal:** Replace the two-case `IslandState` with three cases (`.idle`, `.playing`, `.expanded`) and introduce a pure, unit-testable state-resolution helper.

**Requirements:** R1, R2, R4

**Dependencies:** None.

**Files:**
- Modify: `better-mac/Island/IslandView.swift` (rename the `.collapsed` case to `.idle`; adjust the switch to prepare for the third case — add an empty `.playing` branch that initially renders the same as `.idle`).
- Modify: `better-mac/Island/IslandWindowController.swift` (update callsites; add a `frame(for:)` helper returning the correct rect per case; keep `playingRect` pointing at a placeholder that equals the notch rect for now — actual geometry lands in Unit 3).
- Create: `better-mac/Island/IslandStateResolver.swift` — enum with a `nonisolated static func resolve(hovering: Bool, hasTrack: Bool) -> IslandState`.
- Modify: `better-mac/Island/IslandHotZone.swift` (unchanged logic, but call sites that produce `.collapsed` now produce `.idle`).
- Test: `better-macTests/IslandStateResolverTests.swift`.

**Approach:**
- Enum change is the axis the rest of the plan rotates around — doing it as its own commit keeps every other unit small.
- Controller still only swaps between two rects in this unit; state flip logic and visuals come in Unit 3 and Unit 2/4 respectively.
- The resolver is pure — no `@MainActor`, no AppKit types — so tests don't need the main-actor hop.

**Patterns to follow:**
- `SeekBarMath` in `better-mac/Island/SeekBarView.swift` for pure math + `nonisolated static` test-friendly helpers.
- The existing `nonisolated static` helpers on `VolumeKeyInterceptor` and `AudioOutputMonitor` confirm the idiom.

**Test scenarios:**
- Happy path: `resolve(hovering: false, hasTrack: false)` → `.idle`.
- Happy path: `resolve(hovering: false, hasTrack: true)` → `.playing`.
- Happy path: `resolve(hovering: true, hasTrack: true)` → `.expanded`.
- Happy path: `resolve(hovering: true, hasTrack: false)` → `.expanded` (hover wins).
- Edge case: all four transition pairs (`.idle` → `.playing`, `.playing` → `.idle`, `.idle` → `.expanded`, `.playing` → `.expanded`, `.expanded` → `.playing`, `.expanded` → `.idle`) resolve to the expected next state given the inputs at each moment. Encode these as a table-driven test.

**Verification:**
- Project still builds. All existing tests still pass.
- New resolver tests pass.
- Running the app shows exactly the same visual behavior as before (the new `.playing` case is unreachable until Unit 3 wires the store).

---

- [ ] **Unit 2: WaveformView SwiftUI component**

**Goal:** A reusable SwiftUI view that renders a compact animated sine-wave line and can be frozen at rest. Sized to fit alongside the album thumbnail inside the playing-state pill.

**Requirements:** R3, R5

**Dependencies:** None. Can land in parallel with Unit 1.

**Files:**
- Create: `better-mac/Island/WaveformView.swift`.
- Test: none — pure visual component with no branching logic beyond animation on/off (covered by the visual verification in Unit 4).

**Approach:**
- Use `TimelineView(.animation)` to get a monotonic time source when `isAnimating == true`; wrap it in a plain `Canvas`-based redraw that renders a single sine path across the available width. When `isAnimating == false`, render the same shape with a fixed phase (0) — no `TimelineView` needed, so nothing redraws.
- The view accepts `isAnimating: Bool`, a `color` (default white), and an optional `amplitude` and `frequency` with sensible defaults (~30 % of height, ~1.4 cycles across the width).
- Line width ≈ 1.5 pt, `.round` line cap. Uses `Path` inside the `Canvas` for the sine — avoid AppKit, avoid per-frame allocations beyond the path.
- Stays small: one struct, no view modifiers invented by this plan.

**Patterns to follow:**
- The existing SwiftUI-only island components (`IslandView`, `IslandControlsView`, `SeekBarView`) for naming and style conventions.

**Test scenarios:**
- Test expectation: none — presentation-only view; behavior is validated visually in Unit 4 verification.

**Verification:**
- Dropped into a SwiftUI `#Preview` or a temporary test harness, the view animates smoothly when `isAnimating = true` and renders a static sine line when `isAnimating = false`.
- No runtime warnings about `Canvas` or `TimelineView` misuse.

---

- [ ] **Unit 3: Playing-state geometry + store wiring**

**Goal:** Teach `IslandWindowController` about the playing rect, observe `NowPlayingStore` for track + playback changes, and animate the frame to the right state using the Unit 1 resolver.

**Requirements:** R1, R2, R4, R6, R7

**Dependencies:** Unit 1.

**Files:**
- Modify: `better-mac/Island/IslandWindowController.swift` (add `playingRect(from:)`; extend `frame(for:)`; subscribe to `NowPlayingStore.$title` / `$isPlaying` — whichever publishers give us a clean `hasTrack` signal; combine with hover state via `IslandStateResolver.resolve` and push results into `container.state`).
- Modify: `better-mac/App/AppDelegate.swift` if a small change is needed so the controller gets a reference to the live store (it already does today — double-check no additional wiring is required).
- Test: `better-macTests/IslandPlayingRectTests.swift` — pure rect math (center x, width, height, top-flush behavior); no AppKit needed if we extract a `nonisolated static` helper that takes a screen frame and returns the playing rect.

**Approach:**
- Playing rect math: center on the main screen's midX; width 340 pt; height 36 pt; top = screen.frame.maxY. Corners 18 pt on the bottom only (matches `IslandView`'s playing branch).
- State resolution: combine `ObservableContainer.isHovering` (derived from the existing hover events) with `store.hasTrack` through `IslandStateResolver.resolve`. Today the container directly holds `state`; we introduce an intermediate hover flag and let the resolver compute the final state so both inputs converge on one source of truth.
- Respect `islandEnabled`: when disabled, the controller's `hide()` path is already wired; no new branch needed beyond making sure the store-driven state updates do nothing while the panel is ordered out.
- Animation: reuse the existing 0.24 s ease-out `NSAnimationContext` block. Three-way transitions fall out naturally because `frame(for:)` returns the right rect for the target state.

**Execution note:** Extract the playing-rect math into a `nonisolated static func playingRect(in screenFrame: CGRect) -> CGRect` before wiring the controller. Unit-test it before running the app — rectangle arithmetic is the kind of thing that's cheaper to get right in a test than to eyeball.

**Patterns to follow:**
- The existing `expandedRect(from:)` / `collapsedRect()` pair in `IslandWindowController`.
- The existing Combine `$islandEnabled.sink` pattern in `AppDelegate.observeSettings()` for subscribing to a published property on the main actor.

**Test scenarios:**
- Happy path: `playingRect(in:)` for a 1512×982 screen returns a 340×36 rect flush with `maxY`, centered on `midX`.
- Happy path: `playingRect(in:)` for a smaller 1280×800 screen still centers and clamps to visible area.
- Edge case: `playingRect(in:)` returns the same `y` (maxY) regardless of screen height — confirms the "top-flush" contract.
- Integration: hovering while `hasTrack=true` resolves to `.expanded` (covered by Unit 1 resolver test plus a spot-check that the controller actually calls into the resolver with the right inputs — can be covered by a very small integration test that observes `container.state` transitions).

**Verification:**
- With Music playing, the island grows to the wider playing pill within ~250 ms of the track becoming available.
- Pausing leaves the pill in place (isPlaying change doesn't flip state away from `.playing`).
- Stopping or skipping to a state with no track collapses the pill back to the notch rectangle.
- Hovering the playing pill expands into the full media UI; moving away returns to the playing pill if audio is still loaded, or to idle if not.
- Disabling the island via the menu hides everything; re-enabling restores the correct state based on current track.

---

- [ ] **Unit 4: Playing-state SwiftUI content + polish**

**Goal:** Populate the `.playing` branch of `IslandView` with the real compact layout — album thumbnail on the left, `WaveformView` on the right — and make artwork and animation react to the store.

**Requirements:** R1, R3, R5, R6

**Dependencies:** Units 1, 2, 3.

**Files:**
- Modify: `better-mac/Island/IslandView.swift` — add a new `PlayingCollapsedContent` private view; render it when `state == .playing`; reuse the existing `ArtworkView` fallback for missing artwork; feed `WaveformView(isAnimating: store.isPlaying)`.
- Modify: `better-mac/Island/IslandView.swift` — the `UnevenRoundedRectangle` switch picks the playing shape (top 0, bottom 18) when `state == .playing`.

**Approach:**
- Compact layout: `HStack { Artwork; Spacer; Waveform }` with ~8 pt horizontal padding and 4 pt vertical padding.
- Artwork sizes to ~28×28 pt (slightly inset from the 36 pt pill height), 6 pt corner radius.
- Waveform takes remaining horizontal space with a max width so very narrow thumbnails don't stretch the wave too thin.
- Transition between `.idle`, `.playing`, and `.expanded` uses the same `.animation(.easeOut(duration: 0.22), value: state)` modifier the existing branch uses, so the content cross-fades cleanly without a dedicated matched-geometry rig.
- Text only: no title/artist in the playing pill. That stays exclusive to the expanded state.

**Patterns to follow:**
- The existing `ExpandedIslandContent` and `ArtworkView` in `better-mac/Island/IslandView.swift`.

**Test scenarios:**
- Test expectation: none — layout-only SwiftUI work. Verification is visual.

**Verification:**
- Playing with Music / Spotify / Safari shows artwork + animated waveform in the pill.
- Pausing freezes the waveform; artwork remains; the pill does not flicker.
- Media without artwork (e.g., podcast with no album art) shows the `music.note` fallback glyph in the thumbnail slot.
- Cross-fading between idle, playing, and expanded is smooth; no visible seam at the panel boundary.

---

## System-Wide Impact

- **Interaction graph:**
  - `NowPlayingStore` → `IslandWindowController` (new Combine subscription on `hasTrack` / `isPlaying`-derived publisher).
  - `IslandHotZone` → `IslandWindowController` (unchanged; now feeds a hover flag into the resolver instead of directly setting `state`).
  - `IslandStateResolver` is the single place that combines both inputs into `IslandState`.
- **Error propagation:**
  - No new failure modes. If the store is empty, `.idle` wins. If the waveform view somehow fails to render, SwiftUI falls back to an empty view — there is no crash path.
- **State lifecycle risks:**
  - Rapid `hasTrack` flips (e.g., MediaRemote momentarily returns an empty dict) could cause the pill to strobe. Mitigation: the existing 2-second MediaRemote silence threshold in `NowPlayingStore` already absorbs these; do not add a second debounce unless the problem is observed in practice.
  - Screen hot-plug during playing state must reposition the pill — already handled by the existing `didChangeScreenParametersNotification` observer that calls `reposition()`; confirm it picks up the new rect.
- **API surface parity:**
  - `IslandState` is an internal type; the enum widening is a non-breaking change within the app.
- **Integration coverage:**
  - The enum expansion means every `switch IslandState` site must be revisited. There are only two today (`IslandView` and `IslandWindowController`), but the implementer should rely on Swift's exhaustive switch to catch any misses.
- **Unchanged invariants:**
  - Volume HUD behavior, CGEventTap, CoreAudio monitor, Spotify fallback, permissions flow, Open-at-Login, Settings scene — none of these are touched.

## Risks & Dependencies

| Risk | Mitigation |
|---|---|
| Playing pill flickers on rapid track-change bursts | The existing silence threshold in `NowPlayingStore` already coalesces noise; add a minimum `.playing` dwell time only if flicker is observed. |
| Waveform animation burns CPU | `TimelineView(.animation)` only ticks while the view is on-screen and `isAnimating == true`; when paused or when the pill is hidden (e.g., island disabled or expanded), animation stops. |
| Widened pill interferes with menu bar clicks | The panel is `ignoresMouseEvents = false` but non-activating; it does not steal focus. If the wider rect overlaps existing menu-extra items in practice, reduce the width or offset the pill ~2 pt below the menu bar. |
| Enum widening misses a `switch` site | Rely on Swift exhaustive-switch compiler errors; there are only two sites today. |
| SwiftUI transitions between three states reveal a layout jump between the idle-rect shape and the playing-rect shape | The existing 0.24 s `NSAnimationContext` frame animation plus SwiftUI `.animation(_:value:)` on the content should mask it. If a seam appears, anchor the content to `.top` inside `IslandView` so the top-flush boundary doesn't move. |

## Documentation / Operational Notes

- Update `README.md` with a one-sentence mention under the features bullet list: "When audio is playing, the island expands into a compact pill showing album artwork and an animated waveform."
- No new permissions, no new settings, no migration, no rollout notes.

## Verification Strategy (End-to-End)

1. **Build + tests green** — `xcodebuild -scheme better-mac test` passes, including the new `IslandStateResolverTests` and `IslandPlayingRectTests`.
2. **Idle look unchanged when nothing is playing** — fresh launch with no audio: plain black notch, same as today.
3. **Playing state engages** — start a track in Music: island grows to a 340×36 pill within ~250 ms, showing album artwork on the left and an animated waveform on the right.
4. **Paused state freezes animation** — pause in Music: waveform freezes, artwork remains, pill stays the same size.
5. **Resume animates again** — hit play: waveform resumes motion without layout shift.
6. **Hover still expands** — hover over the playing pill: smooth transition to the full 420×140 expanded panel; moving away returns to the playing pill.
7. **Track cleared returns to idle** — quit Music / stop playback entirely: pill collapses back to the plain black notch within ~250 ms.
8. **Missing artwork** — play a podcast or radio stream with no artwork: thumbnail slot shows the `music.note` fallback glyph.
9. **Spotify fallback path** — play a track in Spotify with Music quit: same playing-pill behavior using the AppleScript-derived artwork and `isPlaying` state.
10. **Island toggle** — disable the island from the menu bar: pill hides immediately; re-enable: pill appears if a track is still playing, idle notch otherwise.
11. **Multi-display hot-plug** — plug/unplug an external display while playing: pill repositions to the main (notched) screen without flicker.

## Sources & References

- Related code: `better-mac/Island/IslandView.swift`, `better-mac/Island/IslandWindowController.swift`, `better-mac/Island/IslandHotZone.swift`, `better-mac/Media/NowPlayingStore.swift`, `better-mac/Support/NSScreen+Notch.swift`
- Prior plan: `docs/plans/2026-04-16-000-feat-initial-better-mac-plan.md` (implicit — the initial build lives in `~/.claude/plans/dreamy-singing-hejlsberg.md`; this plan extends that baseline).
- GitHub repo: https://github.com/KaiSong06/better-mac
