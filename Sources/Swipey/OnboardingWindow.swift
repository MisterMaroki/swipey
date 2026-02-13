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

    private var instructionCenteredConstraint: NSLayoutConstraint!
    private var instructionTopConstraint: NSLayoutConstraint!

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
        instructionLabel.stringValue = instruction
        doneLabel.isHidden = true
        instructionLabel.isHidden = false
        stepLabel.stringValue = "Step \(index + 1) of \(total)"
        stepLabel.isHidden = false
        progressTrack.isHidden = false
        updateProgress(fraction: CGFloat(index) / CGFloat(total))

        showHint(hint, trackpadGesture: trackpadGesture)
    }

    func showCompletion(message: String, index: Int, total: Int) {
        doneLabel.stringValue = message
        doneLabel.isHidden = false
        instructionLabel.isHidden = true
        hideAllHints()
        updateProgress(fraction: CGFloat(index + 1) / CGFloat(total))
    }

    func showFinal() {
        instructionLabel.stringValue = "You are now ready to get swipey."
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

        // Move instruction label to top for hint area
        instructionCenteredConstraint.isActive = false
        instructionTopConstraint.isActive = true

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

        case .doubleTapCmd:
            indicatorHint.configureKeyboard(mode: .doubleTap)
            hintStack.addArrangedSubview(indicatorHint)
            indicatorHint.startAnimating()

        case .holdCmd:
            indicatorHint.configureKeyboard(mode: .hold)
            hintStack.addArrangedSubview(indicatorHint)
            indicatorHint.startAnimating()
        }

        hintStack.isHidden = hintStack.arrangedSubviews.isEmpty
    }

    private func hideAllHints() {
        trackpadHint.stopAnimating()
        titleBarHint.stopAnimating()
        indicatorHint.stopAnimating()
        welcomeContainer.isHidden = true

        hintStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        hintStack.isHidden = true

        instructionTopConstraint.isActive = false
        instructionCenteredConstraint.isActive = true
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

        welcomeSubtitle.stringValue = "Let's become window tiling wizards together.\nScreen real estate tycoons!"
        welcomeSubtitle.font = .systemFont(ofSize: 15, weight: .regular)
        welcomeSubtitle.textColor = .secondaryLabelColor
        welcomeSubtitle.alignment = .center
        welcomeSubtitle.lineBreakMode = .byWordWrapping
        welcomeSubtitle.maximumNumberOfLines = 0
        welcomeSubtitle.translatesAutoresizingMaskIntoConstraints = false

        welcomeContainer.addSubview(welcomeIcon)
        welcomeContainer.addSubview(welcomeTitle)
        welcomeContainer.addSubview(welcomeSubtitle)

        effectView.addSubview(instructionLabel)
        effectView.addSubview(doneLabel)
        effectView.addSubview(hintStack)
        effectView.addSubview(welcomeContainer)
        effectView.addSubview(stepLabel)
        effectView.addSubview(progressTrack)
        progressTrack.addSubview(progressBar)

        let progressWidth = progressBar.widthAnchor.constraint(equalToConstant: 0)
        self.progressWidthConstraint = progressWidth

        NSLayoutConstraint.activate([
            instructionLabel.centerXAnchor.constraint(equalTo: effectView.centerXAnchor),
            instructionLabel.widthAnchor.constraint(lessThanOrEqualTo: effectView.widthAnchor, constant: -60),

            hintStack.centerXAnchor.constraint(equalTo: effectView.centerXAnchor),
            hintStack.topAnchor.constraint(equalTo: instructionLabel.bottomAnchor, constant: 12),

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

        // Switchable vertical position for instruction label
        instructionCenteredConstraint = instructionLabel.centerYAnchor.constraint(
            equalTo: effectView.centerYAnchor, constant: -10)
        instructionTopConstraint = instructionLabel.topAnchor.constraint(
            equalTo: effectView.topAnchor, constant: 40)
        instructionCenteredConstraint.isActive = true
    }
}
