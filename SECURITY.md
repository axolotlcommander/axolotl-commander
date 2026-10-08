# Security

## Reporting a vulnerability

Do **not** report security vulnerabilities in a public issue. Use GitHub's private reporting:
[Report a vulnerability](https://github.com/axolotlcommander/axolotl-commander/security/advisories/new),
or e-mail **acidek@icloud.com**.

Please say what the bug affects (e.g. archive extraction, SFTP/FTP, Markdown/HTML preview,
password storage), how to reproduce it, and what impact it may have. We will respond within
14 days; the fix is published together with credit to you, if you want it.

We mainly consider the following to be security bugs:

- writing outside the target directory when extracting an archive (`../`, absolute paths, symlinks),
- password leaks (into history, logs, URLs, or onto disk outside the Keychain),
- running code or loading remote content from a preview without consent,
- loss or overwriting of data that an operation is not allowed to change.

## Supported versions

Fixes are released for the latest released version and for the `main` branch.
