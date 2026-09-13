import SwiftUI

/// Lays labels along a horizontal scale drawn beneath or above them.
///
/// Each label is centred on its `scalePosition` (0 to 1 across the scale,
/// which starts and ends `inset` points in from the edges, matching the
/// drawing), then pulled back inside the bounds so none is clipped. Labels
/// keep their natural size, so they follow Dynamic Type.
struct ScaleLabelLayout: Layout {
    var inset = 0.0

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let height = subviews.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0
        return CGSize(width: proposal.replacingUnspecifiedDimensions().width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let scaleWidth = bounds.width - 2 * inset
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            let centre = bounds.minX + inset + scaleWidth * subview[ScalePosition.self]
            let x = min(max(centre - size.width / 2, bounds.minX), bounds.maxX - size.width)
            subview.place(at: CGPoint(x: x, y: bounds.minY), proposal: ProposedViewSize(size))
        }
    }
}
