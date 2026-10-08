// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

import AppKit
import CommanderCore

/// New Symbolic Link (⌃⌘L), New Hard Link, Edit Symbolic Link, Paste as Symbolic Link (⌃⌘V, ⌃S)
/// and Go to Link Target (⌃T). New links go to the other panel's folder, as in Unix two-panel file
/// managers, and never replace an existing item.
extension PanelViewController {
    /// The folder new links go to: the other panel's, unless it shows no folder on this Mac.
    private var linkFolder: URL {
        guard let other = router?.otherPanel(than: self),
              other.model.archive == nil, other.model.remote == nil, other.model.results == nil
        else { return model.location }
        return other.model.location
    }

    func newLink(_ kind: LinkKind) {
        let sources = targets()
        guard !sources.isEmpty, let window = view.window else { return }
        let folder = linkFolder
        let single = sources.count == 1
        let sheet = LinkSheetModel(
            mode: kind == .symbolic ? .symbolic : .hard,
            count: sources.count,
            target: single ? sources[0].url.displayPath : "",
            destination: single ? folder.appendingPathComponent(sources[0].name).displayPath : folder.displayPath,
            relative: UserDefaults.standard.bool(forKey: LinkSheetModel.relativeKey))
        LinkSheet.present(sheet, in: window) { [weak self] sheet in
            guard let self else { return true }
            return single
                ? await createLink(kind, to: sources[0].url, sheet: sheet)
                : await createLinks(kind, to: sources.map(\.url), sheet: sheet)
        }
    }

    func editSymbolicLink() {
        guard let item = model.cursorItem, item.isSymlink, let window = view.window,
              let stored = try? FileManager.default.destinationOfSymbolicLink(atPath: item.url.path)
        else { return }
        let folder = item.url.deletingLastPathComponent().path
        let sheet = LinkSheetModel(mode: .edit, count: 1, target: stored, destination: item.url.displayPath,
                                   relative: LinkPaths.isRelative(stored), linkFolder: folder)
        LinkSheet.present(sheet, in: window) { [weak self] sheet in
            guard let self, let operations = router?.operations else { return true }
            let stored = LinkPaths.storedTarget(typed: sheet.target, linkFolder: folder, relative: sheet.relative)
            guard await confirmMissingTarget(stored, linkFolder: folder) else { return false }
            do {
                try await operations.operations.retargetSymbolicLink(item.url, storing: stored)
            } catch {
                sheet.message = OperationsController.describe(error)
                return false
            }
            await linksCreated(in: item.url.deletingLastPathComponent(), focusing: item.name)
            return true
        }
    }

    func pasteAsSymbolicLinks() {
        let pb = NSPasteboard.general
        guard let urls = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
              !urls.isEmpty, let operations = router?.operations else { return }
        let folder = model.location
        Task {
            let outcomes = await operations.operations.makeLinks(.symbolic, to: urls, in: folder, relative: false)
            await linksCreated(in: folder, focusing: outcomes.lazy.compactMap(\.created).first?.lastPathComponent)
            await reportSkipped(outcomes)
        }
    }

    func goToLinkTarget() {
        guard let item = model.cursorItem, !item.isParent else { return }
        Task {
            do {
                let target = try await Task.detached { try LinkTarget.resolve(item.url) }.value
                if target.hasDirectoryPath {
                    go(to: target)
                } else {
                    go(to: target.deletingLastPathComponent(), focusing: target.lastPathComponent)
                }
            } catch {
                NSSound.beep()
                router?.operations.report(error)
            }
        }
    }

    /// Enables Go to Link Target: a symbolic link or a Finder alias under the cursor.
    var cursorIsLink: Bool {
        guard let item = model.cursorItem, !item.isParent else { return false }
        return item.isSymlink || LinkTarget.isLink(item.url)
    }

    // MARK: Creating

    private func createLink(_ kind: LinkKind, to source: URL, sheet: LinkSheetModel) async -> Bool {
        guard let operations = router?.operations else { return true }
        guard let path = localPath(sheet.destination, sheet: sheet) else { return false }
        let folder = (path as NSString).deletingLastPathComponent
        do {
            switch kind {
            case .symbolic:
                let stored = LinkPaths.storedTarget(typed: sheet.target, linkFolder: folder, relative: sheet.relative)
                guard await confirmMissingTarget(stored, linkFolder: folder) else { return false }
                try await operations.operations.makeSymbolicLink(at: path, storing: stored)
            case .hard:
                try await operations.operations.makeHardLink(at: path, to: source)
            }
        } catch {
            sheet.message = OperationsController.describe(error)
            return false
        }
        await linksCreated(in: URL(fileURLWithPath: folder, isDirectory: true),
                           focusing: (path as NSString).lastPathComponent)
        return true
    }

    private func createLinks(_ kind: LinkKind, to sources: [URL], sheet: LinkSheetModel) async -> Bool {
        guard let operations = router?.operations else { return true }
        guard let path = localPath(sheet.destination, sheet: sheet) else { return false }
        var info = stat()
        guard stat(path, &info) == 0, info.st_mode & S_IFMT == S_IFDIR else {
            sheet.message = String(localized: "The folder “\(sheet.destination)” does not exist.")
            return false
        }
        let folder = URL(fileURLWithPath: path, isDirectory: true)
        let outcomes = await operations.operations.makeLinks(kind, to: sources, in: folder, relative: sheet.relative)
        await linksCreated(in: folder, focusing: outcomes.lazy.compactMap(\.created).first?.lastPathComponent)
        Task { await reportSkipped(outcomes) }
        return true
    }

    /// The typed destination as a path on this Mac (relative text is taken from this panel's folder).
    private func localPath(_ text: String, sheet: LinkSheetModel) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            sheet.message = OperationsController.describe(OperationError.path(.empty))
            return nil
        }
        let expanded = (trimmed as NSString).expandingTildeInPath
        guard let url = try? PathInput.resolve(expanded, relativeTo: model.location, absoluteIsLocal: true),
              url.isFileURL, RemoteURL.parse(url) == nil
        else {
            sheet.message = String(localized: "Links can only be created in folders on this Mac.")
            return nil
        }
        return url.standardizedFileURL.path
    }

    /// A target that does not exist is legitimate, but only on purpose.
    private func confirmMissingTarget(_ stored: String, linkFolder: String) async -> Bool {
        var info = stat()
        if lstat(LinkPaths.absolute(stored, linkFolder: linkFolder), &info) == 0 { return true }
        let alert = NSAlert()
        alert.messageText = String(localized: "The target does not exist. Create the link anyway?")
        alert.informativeText = stored
        alert.addButton(withTitle: String(localized: "Create"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        return await OperationsController.present(alert, in: view.window) == .alertFirstButtonReturn
    }

    /// Both panels reread; the ones showing `folder` put the cursor on `name`.
    private func linksCreated(in folder: URL, focusing name: String?) async {
        guard let router else { return }
        await router.refreshPanels()
        guard let name else { return }
        let path = folder.standardizedFileURL.path
        for panel in [router.left, router.right]
        where panel.model.archive == nil && panel.model.remote == nil
            && panel.model.location.standardizedFileURL.path == path {
            panel.focus(name: name)
        }
    }

    private func reportSkipped(_ outcomes: [LinkOutcome]) async {
        let skipped = outcomes.compactMap { outcome -> String? in
            guard case .skipped(let error) = outcome.result else { return nil }
            return "\(outcome.source.lastPathComponent): \(OperationsController.describe(error))"
        }
        guard !skipped.isEmpty else { return }
        let text = skipped.prefix(20).joined(separator: "\n")
            + (skipped.count > 20 ? "\n" + String(localized: "…and \(skipped.count - 20) more") : "")
        await router?.operations.inform(String(localized: "Some links were not created."), text)
    }
}
