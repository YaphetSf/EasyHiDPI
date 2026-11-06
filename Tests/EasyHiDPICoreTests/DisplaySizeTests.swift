import EasyHiDPICore
import Testing

struct DisplaySizeTests {
    @Test(arguments: ["1920x1080", "1920\u{00D7}1080", "1920 1080", " 1920 x 1080 "])
    func parsesCommonSpellings(text: String) {
        #expect(DisplaySize(parsing: text) == DisplaySize(width: 1920, height: 1080))
    }

    @Test(arguments: ["", "1920", "1920x", "0x1080", "1920x1080x60", "99999x1080", "abc"])
    func rejectsAnythingElse(text: String) {
        #expect(DisplaySize(parsing: text) == nil)
    }

    @Test func rotationSwapsOnlyQuarterTurns() {
        let size = DisplaySize(width: 900, height: 1600)
        #expect(size.oriented(rotationDegrees: 90) == DisplaySize(width: 1600, height: 900))
        #expect(size.oriented(rotationDegrees: 270) == DisplaySize(width: 1600, height: 900))
        #expect(size.oriented(rotationDegrees: 180) == size)
        #expect(size.oriented(rotationDegrees: 0) == size)
    }
}
