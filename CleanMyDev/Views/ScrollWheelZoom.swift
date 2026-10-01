import SwiftUI
import AppKit

/// Delivers scroll-wheel / trackpad scroll events that land inside the view,
/// with the cursor position in the view's own coordinates. SwiftUI has no
/// scroll-wheel gesture, so this installs a local NSEvent monitor.
struct ScrollWheelZoom: ViewModifier {
    let onScroll: (_ deltaY: CGFloat, _ point: CGPoint) -> Void
    @State private var frame: CGRect = .zero
    @State private var monitor: Any? = nil

    func body(content: Content) -> some View {
        content
            .background(GeometryReader { g in
                Color.clear
                    .onAppear { frame = g.frame(in: .global) }
                    .onChange(of: g.frame(in: .global)) { _, f in frame = f }
            })
            .onAppear {
                monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
                    guard let window = event.window, let content = window.contentView else { return event }
                    let p = event.locationInWindow
                    // Window coordinates are bottom-left; SwiftUI's global space is top-left.
                    let global = CGPoint(x: p.x, y: content.bounds.height - p.y)
                    guard frame.contains(global) else { return event }
                    let local = CGPoint(x: global.x - frame.minX, y: global.y - frame.minY)
                    let delta = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.scrollingDeltaY * 8
                    onScroll(delta, local)
                    return nil
                }
            }
            .onDisappear {
                if let m = monitor { NSEvent.removeMonitor(m) }
                monitor = nil
            }
    }
}
