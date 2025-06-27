import SwiftUI

/// A reusable infinite-looping horizontal carousel.
struct InfiniteCarousel<Data: RandomAccessCollection, Content: View>: View
  where Data.Element: Identifiable
{
  private let data: Data
  private let itemSpacing: CGFloat
  private let speed: CGFloat      // points per second
  private let content: (Data.Element) -> Content

  @State private var offset: CGFloat = 0
  @State private var totalWidth: CGFloat = .zero

  init(
    _ data: Data,
    itemSpacing: CGFloat = 12,
    speed: CGFloat = 30,
    @ViewBuilder content: @escaping (Data.Element) -> Content
  ) {
    self.data = data
    self.itemSpacing = itemSpacing
    self.speed = speed
    self.content = content
  }

  var body: some View {
    GeometryReader { geo in
      // our “tape” of views
      LazyHStack(spacing: itemSpacing) {
        ForEach(data) { item in
          content(item)
            .fixedSize()
        }
      }
      // measure one full pass width:
      .background(
        GeometryReader { sub in
          Color.clear
            .onAppear { totalWidth = sub.size.width }
        }
      )
      // position it by our offset:
      .offset(x: offset)
      // redraw into a layer for performance:
      .drawingGroup()
      // loop back when we’ve scrolled past one full width:
      .onChange(of: offset) { new in
        if abs(new) >= totalWidth {
          offset += totalWidth * (new>0 ? -1 : 1)
        }
      }
      // drive the scroll with a TimelineView at 60fps:
      .onAppear {
        offset = 0
      }
      .timelineView(.animation) { timeline in
        let dt = timeline.date.timeIntervalSinceReferenceDate
        // delta since last frame:
        let dx = CGFloat(dt - lastUpdate) * speed * (totalWidth>0 ? 1 : 0)
        offset -= dx
        lastUpdate = dt
      }
      .frame(width: geo.size.width, alignment: .leading)
      .clipped()
    }
    .frame(height: 80)    // whatever height you need
  }

  // store last update time
  @State private var lastUpdate: TimeInterval = Date().timeIntervalSinceReferenceDate
}
