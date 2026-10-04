/// TurboModeTests.swift

import XCTest
@testable import Rectangle

class TurboModeTests: XCTestCase {

    private final class TestWindow: AccessibilityElement {
        private var acceptedFrame: CGRect
        private let testWindowId: CGWindowID
        private(set) var setFrameCalls = 0

        init(frame: CGRect, windowId: CGWindowID) {
            acceptedFrame = frame
            testWindowId = windowId
            super.init(AXUIElementCreateApplication(pid_t(20_000 + Int32(windowId))))
        }

        override var frame: CGRect { acceptedFrame }
        override var windowId: CGWindowID? { testWindowId }
        override var pid: pid_t? { 42 }
        override var isWindow: Bool? { true }
        override var isSheet: Bool? { false }
        override var isMinimized: Bool? { false }
        override var isHidden: Bool? { false }
        override var isSystemDialog: Bool? { false }

        override func setFrame(_ frame: CGRect, adjustSizeFirst: Bool = true, adjustPosition: Bool = true) {
            setFrameCalls += 1
            acceptedFrame = frame
        }
    }

    private func visible(_ window: TestWindow) -> WindowInfo {
        WindowInfo(id: window.windowId!, level: 0, frame: window.frame, pid: 42, processName: nil)
    }

    private func forget(_ windows: [TestWindow]) {
        for window in windows {
            AppDelegate.windowHistory.restoreRects.removeValue(forKey: window.windowId!)
            AppDelegate.windowHistory.lastRectangleActions.removeValue(forKey: window.windowId!)
        }
    }

    func testLandscapeCellsAreFourByTwoInReadingOrder() {
        let workArea = CGRect(x: 0, y: 0, width: 5120, height: 1410)
        let cells = TurboModeManager.cellFrames(visibleFrame: workArea, gapSize: 0, skipTopGap: false)
        let flipped = workArea.screenFlipped

        XCTAssertEqual(cells.count, 8)
        for (index, cell) in cells.enumerated() {
            XCTAssertEqual(cell.size, CGSize(width: 1280, height: 705))
            XCTAssertEqual(cell.minX, flipped.minX + CGFloat(index % 4) * 1280)
            XCTAssertEqual(cell.minY, flipped.minY + CGFloat(index / 4) * 705)
        }
    }

    func testPortraitCellsAreTwoByFourInReadingOrder() {
        let workArea = CGRect(x: 0, y: 0, width: 1000, height: 2000)
        let cells = TurboModeManager.cellFrames(visibleFrame: workArea, gapSize: 0, skipTopGap: false)
        let flipped = workArea.screenFlipped

        XCTAssertEqual(cells.count, 8)
        for (index, cell) in cells.enumerated() {
            XCTAssertEqual(cell.size, CGSize(width: 500, height: 500))
            XCTAssertEqual(cell.minX, flipped.minX + CGFloat(index % 2) * 500)
            XCTAssertEqual(cell.minY, flipped.minY + CGFloat(index / 2) * 500)
        }
    }

    func testGapsSeparateCellsAndBorderByTheGapSizeInBothOrientations() {
        for workArea in [CGRect(x: 0, y: 0, width: 5120, height: 1410),
                         CGRect(x: 0, y: 0, width: 1000, height: 2000)] {
            let cells = TurboModeManager.cellFrames(visibleFrame: workArea, gapSize: 10, skipTopGap: false)
            let flipped = workArea.screenFlipped
            let columns = workArea.isLandscape ? 4 : 2
            let rows = 8 / columns

            for (index, cell) in cells.enumerated() {
                let column = index % columns
                let row = index / columns
                if column == 0 { XCTAssertEqual(cell.minX - flipped.minX, 10) }
                if column == columns - 1 { XCTAssertEqual(flipped.maxX - cell.maxX, 10) }
                if column > 0 { XCTAssertEqual(cell.minX - cells[index - 1].maxX, 10) }
                if row == 0 { XCTAssertEqual(cell.minY - flipped.minY, 10) }
                if row == rows - 1 { XCTAssertEqual(flipped.maxY - cell.maxY, 10) }
                if row > 0 { XCTAssertEqual(cell.minY - cells[index - columns].maxY, 10) }
            }
        }
    }

    func testArrangeFillsCellsByCurrentPositionAndARepeatKeepsThem() {
        let workArea = CGRect(x: 0, y: 0, width: 4000, height: 1000)
        let cells = TurboModeManager.cellFrames(visibleFrame: workArea, gapSize: Defaults.gapSize.value,
                                                skipTopGap: Defaults.skipGapTopEdge.enabled)
        let origin = workArea.screenFlipped.origin
        // Listed out of order; reading order of the current frames decides the cells.
        let right = TestWindow(frame: CGRect(x: origin.x + 900, y: origin.y, width: 300, height: 300), windowId: 9_101)
        let lower = TestWindow(frame: CGRect(x: origin.x, y: origin.y + 600, width: 300, height: 300), windowId: 9_102)
        let left = TestWindow(frame: CGRect(x: origin.x + 100, y: origin.y, width: 300, height: 300), windowId: 9_103)
        let windows = [right, lower, left]
        defer { forget(windows) }

        let placed = TurboModeManager.arrange(windows: windows, focusedWindow: right,
                                              visibleWindowInfo: windows.map(visible), visibleFrame: workArea)

        XCTAssertEqual(placed, 3)
        XCTAssertEqual(left.frame, cells[0])
        XCTAssertEqual(right.frame, cells[1])
        XCTAssertEqual(lower.frame, cells[2])

        TurboModeManager.arrange(windows: windows, focusedWindow: lower,
                                 visibleWindowInfo: windows.map(visible), visibleFrame: workArea)
        XCTAssertEqual([left.frame, right.frame, lower.frame], Array(cells[0..<3]))
    }

    func testArrangeSkipsWindowsOffTheCurrentSpaceAndWrapsPastEightWindows() {
        let workArea = CGRect(x: 0, y: 0, width: 4000, height: 1000)
        let cells = TurboModeManager.cellFrames(visibleFrame: workArea, gapSize: Defaults.gapSize.value,
                                                skipTopGap: Defaults.skipGapTopEdge.enabled)
        let origin = workArea.screenFlipped.origin
        let onSpace = (0..<9).map { index in
            TestWindow(frame: CGRect(x: origin.x + CGFloat(index) * 10, y: origin.y, width: 200, height: 200),
                       windowId: CGWindowID(9_200 + index))
        }
        let otherSpace = TestWindow(frame: CGRect(x: origin.x + 5, y: origin.y, width: 200, height: 200), windowId: 9_299)
        let otherSpaceFrame = otherSpace.frame
        defer { forget(onSpace + [otherSpace]) }

        let placed = TurboModeManager.arrange(windows: onSpace + [otherSpace], focusedWindow: onSpace[0],
                                              visibleWindowInfo: onSpace.map(visible), visibleFrame: workArea)

        XCTAssertEqual(placed, 9)
        for (index, window) in onSpace.enumerated() {
            XCTAssertEqual(window.frame, cells[index % 8])
        }
        XCTAssertEqual(otherSpace.setFrameCalls, 0)
        XCTAssertEqual(otherSpace.frame, otherSpaceFrame)
    }

    func testRestoreKeepsTheFrameFromBeforeTheFirstTurbo() {
        let workArea = CGRect(x: 0, y: 0, width: 4000, height: 1000)
        let original = CGRect(x: workArea.screenFlipped.minX + 123, y: workArea.screenFlipped.minY + 45,
                              width: 777, height: 555)
        let window = TestWindow(frame: original, windowId: 9_301)
        defer { forget([window]) }

        for _ in 0..<2 {
            TurboModeManager.arrange(windows: [window], focusedWindow: window,
                                     visibleWindowInfo: [visible(window)], visibleFrame: workArea)
        }

        XCTAssertNotEqual(window.frame, original)
        XCTAssertEqual(AppDelegate.windowHistory.restoreRects[9_301], original)
        XCTAssertEqual(AppDelegate.windowHistory.lastRectangleActions[9_301]?.action, .turboMode)
    }
}
