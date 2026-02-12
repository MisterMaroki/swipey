import AppKit

@MainActor
final class OnboardingWindow: NSWindow {
    private let instructionLabel: NSTextField
    private let doneLabel: NSTextField
    private let stepLabel: NSTextField
    private let progressBar: NSView
    private let progressTrack: NSView
    private var progressWidthConstraint: NSLayoutConstraint?

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

    func showStep(index: Int, total: Int, instruction: String) {
        instructionLabel.stringValue = instruction
        doneLabel.isHidden = true
        instructionLabel.isHidden = false
        stepLabel.stringValue = "Step \(index + 1) of \(total)"
        stepLabel.isHidden = false
        progressTrack.isHidden = false
        updateProgress(fraction: CGFloat(index) / CGFloat(total))
    }

    func showCompletion(message: String, index: Int, total: Int) {
        doneLabel.stringValue = message
        doneLabel.isHidden = false
        instructionLabel.isHidden = true
        updateProgress(fraction: CGFloat(index + 1) / CGFloat(total))
    }

    func showFinal() {
        instructionLabel.stringValue = "You are now ready to get swipey."
        instructionLabel.isHidden = false
        doneLabel.isHidden = true
        stepLabel.isHidden = true
        updateProgress(fraction: 1.0)
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

        effectView.addSubview(instructionLabel)
        effectView.addSubview(doneLabel)
        effectView.addSubview(stepLabel)
        effectView.addSubview(progressTrack)
        progressTrack.addSubview(progressBar)

        let progressWidth = progressBar.widthAnchor.constraint(equalToConstant: 0)
        self.progressWidthConstraint = progressWidth

        NSLayoutConstraint.activate([
            instructionLabel.centerXAnchor.constraint(equalTo: effectView.centerXAnchor),
            instructionLabel.centerYAnchor.constraint(equalTo: effectView.centerYAnchor, constant: -10),
            instructionLabel.widthAnchor.constraint(lessThanOrEqualTo: effectView.widthAnchor, constant: -60),

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
