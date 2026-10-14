// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

import AppKit
import CommanderCore

/// The update window (spec 027): the versions, the notes, and install / remind later / skip. It opens only on
/// the user's request (Check for Updates…, the title-bar button, About, Settings) and blocks nothing.
@MainActor
final class UpdateWindowController: NSWindowController, NSWindowDelegate {
    var onClose: (() -> Void)?

    private let release: ReleaseInfo
    /// Why this copy cannot install itself; then the default is Download… (the release page).
    private var problem: UpdateProblem?
    private var failure: String?
    private let notesView = NotesWebView()
    private let reasonLabel = NSTextField(wrappingLabelWithString: "")
    private let statusLabel = NSTextField(labelWithString: "")
    private let progressBar = NSProgressIndicator()
    private let installButton = NSButton(title: "", target: nil, action: nil)
    private let laterButton = NSButton(title: "", target: nil, action: nil)
    private let skipButton = NSButton(title: "", target: nil, action: nil)
    private let automaticBox = NSButton(checkboxWithTitle: String(localized: "Check for updates automatically"),
                                        target: nil, action: nil)
    private var install: Task<Void, Never>?
    private var waitTimer: Timer?
    private var installer: UpdateInstaller?
    /// Skip, Install or the cancelled install decide; any other close counts as Remind Me Later.
    private var decided = false

    init(release: ReleaseInfo, running: AppVersion, notes: [ReleaseNote], problem: UpdateProblem?) {
        self.release = release
        self.problem = problem
        let window = UpdatePanelWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 540),
                                       styleMask: [.titled, .closable, .resizable, .miniaturizable],
                                       backing: .buffered, defer: false)
        window.title = String(localized: "Software Update")
        window.minSize = NSSize(width: 480, height: 360)
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        window.onCancel = { [weak self] in self?.later() }
        build(in: window, running: running)
        notesView.show(notes, empty: String(localized: "No release notes came with this version."))
        update()
        place(window)
    }

    /// Over the main window (on its screen), not on whichever screen has the keyboard focus.
    private func place(_ window: NSWindow) {
        guard let main = NSApp.windows.first(where: { $0.windowController is MainWindowController && $0.isVisible }) else {
            window.center()
            return
        }
        var frame = window.frame
        frame.origin = NSPoint(x: main.frame.midX - frame.width / 2, y: main.frame.midY - frame.height / 2)
        if let visible = main.screen?.visibleFrame {
            frame.origin.x = min(max(frame.origin.x, visible.minX), visible.maxX - frame.width)
            frame.origin.y = min(max(frame.origin.y, visible.minY), visible.maxY - frame.height)
        }
        window.setFrame(frame, display: false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private func build(in window: NSWindow, running: AppVersion) {
        let icon = NSImageView(image: NSApp.applicationIconImage)
        icon.imageScaling = .scaleProportionallyUpOrDown
        let title = NSTextField(labelWithString: String(localized: "A new version of Axolotl Commander is available"))
        title.font = .boldSystemFont(ofSize: NSFont.systemFontSize + 2)
        let version = release.version.description
        let summary = if let published = release.published?.formatted(date: .long, time: .omitted) {
            String(localized: "Version \(version) was released on \(published). You have version \(running.description).")
        } else {
            String(localized: "Version \(version) is out. You have version \(running.description).")
        }
        let subtitle = NSTextField(wrappingLabelWithString: summary)
        subtitle.textColor = .secondaryLabelColor
        reasonLabel.textColor = .secondaryLabelColor
        notesView.wantsLayer = true
        notesView.layer?.borderWidth = 1
        notesView.layer?.borderColor = NSColor.separatorColor.cgColor
        progressBar.style = .bar
        progressBar.minValue = 0
        progressBar.maxValue = 1
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.lineBreakMode = .byTruncatingTail

        for (button, title, action) in [(installButton, "", #selector(installOrDownload)),
                                        (laterButton, String(localized: "Remind Me Later"), #selector(later)),
                                        (skipButton, String(localized: "Skip This Version"), #selector(skip))] {
            button.title = title
            button.bezelStyle = .push
            button.target = self
            button.action = action
        }
        installButton.keyEquivalent = "\r"
        automaticBox.target = self
        automaticBox.action = #selector(toggleAutomatic)
        automaticBox.state = UpdateController.shared.state.automatic ? .on : .off

        let content = NSView()
        let views: [NSView] = [icon, title, subtitle, reasonLabel, notesView, progressBar, statusLabel,
                               automaticBox, skipButton, laterButton, installButton]
        for view in views {
            view.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(view)
        }
        window.contentView = content
        let margin: CGFloat = 20
        NSLayoutConstraint.activate([
            icon.topAnchor.constraint(equalTo: content.topAnchor, constant: 16),
            icon.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: margin),
            icon.widthAnchor.constraint(equalToConstant: 56),
            icon.heightAnchor.constraint(equalToConstant: 56),
            title.topAnchor.constraint(equalTo: icon.topAnchor, constant: 4),
            title.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 14),
            title.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor, constant: -margin),
            subtitle.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 4),
            subtitle.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            subtitle.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -margin),
            reasonLabel.topAnchor.constraint(equalTo: subtitle.bottomAnchor, constant: 6),
            reasonLabel.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            reasonLabel.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -margin),
            notesView.topAnchor.constraint(greaterThanOrEqualTo: icon.bottomAnchor, constant: 12),
            notesView.topAnchor.constraint(equalTo: reasonLabel.bottomAnchor, constant: 12),
            notesView.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: margin),
            notesView.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -margin),
            progressBar.topAnchor.constraint(equalTo: notesView.bottomAnchor, constant: 12),
            progressBar.leadingAnchor.constraint(equalTo: notesView.leadingAnchor),
            progressBar.widthAnchor.constraint(equalToConstant: 160),
            statusLabel.centerYAnchor.constraint(equalTo: progressBar.centerYAnchor),
            statusLabel.leadingAnchor.constraint(equalTo: progressBar.trailingAnchor, constant: 10),
            statusLabel.trailingAnchor.constraint(equalTo: notesView.trailingAnchor),
            installButton.topAnchor.constraint(equalTo: progressBar.bottomAnchor, constant: 12),
            installButton.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -margin),
            installButton.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -16),
            laterButton.centerYAnchor.constraint(equalTo: installButton.centerYAnchor),
            laterButton.trailingAnchor.constraint(equalTo: installButton.leadingAnchor, constant: -8),
            skipButton.centerYAnchor.constraint(equalTo: installButton.centerYAnchor),
            skipButton.trailingAnchor.constraint(equalTo: laterButton.leadingAnchor, constant: -8),
            automaticBox.centerYAnchor.constraint(equalTo: installButton.centerYAnchor),
            automaticBox.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: margin),
            automaticBox.trailingAnchor.constraint(lessThanOrEqualTo: skipButton.leadingAnchor, constant: -12),
        ])
        notesView.setContentHuggingPriority(.defaultLow, for: .vertical)
    }

    /// The buttons and texts for the current step.
    private func update(status: String? = nil, progress: Double? = nil, busy: Bool = false) {
        let manual = problem != nil
        installButton.title = manual ? String(localized: "Download…") : String(localized: "Install and Relaunch")
        installButton.isEnabled = !busy
        skipButton.isEnabled = !busy
        laterButton.title = busy ? String(localized: "Cancel") : String(localized: "Remind Me Later")
        reasonLabel.stringValue = failure ?? problem?.explanation ?? ""
        reasonLabel.textColor = failure == nil ? .secondaryLabelColor : .systemRed
        reasonLabel.isHidden = reasonLabel.stringValue.isEmpty
        statusLabel.stringValue = status ?? ""
        progressBar.isHidden = status == nil
        statusLabel.isHidden = status == nil
        if let progress {
            progressBar.isIndeterminate = false
            progressBar.doubleValue = progress
        } else {
            progressBar.isIndeterminate = true
            progressBar.startAnimation(nil)
        }
    }

    private var isBusy: Bool { install != nil || waitTimer != nil }

    // MARK: Actions

    @objc private func installOrDownload() {
        if problem != nil {
            NSWorkspace.shared.open(release.page)
            close()
            return
        }
        guard !isBusy else { return }
        if Self.fileOperationsRunning {
            // Running copies and moves are never interrupted (FR-011): the install waits for them.
            update(status: String(localized: "Waiting for the file operations to finish; the update installs afterwards."),
                   busy: true)
            waitTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, !Self.fileOperationsRunning else { return }
                    self.waitTimer?.invalidate()
                    self.waitTimer = nil
                    self.startInstall()
                }
            }
            return
        }
        startInstall()
    }

    static var fileOperationsRunning: Bool {
        NSApp.windows.contains { ($0.windowController as? MainWindowController)?.operations.isBusy == true }
    }

    private func startInstall() {
        let appURL = Bundle.main.bundleURL
        guard let identifier = Bundle.main.bundleIdentifier, let verifier = CodeSignatureVerifier.forRunningApp() else {
            fail(.adHocSignature)
            return
        }
        guard let archiveURL = release.archive, let checksumsURL = release.checksums else {
            fail(.checksumMissing)
            return
        }
        // A private folder on the app's volume, so the new app moves into place without copying.
        guard let work = try? FileManager.default.url(for: .itemReplacementDirectory, in: .userDomainMask,
                                                      appropriateFor: appURL, create: true) else {
            fail(.notWritable)
            return
        }
        let installer = UpdateInstaller(appURL: appURL, bundleIdentifier: identifier, workFolder: work, verifier: verifier)
        self.installer = installer
        let release = release
        failure = nil
        update(status: String(localized: "Downloading…"), progress: 0, busy: true)
        install = Task { [weak self] in
            do {
                let sums = try await UpdateController.text(from: checksumsURL)
                let download = FileDownload(to: work.appendingPathComponent(release.archiveName)) { fraction in
                    Task { @MainActor in
                        guard let self, self.install != nil else { return }
                        self.progressBar.doubleValue = fraction
                    }
                }
                let zip = try await download.run(archiveURL)
                try Task.checkCancellation()
                self?.laterButton.isEnabled = false
                self?.update(status: String(localized: "Checking the download…"), busy: true)
                let app = try await Task.detached { try installer.verify(archive: zip, checksums: sums, release: release) }.value
                self?.update(status: String(localized: "Installing…"), busy: true)
                try installer.replace(with: app)
                installer.cleanUp()
                self?.decided = true
                Self.relaunch(appURL)
            } catch {
                installer.cleanUp()
                guard let self else { return }
                self.install = nil
                self.installer = nil
                self.laterButton.isEnabled = true
                if Task.isCancelled || error is CancellationError || (error as? URLError)?.code == .cancelled {
                    self.update()
                } else if let problem = error as? UpdateProblem {
                    self.fail(problem)
                } else {
                    self.fail(message: String(localized: "The download failed: \(error.localizedDescription)"))
                }
            }
        }
    }

    /// Any failure leaves the running app as it was and offers the manual way.
    private func fail(_ problem: UpdateProblem) {
        fail(message: problem.explanation)
        self.problem = problem
        update()
    }

    private func fail(message: String) {
        failure = message
        if problem == nil { problem = .replaceFailed(message) }
        update()
    }

    /// Starts the new app once this process has ended, then quits (R5).
    private static func relaunch(_ app: URL) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "while /bin/kill -0 \"$1\" 2>/dev/null; do /bin/sleep 0.2; done; /usr/bin/open \"$2\"",
                             "sh", String(ProcessInfo.processInfo.processIdentifier), app.path]
        try? process.run()
        NSApp.terminate(nil)
    }

    @objc private func later() {
        if isBusy {
            cancelInstall()
            update()
            return
        }
        close()
    }

    @objc private func skip() {
        decided = true
        UpdateController.shared.skip(release.version)
        close()
    }

    @objc private func toggleAutomatic() {
        UpdateController.shared.setAutomatic(automaticBox.state == .on)
    }

    /// Stops waiting or downloading and removes the downloaded files.
    func cancelInstall() {
        waitTimer?.invalidate()
        waitTimer = nil
        install?.cancel()
        install = nil
        installer?.cleanUp()
        installer = nil
    }

    func windowWillClose(_ notification: Notification) {
        cancelInstall()
        if !decided { UpdateController.shared.remindLater() }
        onClose?()
    }
}

/// Esc is Remind Me Later (or Cancel while installing); ⌘W closes.
private final class UpdatePanelWindow: NSWindow {
    var onCancel: (() -> Void)?

    override func cancelOperation(_ sender: Any?) { onCancel?() }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
           event.charactersIgnoringModifiers?.lowercased() == "w" {
            performClose(nil)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

extension UpdateProblem {
    /// One sentence for the user: why the app offers the manual download.
    var explanation: String {
        switch self {
        case .developmentBuild:
            String(localized: "This is a development build; download the new version from the release page.")
        case .adHocSignature:
            String(localized: "This copy is not signed with the project's certificate, so it cannot check and install the new version itself.")
        case .translocated:
            String(localized: "macOS runs Axolotl Commander from a temporary place. Move it to the Applications folder first.")
        case .readOnlyVolume:
            String(localized: "Axolotl Commander runs from a read-only disk. Move it to the Applications folder first.")
        case .notWritable:
            String(localized: "The folder of Axolotl Commander cannot be changed without an administrator password.")
        case .checksumMissing:
            String(localized: "The release has no checksum for the download.")
        case .checksumMismatch:
            String(localized: "The download is damaged: its checksum does not match.")
        case .badArchive:
            String(localized: "The download does not contain the app as expected.")
        case .identifierMismatch:
            String(localized: "The downloaded app is not Axolotl Commander.")
        case .versionMismatch:
            String(localized: "The downloaded app has another version than the release announces.")
        case .signatureMismatch:
            String(localized: "The new version is signed with another certificate than this copy. Install it by hand.")
        case .replaceFailed(let reason):
            String(localized: "The app could not be replaced: \(reason)")
        }
    }
}
