import AppKit
import SwiftUI

@MainActor final class ActivityMonitor {
    private var eventMonitor: Any?
    private var timer: Timer?
    private var lastActivity = Date()
    private var wallEnteredAt = Date.distantPast
    private weak var window: NSWindow?
    private weak var store: LibraryStore?
    func start(store: LibraryStore, window: NSWindow) {
        guard eventMonitor == nil else { return }
        self.store = store; self.window = window
        window.acceptsMouseMovedEvents = true
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDown, .rightMouseDown, .keyDown, .scrollWheel, .leftMouseDragged]) { [weak self] event in
            guard let self, let store = self.store else { return event }
            self.lastActivity = Date()
            guard event.window === self.window else { return event }
            if store.showingWall {
                if event.type == .keyDown && event.keyCode == 53 { store.showingWall = false; return nil }
                if store.automaticWall && Date().timeIntervalSince(self.wallEnteredAt) > 1 {
                    store.showingWall = false
                    if event.type == .keyDown || event.type == .leftMouseDown || event.type == .rightMouseDown { return nil }
                }
            }
            return event
        }
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkIdle() }
        }
    }
    func reset() { lastActivity = Date() }
    private func checkIdle() {
        guard let store, let window, store.preferences.idleEnabled, !store.showingWall,
              !store.showingSetup,
              !store.showingAddGame, !store.showingCollections, !store.showingUnlock, !store.showingRemoved, NSApp.isActive, window.isKeyWindow,
              !window.isMiniaturized, window.attachedSheet == nil,
              Date().timeIntervalSince(lastActivity) >= store.preferences.idleMinutes * 60 else { return }
        wallEnteredAt = Date(); store.startWall(automatic: true)
    }
    deinit { if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }; timer?.invalidate() }
}

struct WindowReader: NSViewRepresentable {
    var hidesToolbar: Bool
    var onWindow: (NSWindow) -> Void
    var onTopInset: (CGFloat) -> Void
    func makeNSView(context: Context) -> ReaderView {
        let view = ReaderView(); view.onWindow = onWindow; view.onTopInset = onTopInset; view.hidesToolbar = hidesToolbar; return view
    }
    func updateNSView(_ view: ReaderView, context: Context) {
        view.onWindow = onWindow; view.onTopInset = onTopInset; view.reportTopInset()
        view.hidesToolbar = hidesToolbar
        DispatchQueue.main.async { [weak view] in view?.synchronizeToolbar() }
    }
    final class ReaderView: NSView {
        var onWindow: ((NSWindow) -> Void)?
        var onTopInset: ((CGFloat) -> Void)?
        private var reportedInset: CGFloat = -1
        var hidesToolbar = false
        private var retainedToolbar: NSToolbar?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            window.titleVisibility = .hidden; window.titlebarAppearsTransparent = true
            window.styleMask.insert(.fullSizeContentView)
            window.titlebarSeparatorStyle = .none
            window.backgroundColor = Palette.windowColor
            window.isMovableByWindowBackground = false
            DispatchQueue.main.async { [weak self, weak window] in if let window { self?.onWindow?(window) } }
            reportTopInset()
        }
        override func layout() {
            super.layout(); synchronizeToolbar(); reportTopInset()
        }
        func synchronizeToolbar() {
            guard let window else { return }
            if hidesToolbar {
                // In fullscreen, SwiftUI hides the toolbar items but AppKit can
                // keep an empty toolbar strip. Detach it for the wall.
                if let toolbar = window.toolbar {
                    if retainedToolbar == nil { retainedToolbar = toolbar }
                    window.toolbar = nil
                }
            } else if let retainedToolbar {
                self.retainedToolbar = nil
                window.toolbar = retainedToolbar
            }
        }
        func reportTopInset() {
            guard let window, let content = window.contentView else { return }
            let layout = content.convert(window.contentLayoutRect, from: nil)
            let inset = max(0, content.isFlipped
                ? layout.minY - content.bounds.minY
                : content.bounds.maxY - layout.maxY)
            guard abs(inset - reportedInset) > 0.5 else { return }
            reportedInset = inset
            DispatchQueue.main.async { [weak self] in self?.onTopInset?(inset) }
        }
    }
}
