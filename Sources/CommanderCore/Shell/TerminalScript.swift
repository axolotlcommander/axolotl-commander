public import Foundation

public enum TerminalScript {
    /// Contents of a self-deleting `.command` file Terminal runs. The user's own shell runs the
    /// command and the window stays open with a prompt afterwards. The screen is cleared first,
    /// so the window shows the command instead of the script's path.
    public static func contents(command: String, directory: URL) -> String {
        """
        #!/bin/sh
        rm -f -- "$0"
        cd -- \(ShellQuote.quote(directory.path)) || exit 1
        printf '\\033[H\\033[2J\\033[3J%s\\n' \(ShellQuote.quote("› " + command))
        "${SHELL:-/bin/zsh}" -l -c \(ShellQuote.quote(command))
        exec "${SHELL:-/bin/zsh}" -l

        """
    }
}
