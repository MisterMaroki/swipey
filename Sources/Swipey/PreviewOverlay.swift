import AppKit

@MainActor
final class PreviewOverlay {
    private var overlayPanel: NSPanel?
    private var effectView: NSVisualEffectView?
    private var hideGeneration: UInt = 0

    /// Show the overlay at the given frame (NSScreen coordinates, bottom-left origin).
    func show(frame: CGRect, on screen: NSScreen) {
        hideGeneration &+= 1

        if overlayPanel == nil {
            createPanel()
        }

        guard let panel = overlayPanel else { return }

        panel.setFrame(frame, display: false)
        panel.alphaValue = 0
        panel.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }
    }

    /// Update the overlay to a new frame with animation.
    func update(frame: CGRect) {
        guard let panel = overlayPanel else { return }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(frame, display: true)
        }
    }

    /// Hide the overlay with a fade-out.
    func hide() {
        guard let panel = overlayPanel else { return }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        }

        // Order out after animation duration; invalidated if show() is called before it fires
        let gen = hideGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self, self.hideGeneration == gen else { return }
            panel.orderOut(nil)
        }
    }

    var isVisible: Bool {
        overlayPanel?.isVisible ?? false
    }

    // MARK: - Private

    private func createPanel() {
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.floatingWindow)) + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.ignoresMouseEvents = true
        panel.hasShadow = false

        let effect = NSVisualEffectView()
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 12
        effect.layer?.masksToBounds = true
        effect.layer?.borderWidth = 1
        effect.layer?.borderColor = NSColor.white.withAlphaComponent(0.3).cgColor

        panel.contentView = effect
        self.effectView = effect
        self.overlayPanel = panel
    }
}
