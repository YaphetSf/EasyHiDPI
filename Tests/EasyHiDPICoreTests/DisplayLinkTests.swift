import EasyHiDPICore
import Foundation
import Testing

private func bytes(_ hex: String) -> Data {
    Data(stride(from: 0, to: hex.count, by: 2).map { offset in
        let start = hex.index(hex.startIndex, offsetBy: offset)
        return UInt8(hex[start..<hex.index(start, offsetBy: 2)], radix: 16)!
    })
}

struct DisplayLinkTests {
    // Trimmed from the IORegistry of a Samsung S32B80P on USB-C, with its serial zeroed.
    @Test func directUSBCLink() throws {
        let link = try #require(DisplayLink(properties: [
            "TransportDescription": "Port-USB-C@1/DisplayPort",
            "LinkRateDescription": "5.4 Gbps (HBR2)",
            "LaneCount": 4,
            "MaxLaneCount": 4,
            "Metadata": ["EDID": bytes("00ffffffffffff004c2df37100000000")]
        ]))

        #expect(link.label == "Port-USB-C@1 5.4 Gbps (HBR2) x4")
        #expect(link.identity == EDIDIdentity(display: DisplayIdentity(vendor: 0x4C2D, product: 0x71F3), serial: 0))
        #expect(link.edidHex == "00ffffffffffff004c2df37100000000")
    }

    // Trimmed from the IORegistry of a Philips 243B1JH on a Mac's HDMI port, with its serial zeroed.
    @Test func hdmiPortShowsItsConverter() throws {
        let link = try #require(DisplayLink(properties: [
            "TransportDescription": "Port-HDMI@2/DisplayPort",
            "LinkRateDescription": "8.1 Gbps (HBR3)",
            "LaneCount": 4,
            "MaxLaneCount": 4,
            "Metadata": [
                "BranchDeviceID": "pHDMIg",
                "DFP Type Description": "HDMI",
                "EDID": bytes("00ffffffffffff00410c640900000000")
            ]
        ]))

        #expect(link.label == "Port-HDMI@2 8.1 Gbps (HBR3) x4 via pHDMIg to HDMI")
        #expect(link.identity == EDIDIdentity(display: DisplayIdentity(vendor: 0x410C, product: 0x964), serial: 0))
    }

    @Test func nodeWithoutALiveLinkIsSkipped() {
        #expect(DisplayLink(properties: ["TransportDescription": "Port-USB-C@1/DisplayPort"]) == nil)
    }
}
