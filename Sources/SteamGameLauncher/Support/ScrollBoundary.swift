import SwiftUI
import AppKit

/// Prevent top overscroll beneath the frosted header while preserving bottom bounce.
struct ScrollBoundary: NSViewRepresentable {
    func makeNSView(context: Context) -> BoundaryView { BoundaryView() }
    func updateNSView(_ view: BoundaryView, context: Context) { view.attachWhenReady() }

    final class BoundaryView: NSView {
        private weak var scrollView: NSScrollView?
        private var observer: NSObjectProtocol?
        private var originalElasticity: NSScrollView.Elasticity = .automatic
        private var originalNotifications = false
        private var updating = false

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window == nil { detach() } else { attachWhenReady() }
        }
        override func viewDidMoveToSuperview() {
            super.viewDidMoveToSuperview(); attachWhenReady()
        }
        func attachWhenReady() {
            DispatchQueue.main.async { [weak self] in
                guard let self, self.window != nil, let enclosing = self.enclosingScrollView else { return }
                if self.scrollView !== enclosing { self.attach(enclosing) }
                self.updateBoundary()
            }
        }
        private func attach(_ scroll: NSScrollView) {
            detach(); scrollView = scroll
            originalElasticity = scroll.verticalScrollElasticity
            originalNotifications = scroll.contentView.postsBoundsChangedNotifications
            scroll.contentView.postsBoundsChangedNotifications = true
            observer = NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification,
                object: scroll.contentView, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.updateBoundary() }
                }
        }
        private func updateBoundary() {
            guard !updating, let scrollView, let document = scrollView.documentView else { return }
            updating = true; defer { updating = false }
            let clip = scrollView.contentView
            let documentRect = clip.documentRect
            let flipped = document.isFlipped
            let top = flipped ? documentRect.minY - scrollView.contentInsets.top
                : documentRect.maxY - clip.bounds.height + scrollView.contentInsets.top
            let origin = clip.bounds.origin
            let atTop = flipped ? origin.y <= top + 0.5 : origin.y >= top - 0.5
            scrollView.verticalScrollElasticity = atTop ? .none : originalElasticity
            let beyondTop = flipped ? origin.y < top : origin.y > top
            // Clamp immediately if an inertial event crosses the boundary from below.
            if beyondTop {
                clip.scroll(to: NSPoint(x: origin.x, y: top))
                scrollView.reflectScrolledClipView(clip)
            }
        }
        private func detach() {
            if let observer { NotificationCenter.default.removeObserver(observer); self.observer = nil }
            scrollView?.verticalScrollElasticity = originalElasticity
            scrollView?.contentView.postsBoundsChangedNotifications = originalNotifications
            scrollView = nil
        }
        deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }
    }
}
