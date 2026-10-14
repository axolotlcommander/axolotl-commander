// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

import AppKit
import CommanderCore

/// Checking for updates (spec 027): once a day by itself, at once from the menu, Settings and About.
@MainActor
final class UpdateController {
    static let shared = UpdateController()
    /// Posted when the remembered state changes (Settings and About show it).
    static let stateChanged = Notification.Name("UpdateController.stateChanged")
    static let releasesURL = URL(string: "https://api.github.com/repos/axolotlcommander/axolotl-commander/releases/latest")!
    /// GitHub requires a User-Agent; it carries no version or other detail (FR-005).
    nonisolated static let userAgent = "AxolotlCommander"

    private let defaults = UserDefaults.standard
    private var timer: Timer?
    private var manualCheck: Task<Void, Never>?
    private var progress: CheckProgressWindow?
    private(set) var window: UpdateWindowController?
    /// The release the last check found (in this copy); the title-bar button opens it without a new request.
    private var found: ReleaseInfo?

    var runningVersion: AppVersion? { WhatsNew.runningVersion }
    var state: UpdateState { UpdateState(defaults) }

    /// The project's releases, or the hidden test address (never shown in Settings).
    private var feedURL: URL {
        defaults.string(forKey: UpdateState.feedURLKey).flatMap(URL.init(string:)) ?? Self.releasesURL
    }

    /// The automatic check: a few seconds after the main window, then re-evaluated every 15 minutes.
    func start() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in self?.checkIfDue() }
        timer = Timer.scheduledTimer(withTimeInterval: 15 * 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkIfDue() }
        }
    }

    func checkIfDue() {
        guard let running = runningVersion, window == nil, manualCheck == nil else { return }
        var state = state
        let now = Date()
        guard state.isDue(now: now) else { return }
        // Written first, so another running copy finds the check not due (R7).
        state.lastCheck = now
        state.save(to: defaults)
        let url = feedURL
        Task {
            let result = await Self.latest(from: url)
            self.finish(result, running: running, manual: false)
        }
    }

    /// Check for Updates… and Check Now: always answers.
    func checkNow() {
        guard let running = runningVersion else { return }
        if let window { window.showWindow(nil); return }
        manualCheck?.cancel()
        let url = feedURL
        // A progress window with Cancel when the answer takes longer than a second.
        let progress = CheckProgressWindow { [weak self] in self?.cancelManualCheck() }
        self.progress = progress
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self, weak progress] in
            if let progress, self?.progress === progress { progress.showWindow(nil) }
        }
        manualCheck = Task {
            let result = await Self.latest(from: url)
            guard !Task.isCancelled else { return }
            self.closeProgress()
            self.manualCheck = nil
            self.finish(result, running: running, manual: true)
        }
    }

    private func cancelManualCheck() {
        manualCheck?.cancel()
        manualCheck = nil
        closeProgress()
    }

    private func closeProgress() {
        progress?.close()
        progress = nil
    }

    enum CheckFailure: Error {
        case network(String)
        case server(Int)
        case malformed
    }

    private func finish(_ result: Result<ReleaseInfo, CheckFailure>, running: AppVersion, manual: Bool) {
        var state = state
        let now = Date()
        switch result {
        case .failure(let failure):
            state.recordFailure(now: now)
            state.save(to: defaults)
            NotificationCenter.default.post(name: Self.stateChanged, object: nil)
            if manual { reportFailure(failure) }
        case .success(let release):
            let usable = !release.isDraft && !release.isPrerelease ? release : nil
            state.recordSuccess(usable, running: running, now: now)
            state.save(to: defaults)
            found = state.lastResult == .available ? release : nil
            NotificationCenter.default.post(name: Self.stateChanged, object: nil)
            // The automatic check only shows the title-bar button (clarification 2026-10-14).
            guard manual else { return }
            if state.offers(release, running: running, manual: true, now: now) {
                Task { await self.offer(release, running: running) }
            } else {
                reportNoUpdate(release, running: running)
            }
        }
    }

    /// Reads the release's changelogs (small files) and opens the update window (only on the user's request).
    private func offer(_ release: ReleaseInfo, running: AppVersion) async {
        let english = await Self.optionalText(release.changelog)
        let language = Bundle.main.preferredLocalizations.first ?? "en"
        let translated = language == "cs" ? await Self.optionalText(release.czechChangelog) : nil
        let notes = UpdateNotes.notes(english: english, translated: translated, running: running, offered: release.version)
        if let window { window.showWindow(nil); return }
        let problem = CodeSignatureVerifier.forRunningApp() == nil && InstallCapability.check(appURL: Bundle.main.bundleURL) == nil
            ? .adHocSignature : InstallCapability.check(appURL: Bundle.main.bundleURL)
        let window = UpdateWindowController(release: release, running: running, notes: notes, problem: problem)
        window.onClose = { [weak self] in self?.window = nil }
        self.window = window
        window.showWindow(nil)
        window.window?.makeKeyAndOrderFront(nil)
    }

    /// The version for the title-bar button: found, newer than the running one, not skipped and not put off.
    var buttonVersion: AppVersion? {
        let state = state
        guard let running = runningVersion, state.lastResult == .available, let version = state.availableVersion,
              version > running, version != state.skippedVersion else { return nil }
        if let remindAfter = state.remindAfter, Date() < remindAfter { return nil }
        return version
    }

    /// The title-bar button and About's Install…: the window for the found release, or a check that opens it.
    func showFound() {
        if let window { window.showWindow(nil); return }
        guard let running = runningVersion, let found, found.version == state.availableVersion else { checkNow(); return }
        Task { await offer(found, running: running) }
    }

    /// The user's decisions in the update window.
    func remindLater() {
        var state = state
        state.remindLater(now: Date())
        state.save(to: defaults)
        NotificationCenter.default.post(name: Self.stateChanged, object: nil)
    }

    func skip(_ version: AppVersion) {
        var state = state
        state.skip(version)
        state.save(to: defaults)
        NotificationCenter.default.post(name: Self.stateChanged, object: nil)
    }

    func setAutomatic(_ on: Bool) {
        defaults.set(on, forKey: UpdateState.automaticKey)
        NotificationCenter.default.post(name: Self.stateChanged, object: nil)
    }

    /// Stops a download and removes its files when the app quits.
    func applicationWillTerminate() {
        window?.cancelInstall()
    }

    // MARK: Messages

    private func reportNoUpdate(_ release: ReleaseInfo, running: AppVersion) {
        let alert = NSAlert()
        if release.version > running {
            alert.messageText = String(localized: "No suitable release was found.")
            alert.informativeText = String(localized: "The newest release has no app archive for this Mac yet. Try again later.")
        } else {
            alert.messageText = String(localized: "Axolotl Commander \(running.description) is the latest version.")
        }
        NSApp.activate()
        alert.runModal()
    }

    private func reportFailure(_ failure: CheckFailure) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = String(localized: "The check for updates failed.")
        switch failure {
        case .network(let reason): alert.informativeText = reason
        case .server(403), .server(429):
            alert.informativeText = String(localized: "The release server is busy. Try again in a few minutes.")
        case .server(let status):
            alert.informativeText = String(localized: "The release server answered with an error (\(status)).")
        case .malformed:
            alert.informativeText = String(localized: "The release server sent an answer the app does not understand.")
        }
        alert.addButton(withTitle: String(localized: "Try Again"))
        alert.addButton(withTitle: String(localized: "OK"))
        NSApp.activate()
        if alert.runModal() == .alertFirstButtonReturn { checkNow() }
    }

    /// The text for Settings and About.
    func statusText() -> String {
        let state = state
        let date = state.lastCheck.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? ""
        switch state.lastResult {
        case nil: return String(localized: "Never checked.")
        case .available:
            return String(localized: "Version \(state.availableVersion?.description ?? "") is available.")
        case .upToDate: return String(localized: "Up to date (checked \(date)).")
        case .failed: return String(localized: "The last check failed (\(date)).")
        }
    }

    // MARK: Network

    nonisolated static func request(_ url: URL) -> URLRequest {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        return request
    }

    /// An ephemeral session: no cookies, no cache, no credentials.
    nonisolated static let session = URLSession(configuration: .ephemeral)

    nonisolated static func latest(from url: URL) async -> Result<ReleaseInfo, CheckFailure> {
        do {
            let (data, response) = try await session.data(for: request(url))
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(status) else { return .failure(.server(status)) }
            guard let release = try? ReleaseInfo.parse(data) else { return .failure(.malformed) }
            return .success(release)
        } catch {
            return .failure(.network(error.localizedDescription))
        }
    }

    nonisolated static func optionalText(_ url: URL?) async -> String? {
        guard let url else { return nil }
        return try? await text(from: url)
    }

    nonisolated static func text(from url: URL) async throws -> String {
        let (data, response) = try await session.data(for: request(url))
        guard let status = (response as? HTTPURLResponse)?.statusCode, (200..<300).contains(status) else {
            throw CheckFailure.server((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        return String(decoding: data, as: UTF8.self)
    }
}

/// A file download with progress into a given place (the zip of an update).
final class FileDownload: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let destination: URL
    private let progress: @Sendable (Double) -> Void
    private let lock = NSLock()
    private var continuation: CheckedContinuation<URL, any Error>?
    private var task: URLSessionDownloadTask?
    private var failure: (any Error)?
    private var cancelled = false

    init(to destination: URL, progress: @escaping @Sendable (Double) -> Void) {
        self.destination = destination
        self.progress = progress
    }

    func run(_ url: URL) async throws -> URL {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, any Error>) in
                let session = URLSession(configuration: .ephemeral, delegate: self, delegateQueue: nil)
                let task = session.downloadTask(with: UpdateController.request(url))
                let cancelled = lock.withLock {
                    self.continuation = continuation
                    self.task = task
                    return self.cancelled
                }
                if cancelled { task.cancel() } else { task.resume() }
            }
        } onCancel: {
            lock.withLock {
                cancelled = true
                return task
            }?.cancel()
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        progress(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // The file is only valid during this call.
        let status = (downloadTask.response as? HTTPURLResponse)?.statusCode ?? 0
        do {
            guard (200..<300).contains(status) else { throw UpdateController.CheckFailure.server(status) }
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: location, to: destination)
        } catch {
            lock.withLock { failure = error }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        session.finishTasksAndInvalidate()
        let (continuation, failure) = lock.withLock {
            defer { self.continuation = nil }
            return (self.continuation, self.failure)
        }
        if let error = error ?? failure { continuation?.resume(throwing: error) } else { continuation?.resume(returning: destination) }
    }
}

/// "Checking for updates…" with Cancel, for a check that takes more than a moment.
final class CheckProgressWindow: NSWindowController {
    private let onCancel: () -> Void

    init(onCancel: @escaping () -> Void) {
        self.onCancel = onCancel
        let window = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 320, height: 90), styleMask: [.titled],
                             backing: .buffered, defer: true)
        window.title = String(localized: "Check for Updates")
        window.isReleasedWhenClosed = false
        super.init(window: window)
        let spinner = NSProgressIndicator()
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.startAnimation(nil)
        let label = NSTextField(labelWithString: String(localized: "Checking for updates…"))
        let cancel = NSButton(title: String(localized: "Cancel"), target: self, action: #selector(cancel))
        cancel.keyEquivalent = "\u{1b}"
        let row = NSStackView(views: [spinner, label])
        let stack = NSStackView(views: [row, cancel])
        stack.orientation = .vertical
        stack.alignment = .trailing
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 20, bottom: 16, right: 20)
        window.contentView = stack
        window.setContentSize(stack.fittingSize)
        window.center()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    @objc private func cancel() { onCancel() }
}

/// "↑ Version X.Y.Z" at the right end of the main window's title bar while an update is waiting (R10): takes no
/// focus and opens nothing by itself; a click opens the update window.
final class UpdateTitlebarButton: NSTitlebarAccessoryViewController {
    private let button = NSButton(title: "", target: nil, action: nil)
    private var observer: (any NSObjectProtocol)?

    static func attach(to window: NSWindow) {
        window.addTitlebarAccessoryViewController(UpdateTitlebarButton())
    }

    override func loadView() {
        button.bezelStyle = .accessoryBarAction
        button.controlSize = .small
        button.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        button.contentTintColor = .controlAccentColor
        button.image = NSImage(systemSymbolName: "arrow.up.circle.fill", accessibilityDescription: nil)
        button.imagePosition = .imageLeading
        button.refusesFirstResponder = true
        button.target = self
        button.action = #selector(open)
        button.setAccessibilityIdentifier("update.titlebar")
        let container = NSView()
        button.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(button)
        NSLayoutConstraint.activate([
            button.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 6),
            button.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),
            button.centerYAnchor.constraint(equalTo: container.centerYAnchor),
        ])
        view = container
        layoutAttribute = .trailing
        observer = NotificationCenter.default.addObserver(forName: UpdateController.stateChanged, object: nil,
                                                          queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        refresh()
    }

    private func refresh() {
        let version = UpdateController.shared.buttonVersion
        button.title = version.map { String(localized: "Version \($0.description)") } ?? ""
        button.toolTip = String(localized: "A new version of Axolotl Commander is available")
        isHidden = version == nil
        view.frame.size = NSSize(width: version == nil ? 0 : button.fittingSize.width + 14, height: 28)
    }

    @objc private func open() { UpdateController.shared.showFound() }
}
