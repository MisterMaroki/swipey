import AppKit

@MainActor
final class OnboardingWindow: NSWindow {
    private let instructionLabel: NSTextField
    private let doneLabel: NSTextField
    private let stepLabel: NSTextField
    private let progressBar: NSView
    private let progressTrack: NSView
    private var progressWidthConstraint: NSLayoutConstraint?

    private let hintStack = NSStackView()
    private let trackpadHint = TrackpadHintView()
    private let titleBarHint = TitleBarHintView()
    private let indicatorHint = IndicatorHintView()

    private let welcomeContainer = NSView()
    private let welcomeIcon = NSImageView()
    private let welcomeTitle = NSTextField(labelWithString: "")
    private let welcomeSubtitle = NSTextField(labelWithString: "")

    private let choiceContainer = NSStackView()
    private let contentStack = NSStackView()

    var onSiriConflictChoice: ((SiriConflictChoice) -> Void)?

    init() {
        instructionLabel = NSTextField(labelWithString: "")
        doneLabel = NSTextField(labelWithString: "")
        stepLabel = NSTextField(labelWithString: "")
        progressTrack = NSView()
        progressBar = NSView()

        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 340),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )

        title = "Welcome to Swipey"
        isReleasedWhenClosed = false
        isMovableByWindowBackground = true
        collectionBehavior = [.fullScreenPrimary]

        setupViews()
        center()
    }

    // MARK: - Public

    func showStep(index: Int, total: Int, instruction: String,
                  hint: StepHint, trackpadGesture: TrackpadHintView.Gesture?) {
        instructionLabel.attributedStringValue = styledText(instruction, font: instructionLabel.font!)
        doneLabel.isHidden = true
        instructionLabel.isHidden = false
        stepLabel.stringValue = "Step \(index + 1) of \(total)"
        stepLabel.isHidden = false
        progressTrack.isHidden = false
        updateProgress(fraction: CGFloat(index) / CGFloat(total))

        showHint(hint, trackpadGesture: trackpadGesture)
    }

    func showCompletion(message: String, index: Int, total: Int) {
        doneLabel.attributedStringValue = styledText(message, font: doneLabel.font!)
        doneLabel.isHidden = false
        instructionLabel.isHidden = true
        hideAllHints()
        updateProgress(fraction: CGFloat(index + 1) / CGFloat(total))
    }

    func showFinal() {
        instructionLabel.attributedStringValue = styledText("You are now a screen real estate tycoon!", font: instructionLabel.font!)
        instructionLabel.isHidden = false
        doneLabel.isHidden = true
        stepLabel.isHidden = true
        hideAllHints()
        updateProgress(fraction: 1.0)
    }

    // MARK: - Hints

    private func showHint(_ hint: StepHint, trackpadGesture: TrackpadHintView.Gesture?) {
        hideAllHints()

        if case .welcome = hint {
            instructionLabel.isHidden = true
            stepLabel.isHidden = true
            progressTrack.isHidden = true
            welcomeContainer.isHidden = false
            welcomeContainer.alphaValue = 0
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.6
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                welcomeContainer.animator().alphaValue = 1
            }
            return
        }

        if case .none = hint { return }

        // Add trackpad to the stack if gesture provided
        if let gesture = trackpadGesture {
            trackpadHint.configure(gesture: gesture)
            hintStack.addArrangedSubview(trackpadHint)
            trackpadHint.startAnimating()
        }

        // Add the right-side hint to the stack
        switch hint {
        case .none, .welcome:
            break

        case .titleBarDiagram:
            hintStack.addArrangedSubview(titleBarHint)
            titleBarHint.startAnimating()

        case .indicator(let position):
            indicatorHint.configure(position: position)
            hintStack.addArrangedSubview(indicatorHint)
            indicatorHint.startAnimating()

        case .cancelIndicator:
            indicatorHint.configureCancel()
            hintStack.addArrangedSubview(indicatorHint)
            indicatorHint.startAnimating()

        case .doubleTapKey(let key):
            indicatorHint.configureKeyboard(mode: .doubleTap, triggerKey: key)
            hintStack.addArrangedSubview(indicatorHint)
            indicatorHint.startAnimating()

        case .holdKey(let key):
            indicatorHint.configureKeyboard(mode: .hold, triggerKey: key)
            hintStack.addArrangedSubview(indicatorHint)
            indicatorHint.startAnimating()

        case .siriConflict:
            hintStack.isHidden = true
            choiceContainer.isHidden = false
            return
        }

        hintStack.isHidden = hintStack.arrangedSubviews.isEmpty
    }

    @objc private func siriChoiceTapped(_ sender: NSButton) {
        let choices: [SiriConflictChoice] = [.noConflict, .disableSiri, .switchToControl, .switchToOption]
        guard sender.tag >= 0, sender.tag < choices.count else { return }
        onSiriConflictChoice?(choices[sender.tag])
    }

    private func hideAllHints() {
        trackpadHint.stopAnimating()
        titleBarHint.stopAnimating()
        indicatorHint.stopAnimating()
        welcomeContainer.isHidden = true
        choiceContainer.isHidden = true

        hintStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        hintStack.isHidden = true
    }

    // MARK: - Keycap text rendering

    private static let keycapSymbols: Set<Character> = [
        "\u{2318}", // ⌘ Command
        "\u{2303}", // ⌃ Control
        "\u{2325}", // ⌥ Option
        "\u{2192}", // → Right
        "\u{2190}", // ← Left
        "\u{2191}", // ↑ Up
        "\u{2193}", // ↓ Down
    ]

    private func styledText(_ text: String, font: NSFont) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let baseAttrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.labelColor,
        ]

        let keycapHeight = round(font.pointSize * 1.25)
        var buffer = ""

        for char in text {
            if Self.keycapSymbols.contains(char) {
                if !buffer.isEmpty {
                    result.append(NSAttributedString(string: buffer, attributes: baseAttrs))
                    buffer = ""
                }
                let attachment = NSTextAttachment()
                attachment.image = Self.renderKeycap(symbol: String(char), height: keycapHeight)
                let imgWidth = attachment.image!.size.width
                let imgHeight = attachment.image!.size.height
                attachment.bounds = CGRect(x: 0, y: font.descender, width: imgWidth, height: imgHeight)
                result.append(NSAttributedString(attachment: attachment))
            } else {
                buffer.append(char)
            }
        }
        if !buffer.isEmpty {
            result.append(NSAttributedString(string: buffer, attributes: baseAttrs))
        }

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        result.addAttribute(.paragraphStyle, value: paragraphStyle,
                            range: NSRange(location: 0, length: result.length))
        return result
    }

    nonisolated private static func renderKeycap(symbol: String, height: CGFloat) -> NSImage {
        let font = NSFont.systemFont(ofSize: height * 0.52, weight: .medium)
        let str = symbol as NSString
        let textSize = str.size(withAttributes: [.font: font])
        let width = max(height, textSize.width + height * 0.4)
        let shadowPad: CGFloat = 3
        let imgSize = NSSize(width: width + 2, height: height + shadowPad)

        return NSImage(size: imgSize, flipped: false) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }

            let keyRect = CGRect(x: 1, y: shadowPad, width: width, height: height - 1)
            let cr: CGFloat = 5
            let keyPath = CGPath(roundedRect: keyRect, cornerWidth: cr,
                                 cornerHeight: cr, transform: nil)

            // Shadow
            ctx.saveGState()
            ctx.setShadow(offset: CGSize(width: 0, height: -1.5), blur: 2,
                           color: NSColor.black.withAlphaComponent(0.25).cgColor)
            ctx.setFillColor(NSColor.windowBackgroundColor.cgColor)
            ctx.addPath(keyPath)
            ctx.fillPath()
            ctx.restoreGState()

            // Key face
            ctx.setFillColor(NSColor.windowBackgroundColor.withAlphaComponent(0.95).cgColor)
            ctx.addPath(keyPath)
            ctx.fillPath()

            // Border
            ctx.setStrokeColor(NSColor.tertiaryLabelColor.withAlphaComponent(0.5).cgColor)
            ctx.setLineWidth(0.5)
            ctx.addPath(keyPath)
            ctx.strokePath()

            // Symbol
            let drawAttrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: NSColor.secondaryLabelColor,
            ]
            let drawSize = str.size(withAttributes: drawAttrs)
            let drawRect = CGRect(
                x: keyRect.midX - drawSize.width / 2,
                y: keyRect.midY - drawSize.height / 2,
                width: drawSize.width,
                height: drawSize.height
            )
            str.draw(in: drawRect, withAttributes: drawAttrs)

            return true
        }
    }

    // MARK: - Private

    private func updateProgress(fraction: CGFloat) {
        let trackWidth = progressTrack.bounds.width
        let target = max(0, min(trackWidth, trackWidth * fraction))
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            progressWidthConstraint?.animator().constant = target
        }
    }

    private func setupViews() {
        let effectView = NSVisualEffectView()
        effectView.material = .underWindowBackground
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        contentView = effectView

        instructionLabel.font = .systemFont(ofSize: 22, weight: .medium)
        instructionLabel.textColor = .labelColor
        instructionLabel.alignment = .center
        instructionLabel.lineBreakMode = .byWordWrapping
        instructionLabel.maximumNumberOfLines = 0
        instructionLabel.translatesAutoresizingMaskIntoConstraints = false

        doneLabel.font = .systemFont(ofSize: 20, weight: .regular)
        doneLabel.textColor = .secondaryLabelColor
        doneLabel.alignment = .center
        doneLabel.translatesAutoresizingMaskIntoConstraints = false
        doneLabel.isHidden = true

        stepLabel.font = .systemFont(ofSize: 13, weight: .regular)
        stepLabel.textColor = .tertiaryLabelColor
        stepLabel.alignment = .center
        stepLabel.translatesAutoresizingMaskIntoConstraints = false

        progressTrack.wantsLayer = true
        progressTrack.layer?.backgroundColor = NSColor.separatorColor.cgColor
        progressTrack.layer?.cornerRadius = 2
        progressTrack.translatesAutoresizingMaskIntoConstraints = false

        progressBar.wantsLayer = true
        progressBar.layer?.backgroundColor = NSColor.controlAccentColor.cgColor
        progressBar.layer?.cornerRadius = 2
        progressBar.translatesAutoresizingMaskIntoConstraints = false

        // Hint stack (arranges trackpad + right-side hint horizontally)
        hintStack.orientation = .horizontal
        hintStack.spacing = 20
        hintStack.alignment = .centerY
        hintStack.translatesAutoresizingMaskIntoConstraints = false
        hintStack.isHidden = true

        // Hint views need translatesAutoresizing off for stack view
        trackpadHint.translatesAutoresizingMaskIntoConstraints = false
        titleBarHint.translatesAutoresizingMaskIntoConstraints = false
        indicatorHint.translatesAutoresizingMaskIntoConstraints = false

        // Set content hugging so views stay at intrinsic size in the stack
        for view in [trackpadHint, titleBarHint, indicatorHint] as [NSView] {
            view.setContentHuggingPriority(.required, for: .horizontal)
            view.setContentHuggingPriority(.required, for: .vertical)
            view.setContentCompressionResistancePriority(.required, for: .horizontal)
            view.setContentCompressionResistancePriority(.required, for: .vertical)
        }

        // Welcome layout
        welcomeContainer.translatesAutoresizingMaskIntoConstraints = false
        welcomeContainer.isHidden = true

        if let appIcon = NSImage(named: NSImage.applicationIconName) {
            welcomeIcon.image = appIcon
        }
        welcomeIcon.imageScaling = .scaleProportionallyUpOrDown
        welcomeIcon.translatesAutoresizingMaskIntoConstraints = false

        welcomeTitle.stringValue = "Welcome to Swipey"
        welcomeTitle.font = .systemFont(ofSize: 28, weight: .bold)
        welcomeTitle.textColor = .labelColor
        welcomeTitle.alignment = .center
        welcomeTitle.translatesAutoresizingMaskIntoConstraints = false

        welcomeSubtitle.stringValue = "Let's become window tiling wizards together.\n"
        welcomeSubtitle.font = .systemFont(ofSize: 15, weight: .regular)
        welcomeSubtitle.textColor = .secondaryLabelColor
        welcomeSubtitle.alignment = .center
        welcomeSubtitle.lineBreakMode = .byWordWrapping
        welcomeSubtitle.maximumNumberOfLines = 0
        welcomeSubtitle.translatesAutoresizingMaskIntoConstraints = false

        welcomeContainer.addSubview(welcomeIcon)
        welcomeContainer.addSubview(welcomeTitle)
        welcomeContainer.addSubview(welcomeSubtitle)

        // Choice container for siri conflict step
        choiceContainer.orientation = .vertical
        choiceContainer.spacing = 6
        choiceContainer.alignment = .centerX
        choiceContainer.translatesAutoresizingMaskIntoConstraints = false
        choiceContainer.isHidden = true

        let choices: [(title: String, desc: String?, choice: SiriConflictChoice)] = [
            ("No, it worked fine", nil, .noConflict),
            ("Open Siri Settings",
             "Turn off or change the Siri shortcut, then try again", .disableSiri),
            ("Use \u{2303} Control instead",
             "Swipey will use double-tap Control for zoom", .switchToControl),
            ("Use \u{2325} Option instead",
             "Swipey will use double-tap Option for zoom", .switchToOption),
        ]
        for (index, (title, desc, _)) in choices.enumerated() {
            let button = NSButton(title: title, target: self, action: #selector(siriChoiceTapped(_:)))
            button.bezelStyle = .rounded
            button.controlSize = .large
            button.tag = index
            button.widthAnchor.constraint(greaterThanOrEqualToConstant: 260).isActive = true
            choiceContainer.addArrangedSubview(button)

            if let desc {
                let label = NSTextField(labelWithString: desc)
                label.font = .systemFont(ofSize: 11)
                label.textColor = .tertiaryLabelColor
                label.alignment = .center
                choiceContainer.addArrangedSubview(label)
                choiceContainer.setCustomSpacing(1, after: button)
                choiceContainer.setCustomSpacing(10, after: label)
            }
        }

        // Content stack: groups instruction + hints/choices, always centered
        contentStack.orientation = .vertical
        contentStack.spacing = 14
        contentStack.alignment = .centerX
        contentStack.translatesAutoresizingMaskIntoConstraints = false

        contentStack.addArrangedSubview(instructionLabel)
        contentStack.addArrangedSubview(hintStack)
        contentStack.addArrangedSubview(choiceContainer)

        effectView.addSubview(contentStack)
        effectView.addSubview(doneLabel)
        effectView.addSubview(welcomeContainer)
        effectView.addSubview(stepLabel)
        effectView.addSubview(progressTrack)
        progressTrack.addSubview(progressBar)

        let progressWidth = progressBar.widthAnchor.constraint(equalToConstant: 0)
        self.progressWidthConstraint = progressWidth

        NSLayoutConstraint.activate([
            contentStack.centerXAnchor.constraint(equalTo: effectView.centerXAnchor),
            contentStack.centerYAnchor.constraint(equalTo: effectView.centerYAnchor, constant: -20),
            contentStack.widthAnchor.constraint(lessThanOrEqualTo: effectView.widthAnchor, constant: -40),

            instructionLabel.widthAnchor.constraint(lessThanOrEqualTo: effectView.widthAnchor, constant: -60),

            welcomeContainer.centerXAnchor.constraint(equalTo: effectView.centerXAnchor),
            welcomeContainer.centerYAnchor.constraint(equalTo: effectView.centerYAnchor, constant: -10),
            welcomeContainer.widthAnchor.constraint(lessThanOrEqualTo: effectView.widthAnchor, constant: -60),

            welcomeIcon.centerXAnchor.constraint(equalTo: welcomeContainer.centerXAnchor),
            welcomeIcon.topAnchor.constraint(equalTo: welcomeContainer.topAnchor),
            welcomeIcon.widthAnchor.constraint(equalToConstant: 64),
            welcomeIcon.heightAnchor.constraint(equalToConstant: 64),

            welcomeTitle.centerXAnchor.constraint(equalTo: welcomeContainer.centerXAnchor),
            welcomeTitle.topAnchor.constraint(equalTo: welcomeIcon.bottomAnchor, constant: 14),
            welcomeTitle.widthAnchor.constraint(lessThanOrEqualTo: welcomeContainer.widthAnchor),

            welcomeSubtitle.centerXAnchor.constraint(equalTo: welcomeContainer.centerXAnchor),
            welcomeSubtitle.topAnchor.constraint(equalTo: welcomeTitle.bottomAnchor, constant: 8),
            welcomeSubtitle.widthAnchor.constraint(lessThanOrEqualTo: welcomeContainer.widthAnchor),
            welcomeSubtitle.bottomAnchor.constraint(equalTo: welcomeContainer.bottomAnchor),

            doneLabel.centerXAnchor.constraint(equalTo: effectView.centerXAnchor),
            doneLabel.centerYAnchor.constraint(equalTo: effectView.centerYAnchor, constant: -10),
            doneLabel.widthAnchor.constraint(lessThanOrEqualTo: effectView.widthAnchor, constant: -60),

            stepLabel.centerXAnchor.constraint(equalTo: effectView.centerXAnchor),
            stepLabel.bottomAnchor.constraint(equalTo: effectView.bottomAnchor, constant: -20),

            progressTrack.leadingAnchor.constraint(equalTo: effectView.leadingAnchor, constant: 40),
            progressTrack.trailingAnchor.constraint(equalTo: effectView.trailingAnchor, constant: -40),
            progressTrack.bottomAnchor.constraint(equalTo: stepLabel.topAnchor, constant: -12),
            progressTrack.heightAnchor.constraint(equalToConstant: 4),

            progressBar.leadingAnchor.constraint(equalTo: progressTrack.leadingAnchor),
            progressBar.topAnchor.constraint(equalTo: progressTrack.topAnchor),
            progressBar.bottomAnchor.constraint(equalTo: progressTrack.bottomAnchor),
            progressWidth,
        ])
    }
}
