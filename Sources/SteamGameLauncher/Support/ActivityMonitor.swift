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
        private var fullscreenObserver: NSObjectProtocol?
        private let fullscreenDelegate = FullscreenPresentationDelegate()
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let fullscreenObserver { NotificationCenter.default.removeObserver(fullscreenObserver); self.fullscreenObserver = nil }
            guard let window else { return }
            if window.delegate !== fullscreenDelegate {
                fullscreenDelegate.original = window.delegate
                window.delegate = fullscreenDelegate
            }
            window.titleVisibility = .hidden; window.titlebarAppearsTransparent = true
            window.styleMask.insert(.fullSizeContentView)
            window.titlebarSeparatorStyle = .none
            window.backgroundColor = Palette.windowColor
            window.isMovableByWindowBackground = false
            fullscreenObserver = NotificationCenter.default.addObserver(forName: NSWindow.willEnterFullScreenNotification, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    // Detach before AppKit snapshots its native toolbar for the
                    // fullscreen animation, rather than after the animation.
                    self?.hidesToolbar = true
                    self?.synchronizeToolbar()
                }
            }
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
        deinit { if let fullscreenObserver { NotificationCenter.default.removeObserver(fullscreenObserver) } }
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

/// Standard AppKit controls remain available in the fullscreen content header.
struct FullscreenWindowControls: NSViewRepresentable {
    var window: NSWindow?
    func makeNSView(context: Context) -> ControlsView { ControlsView() }
    func updateNSView(_ view: ControlsView, context: Context) { view.targetWindow = window }
    final class ControlsView: NSView {
        weak var targetWindow: NSWindow? {
            didSet {
                for button in buttons { button.target = targetWindow }
            }
        }
        private var buttons: [NSButton] = []
        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            let controls: [(NSWindow.ButtonType, Selector, String)] = [
                (.closeButton, #selector(NSWindow.performClose(_:)), "关闭窗口"),
                (.miniaturizeButton, #selector(NSWindow.performMiniaturize(_:)), "最小化窗口"),
                (.zoomButton, #selector(NSWindow.toggleFullScreen(_:)), "退出全屏")
            ]
            for (type, action, label) in controls {
                guard let button = NSWindow.standardWindowButton(type, for: .titled) else { continue }
                button.action = action; button.setAccessibilityLabel(label)
                // macOS disables minimization while the window occupies a Space.
                button.isEnabled = type != .miniaturizeButton
                buttons.append(button); addSubview(button)
            }
        }
        required init?(coder: NSCoder) { nil }
        override func layout() {
            super.layout()
            var x: CGFloat = 0
            for button in buttons {
                button.setFrameOrigin(NSPoint(x: x, y: (bounds.height - button.frame.height) / 2))
                x += button.frame.width + 8
            }
        }
    }
}

/// Preserve SwiftUI's delegate while suppressing its separate hover toolbar.
private final class FullscreenPresentationDelegate: NSObject, NSWindowDelegate {
    weak var original: NSWindowDelegate?
    override func responds(to selector: Selector!) -> Bool {
        super.responds(to: selector) || (original?.responds(to: selector) ?? false)
    }
    override func forwardingTarget(for selector: Selector!) -> Any? {
        if original?.responds(to: selector) == true { return original }
        return super.forwardingTarget(for: selector)
    }
    func window(_ window: NSWindow, willUseFullScreenPresentationOptions proposedOptions: NSApplication.PresentationOptions) -> NSApplication.PresentationOptions {
        let options = original?.window?(window, willUseFullScreenPresentationOptions: proposedOptions) ?? proposedOptions
        // The content supplies fullscreen controls. Revealing an empty AppKit
        // toolbar alongside the menu bar would cover them with a black strip.
        return options.subtracting(.autoHideToolbar)
    }
}
