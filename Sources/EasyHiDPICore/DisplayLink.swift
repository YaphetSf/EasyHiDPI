import Foundation

/// How the Mac reaches a display, from the IORegistry's DisplayPort transport state. The HDMI port
/// reports here too, as DisplayPort into a built-in converter.
public struct DisplayLink: Hashable, Sendable {
    public let port: String
    public let rate: String
    public let lanes: Int
    public let maxLanes: Int
    public let converter: String?
    public let edid: [UInt8]

    public init?(properties: [String: Any]) {
        guard let transport = properties["TransportDescription"] as? String,
              let rate = properties["LinkRateDescription"] as? String,
              let lanes = properties["LaneCount"] as? Int,
              let metadata = properties["Metadata"] as? [String: Any],
              let edid = metadata["EDID"] as? Data else { return nil }
        port = transport.split(separator: "/").first.map(String.init) ?? transport
        self.rate = rate
        self.lanes = lanes
        maxLanes = properties["MaxLaneCount"] as? Int ?? lanes
        self.edid = [UInt8](edid)
        converter = (metadata["BranchDeviceID"] as? String).map { chip in
            let output = metadata["DFP Type Description"] as? String
            return [chip, output].compactMap { $0 }.joined(separator: " to ")
        }
    }

    public var identity: EDIDIdentity? {
        EDIDIdentity(edid: edid)
    }

    public var label: String {
        let width = lanes == maxLanes ? "x\(lanes)" : "x\(lanes) of \(maxLanes)"
        let via = converter.map { " via \($0)" } ?? ""
        return "\(port) \(rate) \(width)\(via)"
    }

    public var edidHex: String {
        edid.map { String(format: "%02x", $0) }.joined()
    }
}
