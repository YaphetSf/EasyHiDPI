/// The quarter turns System Settings offers, in degrees clockwise.
public enum DisplayRotation {
    public static let all = [0, 90, 180, 270]

    public static func label(_ degrees: Int) -> String { "\(degrees)\u{00B0}" }

    /// Whether turning a display from one rotation to another swaps its width and height.
    public static func swapsAxes(from current: Int, to target: Int) -> Bool {
        (target - current) % 180 != 0
    }
}
