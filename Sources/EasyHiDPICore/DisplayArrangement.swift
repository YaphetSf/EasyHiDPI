import CoreGraphics

/// Where a dragged display lands. A valid spot overlaps nothing and keeps every display in one
/// connected group, so moving a display that bridges two others can never strand one of them.
public enum DisplayArrangement {
    private static let minimumSharedEdge: CGFloat = 40

    /// Returns the valid origin nearest to `proposed`, or the current origin if there is none.
    /// `alignmentTolerance` is in the same points as the rects: within it, the display locks to a
    /// neighbour's start, centre or end.
    public static func snappedOrigin(
        of moving: CGRect,
        proposed: CGPoint,
        others: [CGRect],
        alignmentTolerance: CGFloat
    ) -> CGPoint {
        let candidates = others.flatMap {
            placements(of: moving.size, around: $0, proposed: proposed, tolerance: alignmentTolerance)
        }
        let valid = candidates.filter { origin in
            let frame = CGRect(origin: origin, size: moving.size)
            return !others.contains { overlaps(frame, $0) } && isConnected([frame] + others)
        }
        let nearest = valid.min { distance($0, proposed) < distance($1, proposed) }
        return nearest ?? moving.origin
    }

    /// macOS treats the display at (0, 0) as main, so changing it shifts every display equally,
    /// which leaves the physical layout exactly as it was.
    public static func originsMakingMain<ID: Hashable>(_ id: ID, from origins: [ID: CGPoint]) -> [ID: CGPoint] {
        guard let target = origins[id] else { return origins }
        return origins.mapValues { CGPoint(x: $0.x - target.x, y: $0.y - target.y) }
    }

    private static func placements(
        of size: CGSize,
        around other: CGRect,
        proposed: CGPoint,
        tolerance: CGFloat
    ) -> [CGPoint] {
        let y = along(proposed.y, length: size.height, neighbourStart: other.minY, neighbourLength: other.height, tolerance: tolerance)
        let x = along(proposed.x, length: size.width, neighbourStart: other.minX, neighbourLength: other.width, tolerance: tolerance)
        return [
            CGPoint(x: other.minX - size.width, y: y),
            CGPoint(x: other.maxX, y: y),
            CGPoint(x: x, y: other.minY - size.height),
            CGPoint(x: x, y: other.maxY)
        ]
    }

    private static func along(
        _ proposed: CGFloat,
        length: CGFloat,
        neighbourStart: CGFloat,
        neighbourLength: CGFloat,
        tolerance: CGFloat
    ) -> CGFloat {
        let required = min(minimumSharedEdge, length, neighbourLength)
        let lowest = neighbourStart - length + required
        let highest = neighbourStart + neighbourLength - required
        let clamped = min(max(proposed, lowest), highest)

        let alignments = [
            neighbourStart,
            neighbourStart + (neighbourLength - length) / 2,
            neighbourStart + neighbourLength - length
        ]
        let closest = alignments.min { abs($0 - clamped) < abs($1 - clamped) } ?? clamped
        let value = abs(closest - clamped) <= tolerance ? closest : clamped
        return value.rounded()
    }

    private static func overlaps(_ first: CGRect, _ second: CGRect) -> Bool {
        first.minX < second.maxX && first.maxX > second.minX
            && first.minY < second.maxY && first.maxY > second.minY
    }

    private static func sharesEdge(_ first: CGRect, _ second: CGRect) -> Bool {
        let overlapX = min(first.maxX, second.maxX) - max(first.minX, second.minX)
        let overlapY = min(first.maxY, second.maxY) - max(first.minY, second.minY)
        let touchesSideways = first.maxX == second.minX || second.maxX == first.minX
        let touchesVertically = first.maxY == second.minY || second.maxY == first.minY
        return (touchesSideways && overlapY > 0) || (touchesVertically && overlapX > 0)
    }

    private static func isConnected(_ frames: [CGRect]) -> Bool {
        guard let first = frames.first else { return true }
        var reached = [first]
        var remaining = Array(frames.dropFirst())
        while let index = remaining.firstIndex(where: { candidate in
            reached.contains { sharesEdge($0, candidate) }
        }) {
            reached.append(remaining.remove(at: index))
        }
        return remaining.isEmpty
    }

    private static func distance(_ first: CGPoint, _ second: CGPoint) -> CGFloat {
        let dx = first.x - second.x
        let dy = first.y - second.y
        return dx * dx + dy * dy
    }
}
