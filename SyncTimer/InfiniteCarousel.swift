import SwiftUI

/// A performant, infinite‐looping horizontal carousel.
public struct InfiniteCarousel<Data: RandomAccessCollection, Content: View>: View
  where Data.Element: Identifiable
{
  private let items: [Data.Element]
  private let spacing: CGFloat        // spacing between items
  private let speed: CGFloat          // points per second
  private let content: (Data.Element) -> Content

  @State private var offset: CGFloat = 0
  @State private var halfWidth: CGFloat = 0
  private let timer = Timer.publish(every: 1/60, on: .main, in: .common).autoconnect()

  public init(
    _ data: Data,
    spacing: CGFloat = 12,
    speed: CGFloat = 30,
    @ViewBuilder content: @escaping (Data.Element) -> Content
  ) {
    self.items = Array(data)
    self.spacing = spacing
    self.speed = speed
    self.content = content
  }

  public var body: some View {
    GeometryReader { geo in
      HStack(spacing: spacing) {
        // duplicate the sequence twice
        ForEach(items) { item in content(item).fixedSize() }
        ForEach(items) { item in content(item).fixedSize() }
      }
      // measure one loop’s width (half of the HStack)
      .background(
        GeometryReader { g in
          Color.clear
            .onAppear { halfWidth = g.size.width / 2 }
        }
      )
      // slide
      .offset(x: offset)
      // update on every tick
      .onReceive(timer) { _ in
        let shift = speed / 60
        offset -= shift
        // when we've shifted past one cycle, wrap back
        if abs(offset) >= halfWidth {
          offset += halfWidth
        }
      }
      // constrain to the parent’s width and clip overflow
      .frame(width: geo.size.width, alignment: .leading)
      .clipped()
    }
    // you can adjust this height as needed
    .frame(height: 80)
  }
}
