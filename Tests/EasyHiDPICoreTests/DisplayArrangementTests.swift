import CoreGraphics
import EasyHiDPICore
import Testing

// The real desk: a portrait Philips, the main Samsung at the origin, then the VG27A.
private let main = CGRect(x: 0, y: 0, width: 1920, height: 1080)
private let philips = CGRect(x: -900, y: 0, width: 900, height: 1600)
private let vg27a = CGRect(x: 1920, y: 0, width: 1600, height: 900)

private func snap(_ moving: CGRect, to proposed: CGPoint, others: [CGRect], tolerance: CGFloat = 0) -> CGPoint {
    DisplayArrangement.snappedOrigin(of: moving, proposed: proposed, others: others, alignmentTolerance: tolerance)
}

struct DisplayArrangementTests {
    @Test func smallNudgeSlidesAlongTheEdgeWithoutAlignment() {
        #expect(snap(vg27a, to: CGPoint(x: 1930, y: 100), others: [main, philips]) == CGPoint(x: 1920, y: 100))
    }

    @Test func nearbyEdgeLocksWithinTolerance() {
        #expect(snap(vg27a, to: CGPoint(x: 1930, y: 15), others: [main, philips], tolerance: 20) == CGPoint(x: 1920, y: 0))
    }

    @Test func nearbyCentreLocksWithinTolerance() {
        let centred = (1080.0 - 900.0) / 2
        #expect(snap(vg27a, to: CGPoint(x: 1930, y: centred + 10), others: [main, philips], tolerance: 20) == CGPoint(x: 1920, y: centred))
    }

    @Test func droppingOnTheMainDisplayPushesItToTheNearestFreeEdge() {
        #expect(snap(vg27a, to: CGPoint(x: 500, y: 300), others: [main, philips]) == CGPoint(x: 500, y: 1080))
    }

    @Test func canMoveToTheFarSideOfTheOtherExtendedDisplay() {
        #expect(snap(vg27a, to: CGPoint(x: -3000, y: 0), others: [main, philips]) == CGPoint(x: -2500, y: 0))
    }

    @Test func canMoveAboveTheMainDisplay() {
        #expect(snap(vg27a, to: CGPoint(x: 200, y: -1000), others: [main, philips]) == CGPoint(x: 200, y: -900))
    }

    @Test func keepsAtLeastAUsableSharedEdge() {
        let origin = snap(vg27a, to: CGPoint(x: 3000, y: 1100), others: [main, philips])
        #expect(origin == CGPoint(x: 1920, y: 1040))
    }

    @Test func movingABridgeDisplayNeverStrandsTheOneBehindIt() {
        let first = CGRect(x: 0, y: 0, width: 100, height: 100)
        let bridge = CGRect(x: 100, y: 0, width: 100, height: 100)
        let last = CGRect(x: 200, y: 0, width: 100, height: 100)

        let origin = snap(bridge, to: CGPoint(x: 100, y: 500), others: [first, last])
        #expect(origin == CGPoint(x: 100, y: 60))
    }

    @Test func stayedPutWhenNothingIsValid() {
        let first = CGRect(x: 0, y: 0, width: 100, height: 100)
        let farAway = CGRect(x: 5000, y: 5000, width: 100, height: 100)
        let moving = CGRect(x: 100, y: 0, width: 100, height: 100)

        #expect(snap(moving, to: CGPoint(x: 900, y: 900), others: [first, farAway]) == moving.origin)
    }

    @Test func makingADisplayMainShiftsEveryoneAndKeepsTheLayout() {
        let origins = ["samsung": CGPoint(x: 0, y: 0), "philips": CGPoint(x: -810, y: 0), "vg27a": CGPoint(x: 1920, y: 40)]
        let updated = DisplayArrangement.originsMakingMain("vg27a", from: origins)

        #expect(updated == ["samsung": CGPoint(x: -1920, y: -40), "philips": CGPoint(x: -2730, y: -40), "vg27a": CGPoint(x: 0, y: 0)])
    }

    @Test func makingAnUnknownDisplayMainChangesNothing() {
        let origins = ["samsung": CGPoint(x: 0, y: 0)]
        #expect(DisplayArrangement.originsMakingMain("other", from: origins) == origins)
    }

    @Test func resultNeverOverlapsAnythingFromAnywhere() {
        let others = [main, philips]
        for x in stride(from: -4000.0, through: 4000.0, by: 400.0) {
            for y in stride(from: -3000.0, through: 3000.0, by: 400.0) {
                let origin = snap(vg27a, to: CGPoint(x: x, y: y), others: others, tolerance: 30)
                let frame = CGRect(origin: origin, size: vg27a.size)
                for other in others {
                    let overlap = frame.intersection(other)
                    #expect(overlap.isNull || overlap.width == 0 || overlap.height == 0)
                }
            }
        }
    }
}
