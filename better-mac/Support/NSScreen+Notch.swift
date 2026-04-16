import AppKit

extension NSScreen {
    /// True when the screen reports a non-zero top safe-area inset — i.e. a
    /// physical MacBook notch.
    var hasPhysicalNotch: Bool {
        safeAreaInsets.top > 0
    }

    /// Rect (in screen coordinates, bottom-left origin per AppKit convention)
    /// describing the notch opening. Returns nil on non-notched screens.
    ///
    /// `auxiliaryTopLeftArea` and `auxiliaryTopRightArea` describe the menu bar
    /// regions to the left and right of the notch respectively; their missing
    /// width equals the notch width.
    var notchRect: CGRect? {
        guard hasPhysicalNotch else { return nil }
        let notchHeight = safeAreaInsets.top
        let leftWidth = auxiliaryTopLeftArea?.width ?? 0
        let rightWidth = auxiliaryTopRightArea?.width ?? 0
        let notchWidth = max(0, frame.width - leftWidth - rightWidth)
        guard notchWidth > 0 else { return nil }
        let x = frame.minX + leftWidth
        // AppKit's frame origin is bottom-left, so the notch sits at the top
        // of the screen = frame.maxY - notchHeight.
        let y = frame.maxY - notchHeight
        return CGRect(x: x, y: y, width: notchWidth, height: notchHeight)
    }

    /// Fallback pill rect used for external monitors and non-notched Macs.
    /// Renders as a floating pill centered at the top of the main screen.
    func fallbackPillRect(width: CGFloat = 200, height: CGFloat = 32) -> CGRect {
        let x = frame.midX - width / 2
        let y = frame.maxY - height
        return CGRect(x: x, y: y, width: width, height: height)
    }

    /// Resolve the rect to use for the collapsed island on this screen —
    /// physical notch when available, pill fallback otherwise.
    var islandCollapsedRect: CGRect {
        notchRect ?? fallbackPillRect()
    }
}
