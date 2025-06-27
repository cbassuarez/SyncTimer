import SwiftUI

/// A 2-column (or N-column) waterfall layout that always
/// appends each item into the shortest column.
struct MasonryLayout: Layout {
  let columns: Int
  let spacing: CGFloat

  func sizeThatFits(
    proposal: ProposedViewSize,
    subviews: Subviews,
    cache: inout ()
  ) -> CGSize {
    // total width we have to work with
    let totalWidth = proposal.width ?? 0
    let colWidth = (totalWidth - spacing * CGFloat(columns - 1)) / CGFloat(columns)

    // track the running height of each column
    var heights = Array(repeating: CGFloat(0), count: columns)

    // measure every subview and “drop” it into the shortest column
    for sub in subviews {
      let sz = sub.sizeThatFits(.init(width: colWidth, height: nil))
      let idx = heights.enumerated().min(by: { $0.element < $1.element })!.offset
      heights[idx] += sz.height + spacing
    }

    // overall height is the tallest column minus the extra spacing at the end
    let fullH = (heights.max() ?? 0) - spacing
    return CGSize(width: totalWidth, height: fullH)
  }

  func placeSubviews(
    in bounds: CGRect,
    proposal: ProposedViewSize,
    subviews: Subviews,
    cache: inout ()
  ) {
    let totalWidth = bounds.width
    let colWidth = (totalWidth - spacing * CGFloat(columns - 1)) / CGFloat(columns)
    var heights = Array(repeating: CGFloat(0), count: columns)

    for sub in subviews {
      let sz = sub.sizeThatFits(.init(width: colWidth, height: nil))
      let idx = heights.enumerated().min(by: { $0.element < $1.element })!.offset

      let x = bounds.minX + CGFloat(idx) * (colWidth + spacing)
      let y = bounds.minY + heights[idx]

      sub.place(
        at: CGPoint(x: x, y: y),
        proposal: .init(width: colWidth, height: sz.height)
      )

      heights[idx] += sz.height + spacing
    }
  }
}
