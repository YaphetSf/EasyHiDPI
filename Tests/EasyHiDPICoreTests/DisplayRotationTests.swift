import EasyHiDPICore
import Testing

struct DisplayRotationTests {
    @Test func offersTheFourQuarterTurns() {
        #expect(DisplayRotation.all.map(DisplayRotation.label) == ["0\u{00B0}", "90\u{00B0}", "180\u{00B0}", "270\u{00B0}"])
    }

    @Test func onlyAnOddNumberOfQuarterTurnsSwapsAxes() {
        #expect(DisplayRotation.swapsAxes(from: 0, to: 90))
        #expect(DisplayRotation.swapsAxes(from: 90, to: 0))
        #expect(DisplayRotation.swapsAxes(from: 270, to: 0))
        #expect(DisplayRotation.swapsAxes(from: 90, to: 180))
        #expect(!DisplayRotation.swapsAxes(from: 0, to: 180))
        #expect(!DisplayRotation.swapsAxes(from: 90, to: 270))
        #expect(!DisplayRotation.swapsAxes(from: 270, to: 90))
        #expect(!DisplayRotation.swapsAxes(from: 90, to: 90))
    }
}
