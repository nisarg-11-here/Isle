import AppKit
import SwiftUI

/// A borderless panel over the notch. Its frame follows the island, so it never
/// blocks clicks on the menu bar beside it.
///
/// The SwiftUI canvas has one fixed size and is pinned to the top of the window. A window
/// resize only clips it. If the canvas resized with the window, SwiftUI would lay out one
/// frame late, and the island would jump down and snap back.
final class IslandPanel: NSPanel {
    private let model: IslandModel
    private let host: IslandHostingView
    private var screenRef: NSScreen?
    private var shrink: DispatchWorkItem?

    init(model: IslandModel) {
        self.model = model
        host = IslandHostingView(rootView: AnyView(IslandView().environment(model)))
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        // Set on purpose. Left unset, the window server sends clicks on fully transparent pixels to
        // the window below, and Liquid Glass leaves the island's own pixels transparent.
        ignoresMouseEvents = false
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]

        host.model = model
        let container = FlippedView()
        container.wantsLayer = true
        container.addSubview(host)
        contentView = container
        model.panel = self

        NotificationCenter.default.addObserver(self, selector: #selector(placeOnScreen),
                                               name: NSApplication.didChangeScreenParametersNotification, object: nil)
        placeOnScreen()
        follow()
        orderFrontRegardless()
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) { model.escape() }

    override func resignKey() {
        super.resignKey()
        if !model.isolated { model.resignedKey() }
    }

    /// Prefer the screen with a notch. Else draw a notch-sized pill on the main screen.
    @objc private func placeOnScreen() {
        let screen = NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main ?? NSScreen.screens[0]
        screenRef = screen
        if screen.safeAreaInsets.top > 0, let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            model.notch = CGSize(width: screen.frame.width - left.width - right.width, height: screen.safeAreaInsets.top)
        } else {
            model.notch = CGSize(width: 185, height: max(24, screen.frame.maxY - screen.visibleFrame.maxY))
        }
        host.setFrameSize(model.canvasSize)
        applyFrame()
    }

    /// Runs `applyFrame` again each time the island's size changes.
    private func follow() {
        withObservationTracking { _ = model.windowSize } onChange: { [weak self] in
            DispatchQueue.main.async {
                self?.applyFrame()
                self?.follow()
            }
        }
    }

    /// Grow at once so the spring has room. Shrink after the spring ends so nothing is clipped.
    private func applyFrame() {
        guard let screen = screenRef else { return }
        let target = model.windowSize
        let current = frame.size
        shrink?.cancel()
        let grown = CGSize(width: max(target.width, current.width), height: max(target.height, current.height))
        resize(to: grown, on: screen)
        guard target.width < current.width || target.height < current.height else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            resize(to: target, on: screen)
        }
        shrink = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    /// Moves the window and re-centers the canvas in the same pass, so both land in one frame.
    private func resize(to size: CGSize, on screen: NSScreen) {
        setFrame(NSRect(x: screen.frame.midX - size.width / 2, y: screen.frame.maxY - size.height,
                        width: size.width, height: size.height), display: false)
        host.setFrameOrigin(NSPoint(x: (size.width - host.frame.width) / 2, y: 0))
        displayIfNeeded()
    }
}

/// Top-left origin, so the canvas stays pinned to the top edge.
private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

/// Hosts the SwiftUI island. Takes the first click without activating the app,
/// and reports when the pointer enters or leaves the panel.
final class IslandHostingView: NSHostingView<AnyView> {
    var model: IslandModel?
    private var hoverArea: NSTrackingArea?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard hoverArea == nil else { return }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                  owner: self)
        addTrackingArea(area)
        hoverArea = area
    }

    // SwiftUI's own hover areas also call these methods. Only ours drives the island.
    override func mouseEntered(with event: NSEvent) {
        if event.trackingArea === hoverArea {
            if model?.isolated == false { model?.hover(true) }
        } else {
            super.mouseEntered(with: event)
        }
    }

    override func mouseExited(with event: NSEvent) {
        if event.trackingArea === hoverArea {
            if model?.isolated == false { model?.hover(false) }
        } else {
            super.mouseExited(with: event)
        }
    }
}
