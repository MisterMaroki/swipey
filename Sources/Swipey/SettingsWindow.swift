import AppKit

@MainActor
final class SettingsWindow: NSWindow {
    private let popup: NSPopUpButton
    var onTriggerKeyChanged: ((ZoomTriggerKey) -> Void)?

    init() {
        popup = NSPopUpButton()

        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 200),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )

        title = "Swipey Settings"
        isReleasedWhenClosed = false
        isMovableByWindowBackground = true

        setupViews()
        center()
    }

    private func setupViews() {
        let effectView = NSVisualEffectView()
        effectView.material = .underWindowBackground
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        contentView = effectView

        let titleLabel = NSTextField(labelWithString: "Zoom Trigger Key")
        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        titleLabel.textColor = .labelColor
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let descLabel = NSTextField(labelWithString: "Double-tap this key to expand/restore tiled windows.")
        descLabel.font = .systemFont(ofSize: 12, weight: .regular)
        descLabel.textColor = .secondaryLabelColor
        descLabel.lineBreakMode = .byWordWrapping
        descLabel.maximumNumberOfLines = 0
        descLabel.translatesAutoresizingMaskIntoConstraints = false

        popup.translatesAutoresizingMaskIntoConstraints = false
        popup.removeAllItems()
        let current = ZoomTriggerKey.current
        for key in ZoomTriggerKey.allCases {
            popup.addItem(withTitle: "\(key.symbol) \(key.displayName)")
            if key == current {
                popup.selectItem(at: popup.numberOfItems - 1)
            }
        }
        popup.target = self
        popup.action = #selector(popupChanged(_:))

        effectView.addSubview(titleLabel)
        effectView.addSubview(descLabel)
        effectView.addSubview(popup)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: effectView.topAnchor, constant: 30),
            titleLabel.leadingAnchor.constraint(equalTo: effectView.leadingAnchor, constant: 30),

            descLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 6),
            descLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            descLabel.trailingAnchor.constraint(equalTo: effectView.trailingAnchor, constant: -30),

            popup.topAnchor.constraint(equalTo: descLabel.bottomAnchor, constant: 16),
            popup.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            popup.widthAnchor.constraint(equalToConstant: 200),
        ])
    }

    @objc private func popupChanged(_ sender: NSPopUpButton) {
        let allKeys = ZoomTriggerKey.allCases
        guard sender.indexOfSelectedItem >= 0, sender.indexOfSelectedItem < allKeys.count else { return }
        let selected = allKeys[ZoomTriggerKey.allCases.index(allKeys.startIndex, offsetBy: sender.indexOfSelectedItem)]
        ZoomTriggerKey.current = selected
        onTriggerKeyChanged?(selected)
    }
}
