// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

import Testing
import Foundation
@testable import CommanderCore

@Suite struct ReleaseNotesTests {
    static let changelog = """
        # Changelog

        The format is based on Keep a Changelog.

        ## [Unreleased]

        - Not yet released.

        ## [0.6.0] - 2026-10-14

        ### Added

        - Thumbnails.

        ## [0.5.0] - 2026-10-13

        ### Fixed

        - A fix.

        ## 0.4.3

        - Without brackets and date.

        ## [0.4.2] - 2026-10-01

        - Old.

        ## [0.5.0] - 2026-09-01

        - A repeated section.
        """

    func v(_ text: String) -> AppVersion { AppVersion(text)! }

    @Test func versions() {
        #expect(AppVersion("0.6.0") == AppVersion(major: 0, minor: 6, patch: 0))
        #expect(AppVersion("v1.2.3")?.description == "1.2.3")
        #expect(AppVersion("[0.6.0]")?.description == "0.6.0")
        #expect(AppVersion(" 0.6.0\n")?.description == "0.6.0")
        for bad in ["", "0.6", "0.6.0.1", "a.b.c", "Unreleased", "-1.0.0", "0.6.0-beta"] {
            #expect(AppVersion(bad) == nil, "\(bad)")
        }
        #expect(v("0.10.0") > v("0.9.9"))
        #expect(v("1.0.0") > v("0.99.99"))
        #expect(v("0.6.1") > v("0.6.0"))
    }

    @Test func parse() {
        let notes = ReleaseNotes.parse(Self.changelog)
        #expect(notes.map(\.version.description) == ["0.6.0", "0.5.0", "0.4.3", "0.4.2"])
        #expect(notes[0].date == "2026-10-14")
        #expect(notes[0].body == "### Added\n\n- Thumbnails.")
        #expect(notes[1].body == "### Fixed\n\n- A fix.")   // the first 0.5.0 section is kept
        #expect(notes[2].date == nil)
        #expect(ReleaseNotes.parse("").isEmpty)
        #expect(ReleaseNotes.parse("# Changelog\n\n## [Unreleased]\n- x").isEmpty)
    }

    @Test func localized() {
        let english = ReleaseNotes.parse(Self.changelog)
        let czech = ReleaseNotes.parse("""
            # Změny

            ## [Unreleased]

            - Ještě nevydáno.

            ## [0.7.0] - 2026-10-20

            - Jen v překladu.

            ## [0.6.0] - 2026-10-15

            ### Přidáno

            - Náhledy.

            ## [0.4.3]

            """)
        let notes = ReleaseNotes.localized(english, translated: czech)
        #expect(notes.map(\.version.description) == ["0.6.0", "0.5.0", "0.4.3", "0.4.2"])
        #expect(notes[0].body == "### Přidáno\n\n- Náhledy.")
        #expect(notes[0].date == "2026-10-14")             // the date of the English changelog
        #expect(notes[1].body == english[1].body)           // no translation: English
        #expect(notes[2].body == english[2].body)           // an empty translation does not hide the notes
        #expect(ReleaseNotes.localized(english, translated: []) == english)
    }

    @Test func page() {
        let notes = ReleaseNotes.parse(Self.changelog)
        let page = ReleaseNotes.markdown(Array(notes.prefix(3)))
        #expect(page == """
            ## 0.6.0 — 2026-10-14

            ### Added

            - Thumbnails.

            ## 0.5.0 — 2026-10-13

            ### Fixed

            - A fix.

            ## 0.4.3

            - Without brackets and date.
            """)
    }

    @Test func startDecision() {
        let notes = ReleaseNotes.parse(Self.changelog)
        func shown(_ lastRun: String?, _ running: String = "0.6.0") -> [String] {
            let decision = WhatsNewStart.decide(lastRun: lastRun, running: v(running), notes: notes)
            #expect(decision.remember == running)
            return decision.show.map(\.version.description)
        }
        #expect(shown("0.4.2") == ["0.6.0", "0.5.0", "0.4.3"])
        #expect(shown("0.5.0") == ["0.6.0"])
        #expect(shown("0.6.0").isEmpty)                  // same version
        #expect(shown("0.7.0").isEmpty)                  // downgrade
        #expect(shown(nil).isEmpty)                      // first start
        #expect(shown("garbage").isEmpty)
        #expect(shown("0.6.0", "0.6.1").isEmpty)         // a version without notes
        #expect(shown("0.4.3", "0.6.1") == ["0.6.0", "0.5.0"])
    }
}
