/// TurboModeManager.swift

import Cocoa

/// Turbo Mode places every visible window of the frontmost app on its display
/// into the eighths grid, one window per cell. Other apps' windows stay put.
class TurboModeManager {

    /// In reading order on both landscape (4x2) and portrait (2x4) displays.
    private static let cellCalculations: [OrientationAware] = [
        WindowCalculationFactory.topLeftEighthCalculation,
        WindowCalculationFactory.topCenterLeftEighthCalculation,
        WindowCalculationFactory.topCenterRightEighthCalculation,
        WindowCalculationFactory.topRightEighthCalculation,
        WindowCalculationFactory.bottomLeftEighthCalculation,
        WindowCalculationFactory.bottomCenterLeftEighthCalculation,
        WindowCalculationFactory.bottomCenterRightEighthCalculation,
        WindowCalculationFactory.bottomRightEighthCalculation
    ]

    static func arrange() {
        let screenDetection = ScreenDetection()
        let focusedWindow = AccessibilityElement.getFocusedWindowElement()
        guard let pid = focusedWindow?.pid ?? NSWorkspace.shared.frontmostApplication?.processIdentifier,
              let context = MultiWindowManager.tilingContext(focusedWindow: focusedWindow,
                                                             screenDetection: screenDetection)
        else {
            NSSound.beep()
            return
        }

        // A fresh on-screen snapshot is the current-Space evidence, as for band tiling.
        let visibleInfo = WindowUtil.getWindowList(forceRefresh: true)
        let windows = MultiWindowManager.windowsOnScreen(screens: context.screens,
                                                         windows: AccessibilityElement(pid).windowElements ?? [],
                                                         focusedWindow: context.focusedWindow,
                                                         screenFor: { screenDetection.detectScreens(using: $0)?.currentScreen }).windows
        let screen = context.screens.currentScreen
        let arranged = arrange(windows: windows.filter { $0.pid == pid },
                               focusedWindow: context.focusedWindow,
                               visibleWindowInfo: visibleInfo,
                               visibleFrame: screen.adjustedVisibleFrame(),
                               frameTolerance: 1 / max(1, screen.backingScaleFactor))
        if arranged == 0 {
            NSSound.beep()
        }
    }

    /// Moves the current-Space windows into the cells in reading order, so a repeat
    /// keeps each window where it is. A ninth window onward wraps to the first cell.
    /// - Returns: The number of windows placed.
    @discardableResult
    static func arrange(windows: [AccessibilityElement], focusedWindow: AccessibilityElement?,
                        visibleWindowInfo: [WindowInfo], visibleFrame: CGRect,
                        frameTolerance: CGFloat = 1) -> Int {
        let snapshots = windows.compactMap { window -> MultiWindowManager.TilingWindow? in
            let frame = window.frame
            guard !frame.isNull else { return nil }
            return MultiWindowManager.TilingWindow(element: window, frame: frame, windowId: window.windowId,
                                                   pid: window.pid, isFocused: window == focusedWindow)
        }
        let current = MultiWindowManager.selectCurrentSpaceWindows(snapshots, visibleWindowInfo: visibleWindowInfo,
                                                                   frameTolerance: frameTolerance)
        let ordered = MultiWindowManager.orderForBandTiling(current, direction: .rows)
        let cells = cellFrames(visibleFrame: visibleFrame,
                               gapSize: Defaults.gapSize.value,
                               skipTopGap: Defaults.skipGapTopEdge.enabled)

        for (index, candidate) in ordered.enumerated() {
            place(candidate, in: cells[index % cells.count])
        }
        return ordered.count
    }

    /// The eighths cells for a visible frame in Cocoa coordinates, with gaps applied,
    /// returned as AX frames in reading order (top row first, then left to right).
    static func cellFrames(visibleFrame: CGRect, gapSize: Float, skipTopGap: Bool) -> [CGRect] {
        cellCalculations.map { calculation in
            var rect = calculation.orientationBasedRect(visibleFrame).rect
            if gapSize > 0 {
                // Edges are shared unless they lie on the work area's border. The
                // eighths' own sub-actions assume landscape, which portrait breaks.
                // Cells are floored, so a border edge can fall up to 3 points short.
                let borderSlack: CGFloat = 4
                var sharedEdges: Edge = []
                if rect.minX - visibleFrame.minX > borderSlack { sharedEdges.insert(.left) }
                if visibleFrame.maxX - rect.maxX > borderSlack { sharedEdges.insert(.right) }
                if rect.minY - visibleFrame.minY > borderSlack { sharedEdges.insert(.bottom) }
                if visibleFrame.maxY - rect.maxY > borderSlack { sharedEdges.insert(.top) }
                rect = GapCalculation.applyGaps(rect, dimension: .both, sharedEdges: sharedEdges,
                                                gapSize: gapSize, skipTopGap: skipTopGap)
            }
            return rect.screenFlipped
        }
    }

    private static func place(_ candidate: MultiWindowManager.TilingWindow, in cell: CGRect) {
        let window = candidate.element
        let history = AppDelegate.windowHistory
        // Keep the user's own frame for Restore unless Rectangle placed the window here.
        if let windowId = candidate.windowId,
           history.restoreRects[windowId] == nil || history.lastRectangleActions[windowId]?.rect != candidate.frame {
            history.restoreRects[windowId] = candidate.frame
        }
        WindowAnimator.shared.cancel(for: window)
        window.setFrame(cell)
        if let windowId = candidate.windowId {
            history.lastRectangleActions[windowId] = RectangleAction(action: .turboMode, rect: window.frame, count: 1)
        }
    }
}
