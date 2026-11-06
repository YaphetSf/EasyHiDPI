import EasyHiDPICore
import Testing

struct DDCTests {
    @Test func readRequestMatchesTheWireFormat() {
        #expect(DDC.readRequest(code: 0x10) == [0x82, 0x01, 0x10, 0x6E ^ 0x51 ^ 0x82 ^ 0x01 ^ 0x10])
    }

    @Test func writeRequestCarriesBigEndianValueAndChecksum() {
        let hi: UInt8 = 0x00
        let lo: UInt8 = 0x46
        #expect(DDC.writeRequest(code: 0x10, value: 70) == [0x84, 0x03, 0x10, hi, lo, 0x6E ^ 0x51 ^ 0x84 ^ 0x03 ^ 0x10 ^ hi ^ lo])
    }

    @Test func writeRequestClampsOutOfRangeValues() {
        #expect(DDC.writeRequest(code: 0x10, value: -5)[3...4] == [0x00, 0x00])
    }

    // Replies captured from a real ASUS VG27A and Philips 243B1JH.
    @Test func parsesRealReplies() {
        let asus: [UInt8] = [0x6E, 0x88, 0x02, 0x00, 0x10, 0x00, 0x00, 0x64, 0x00, 0x64, 0xA4]
        #expect(DDC.parseReply(asus, code: 0x10) == DDCReading(current: 100, maximum: 100))

        let philips: [UInt8] = [0x6E, 0x88, 0x02, 0x00, 0x10, 0x00, 0x00, 0x64, 0x00, 0x63, 0xA3]
        #expect(DDC.parseReply(philips, code: 0x10) == DDCReading(current: 99, maximum: 100))
    }

    // A real Samsung S32B80P sends this on quick repeat reads: a null header over its last reply's payload.
    @Test func acceptsSamsungHeaderQuirkWhenThePayloadChecksOut() {
        let samsung: [UInt8] = [0x6E, 0x80, 0xBE, 0x00, 0x10, 0x00, 0x00, 0x64, 0x00, 0x64, 0xA4]
        #expect(DDC.parseReply(samsung, code: 0x10) == DDCReading(current: 100, maximum: 100))

        var corrupted = samsung
        corrupted[9] = 0x20
        #expect(DDC.parseReply(corrupted, code: 0x10) == nil)
    }

    // Captured from a real Samsung S32B80P set to 76 by hand: the first read, then a quick repeat.
    @Test func readsTheSameValueFromAFirstReadAndARepeat() {
        let first: [UInt8] = [0x6E, 0x88, 0x02, 0x00, 0x10, 0x00, 0x00, 0x64, 0x00, 0x4C, 0x8C]
        let repeated: [UInt8] = [0x6E, 0x80, 0xBE, 0x00, 0x10, 0x00, 0x00, 0x64, 0x00, 0x4C, 0x8C]

        #expect(DDC.parseReply(first, code: 0x10) == DDCReading(current: 76, maximum: 100))
        #expect(DDC.parseReply(repeated, code: 0x10) == DDCReading(current: 76, maximum: 100))
    }

    // A real Samsung S32B80P returned this just after a power cycle: a null header over EDID bytes.
    @Test func rejectsANullHeaderOverOtherData() {
        let reply: [UInt8] = [0x6E, 0x80, 0xBE, 0x00, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x00]
        #expect(DDC.parseReply(reply, code: 0x10) == nil)
    }

    // A real Philips 243B1JH returns zeros when read back too quickly.
    @Test func rejectsAllZeroReply() {
        #expect(DDC.parseReply([UInt8](repeating: 0, count: 11), code: 0x10) == nil)
    }

    @Test func rejectsBadChecksumOtherCodeAndUnsupportedFlag() {
        let good: [UInt8] = [0x6E, 0x88, 0x02, 0x00, 0x10, 0x00, 0x00, 0x64, 0x00, 0x64, 0xA4]
        var badChecksum = good
        badChecksum[10] = 0x00
        #expect(DDC.parseReply(badChecksum, code: 0x10) == nil)
        #expect(DDC.parseReply(good, code: 0x12) == nil)

        var unsupported = good
        unsupported[3] = 0x01
        #expect(DDC.parseReply(unsupported, code: 0x10) == nil)
        #expect(DDC.parseReply(Array(good.prefix(8)), code: 0x10) == nil)
    }
}

struct EDIDIdentityTests {
    private func edid(vendor: [UInt8], product: [UInt8], serial: [UInt8]) -> [UInt8] {
        [0x00, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x00] + vendor + product + serial + [UInt8](repeating: 0, count: 240)
    }

    @Test func readsVendorProductAndSerial() {
        // VG27A: AUS 0x06B3, product 0x2783 little-endian, serial 16843009 little-endian.
        let identity = EDIDIdentity(edid: edid(vendor: [0x06, 0xB3], product: [0x83, 0x27], serial: [0x01, 0x01, 0x01, 0x01]))
        #expect(identity == EDIDIdentity(display: DisplayIdentity(vendor: 1715, product: 10115), serial: 16_843_009))
    }

    @Test func rejectsMissingHeaderOrShortData() {
        #expect(EDIDIdentity(edid: [UInt8](repeating: 0, count: 256)) == nil)
        #expect(EDIDIdentity(edid: [0x00, 0xFF]) == nil)
    }

    private let asus = DisplayIdentity(vendor: 1715, product: 10115)
    private let philips = DisplayIdentity(vendor: 16652, product: 2404)

    @Test func matchesEachDisplayToItsOwnEndpoint() {
        let matched = matchEndpoints(
            displays: [
                (id: 1, identity: EDIDIdentity(display: asus, serial: 7)),
                (id: 2, identity: EDIDIdentity(display: philips, serial: 9))
            ],
            endpoints: [
                (identity: EDIDIdentity(display: philips, serial: 9), endpoint: "philips"),
                (identity: EDIDIdentity(display: asus, serial: 7), endpoint: "asus")
            ]
        )
        #expect(matched == [1: "asus", 2: "philips"])
    }

    @Test func identicalMonitorsGetDistinctEndpoints() {
        let identity = EDIDIdentity(display: asus, serial: 16_843_009)
        let matched = matchEndpoints(
            displays: [(id: 1, identity: identity), (id: 2, identity: identity)],
            endpoints: [(identity: identity, endpoint: "first"), (identity: identity, endpoint: "second")]
        )
        #expect(matched == [1: "first", 2: "second"])
    }

    @Test func serialMismatchFallsBackToVendorAndProductButUnknownDisplayStaysUnmatched() {
        let matched = matchEndpoints(
            displays: [
                (id: 1, identity: EDIDIdentity(display: asus, serial: 0)),
                (id: 2, identity: EDIDIdentity(display: philips, serial: 9))
            ],
            endpoints: [(identity: EDIDIdentity(display: asus, serial: 7), endpoint: "asus")]
        )
        #expect(matched == [1: "asus"])
    }
}
