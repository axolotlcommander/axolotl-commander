// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

import CommanderCore
import Foundation
import Testing

@Suite struct SizeFormatTests {
    private let cs = Locale(identifier: "cs_CZ")
    private let en = Locale(identifier: "en_US")
    private let samples: [Int64] = [0, 1, 402, 999, 1_000, 1_023, 1_024, 4_300_000, 46_000_000, 1_200_000_000_000]

    /// Spaces of any kind as plain spaces: the system may group with a no-break space.
    private func plain(_ text: String) -> String {
        String(text.map { $0.isWhitespace ? " " : $0 })
    }

    @Test func roundedIsTheSystemFileSizeText() {
        for locale in [cs, en] {
            for bytes in samples {
                #expect(SizeFormat.rounded(bytes, units: .decimal, locale: locale)
                    == bytes.formatted(ByteCountFormatStyle(style: .file, locale: locale)))
                #expect(SizeFormat.rounded(bytes, units: .binary, locale: locale)
                    == bytes.formatted(ByteCountFormatStyle(style: .binary, locale: locale)))
            }
        }
    }

    @Test func roundedFollowsTheBase() {
        #expect(plain(SizeFormat.rounded(4_300_000, units: .decimal, locale: cs)) == "4,3 MB")
        #expect(plain(SizeFormat.rounded(4_300_000, units: .binary, locale: cs)) == "4,1 MB")
        #expect(plain(SizeFormat.rounded(4_300_000, units: .decimal, locale: en)) == "4.3 MB")
        #expect(plain(SizeFormat.rounded(402, units: .decimal, locale: cs)) == "402 bajtů")
        #expect(plain(SizeFormat.rounded(999, units: .decimal, locale: cs)) == "1 kB")
        #expect(plain(SizeFormat.rounded(999, units: .binary, locale: cs)) == "999 bajtů")
        #expect(SizeFormat.rounded(1_200_000_000_000, units: .decimal, locale: en).contains("TB"))
        #expect(!SizeFormat.rounded(4_300_000, units: .binary, locale: en).contains("iB"))
    }

    @Test func exactGroupsEveryDigit() {
        #expect(plain(SizeFormat.exact(4_300_000, locale: cs)) == "4 300 000")
        #expect(SizeFormat.exact(4_300_000, locale: en) == "4,300,000")
    }

    @Test func columnVariantsFollowTheMode() {
        let finder = SizeFormat(display: .finder, units: .decimal)
        #expect(finder.columnVariants(4_300_000, locale: cs).map(plain) == ["4,3 MB"])
        let bytes = SizeFormat(display: .bytes, units: .binary)
        #expect(bytes.columnVariants(4_300_000, locale: cs).map(plain) == ["4 300 000", "4,1 MB"])
        #expect(bytes.columnVariants(402, locale: cs).map(plain) == ["402", "402 bajtů"])
        for bytesCount in samples {
            let variants = bytes.columnVariants(bytesCount, locale: en)
            #expect(Set(variants).count == variants.count)
        }
    }

    @Test func roundedIsExactOnlyWhenEveryByteIsShown() {
        let decimal = SizeFormat(units: .decimal), binary = SizeFormat(units: .binary)
        #expect(decimal.roundedIsExact(402, locale: cs))
        #expect(binary.roundedIsExact(1_000, locale: cs))
        #expect(!decimal.roundedIsExact(1_000, locale: cs))
        #expect(!decimal.roundedIsExact(4_300_000, locale: cs))
        #expect(!decimal.roundedIsExact(0, locale: en))
    }

    @Test func defaultsAndUnknownValues() {
        #expect(SizeFormat() == SizeFormat(display: .finder, units: .decimal))
        #expect(SizeDisplay(rawValue: "kb") == nil)
        #expect(SizeUnits(rawValue: "iec") == nil)
        #expect(SizeDisplay(rawValue: "bytes") == .bytes)
        #expect(SizeUnits(rawValue: "binary") == .binary)
    }
}
