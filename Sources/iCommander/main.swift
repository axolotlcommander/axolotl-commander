import AppKit
import Carbon.HIToolbox
import CommanderCore

// Launched by ssh as SSH_ASKPASS: answer the prompt and quit before any UI starts.
if let status = Askpass.runHelperIfRequested() { exit(status) }

/// The Help key (Insert on PC keyboards) is consumed by AppKit for context
/// help before any keyDown. Commander needs it as Insert, so deliver it directly.
final class CommanderApplication: NSApplication {
    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, event.keyCode == UInt16(kVK_Help),
           let responder = keyWindow?.firstResponder as? PanelTableView {
            responder.keyDown(with: event)
            return
        }
        super.sendEvent(event)
    }
}

let app = CommanderApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
