import CoreGraphics

/// The parts of the arrangement the map shows while a display is dragged, in global display points.
public enum DragViewport {
    private static let fineMargin: CGFloat = 0.25
    private static let closeMargin: CGFloat = 0.2

    /// The views a drag steps through, closest first: it starts on the first and moves to the next
    /// each time the cursor reaches an edge of the map.
    public static func steps(of moving: CGRect, among others: [CGRect]) -> [CGRect] {
        [fine(of: moving), close(of: moving, among: others), wide(of: moving, among: others)]
    }

    /// The display with a quarter of its size around it, enough to show the edge of a neighbour,
    /// so a small move of the cursor is a small move of the display.
    public static func fine(of moving: CGRect) -> CGRect {
        moving.insetBy(dx: -moving.width * fineMargin, dy: -moving.height * fineMargin)
    }

    /// The display and the displays it touches, with a little room around.
    public static func close(of moving: CGRect, among others: [CGRect]) -> CGRect {
        let touching = others.filter { DisplayArrangement.sharesEdge(moving, $0) }
        guard !touching.isEmpty else { return wide(of: moving, among: others) }
        return touching
            .reduce(moving) { $0.union($1) }
            .insetBy(dx: -moving.width * closeMargin, dy: -moving.height * closeMargin)
    }

    /// Every other display with room for the moving one on each side.
    public static func wide(of moving: CGRect, among others: [CGRect]) -> CGRect {
        others
            .reduce(CGRect.null) { $0.union($1) }
            .insetBy(dx: -moving.width, dy: -moving.height)
    }
}
