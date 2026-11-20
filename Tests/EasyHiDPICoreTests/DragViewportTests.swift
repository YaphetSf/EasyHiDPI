import CoreGraphics
import EasyHiDPICore
import Testing

// The desk as arranged now: both side displays centred on the main Samsung.
private let main = CGRect(x: 0, y: 0, width: 1920, height: 1080)
private let philips = CGRect(x: -1440, y: 135, width: 1440, height: 810)
private let vg27a = CGRect(x: 1920, y: 135, width: 1440, height: 810)

struct DragViewportTests {
    @Test func stepsGoFromFineToWide() {
        let steps = DragViewport.steps(of: vg27a, among: [main, philips])
        #expect(steps == [
            DragViewport.fine(of: vg27a),
            DragViewport.close(of: vg27a, among: [main, philips]),
            DragViewport.wide(of: vg27a, among: [main, philips])
        ])
    }

    @Test func fineViewShowsAQuarterOfTheDisplayOnEverySide() {
        #expect(DragViewport.fine(of: vg27a) == CGRect(x: 1560, y: -67.5, width: 2160, height: 1215))
    }

    @Test func closeViewHoldsOnlyTheDisplayAndWhatItTouches() {
        #expect(DragViewport.close(of: vg27a, among: [main, philips]) == CGRect(x: -288, y: -162, width: 3936, height: 1404))
    }

    @Test func closeViewFallsBackToTheWideViewWhenNothingTouches() {
        let stray = CGRect(x: 5000, y: 0, width: 1440, height: 810)
        #expect(DragViewport.close(of: stray, among: [main]) == DragViewport.wide(of: stray, among: [main]))
    }

    @Test func wideViewLeavesRoomForTheDisplayOnEverySide() {
        #expect(DragViewport.wide(of: vg27a, among: [main, philips]) == CGRect(x: -2880, y: -810, width: 6240, height: 2700))
    }
}
