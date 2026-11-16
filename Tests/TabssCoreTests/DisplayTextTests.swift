import Testing
@testable import TabssCore

struct DisplayTextTests {
    @Test func keepsOrdinaryTitles() {
        #expect(DisplayText.title("Inbox — Mail", fallback: "Mail") == "Inbox — Mail")
        #expect(DisplayText.title("日本語 📄 résumé", fallback: "x") == "日本語 📄 résumé")
    }

    @Test func removesDirectionOverridesAndControlCharacters() {
        #expect(DisplayText.title("invoice\u{202E}fdp.exe", fallback: "x") == "invoicefdp.exe")
        #expect(DisplayText.title("a\u{2066}b\u{2069}c\u{200F}", fallback: "x") == "abc")
        #expect(DisplayText.title("line\nbreak\ttab\u{0}", fallback: "x") == "line break tab")
    }

    @Test func trimsWhitespaceAndFallsBackWhenEmpty() {
        #expect(DisplayText.title("  Notes  ", fallback: "x") == "Notes")
        #expect(DisplayText.title("", fallback: "Finder") == "Finder")
        #expect(DisplayText.title(" \u{202E} ", fallback: "Finder") == "Finder")
    }
}

struct DisplayTextEdgeCaseTests {
    @Test func removesEveryDirectionalFormattingCharacter() {
        for value: UInt32 in [0x200E, 0x200F, 0x202A, 0x202B, 0x202C, 0x202D, 0x202E, 0x2066, 0x2067, 0x2068, 0x2069] {
            let scalar = Unicode.Scalar(value)!
            #expect(DisplayText.title("a\(Character(scalar))b", fallback: "x") == "ab", "U+\(String(value, radix: 16))")
        }
    }

    @Test func lineSeparatorsBecomeSpacesAndVisibleSpacesStay() {
        #expect(DisplayText.title("a\u{2029}b\u{2028}c", fallback: "x") == "a b c")
        #expect(DisplayText.title("a\u{202F}b", fallback: "x") == "a\u{202F}b")  // narrow no-break space
    }

    @Test func removesInvisibleFormatCharacters() {
        #expect(DisplayText.title("a\u{200B}b\u{2060}c\u{FEFF}d\u{206A}e", fallback: "x") == "abcde")
        #expect(DisplayText.title("\u{200B}\u{FEFF}", fallback: "Finder") == "Finder")
    }

    @Test func deleteAndC1ControlsBecomeSpaces() {
        #expect(DisplayText.title("a\u{7F}b\u{80}c\u{9F}d", fallback: "x") == "a b c d")
        #expect(DisplayText.title("cr\r\nlf", fallback: "x") == "cr  lf")
    }

    @Test func keepsJoinersSoEmojiSequencesAndCombiningMarksSurvive() {
        let family = "👨\u{200D}👩\u{200D}👧"
        #expect(DisplayText.title(family, fallback: "x") == family)
        #expect(DisplayText.title("e\u{301}", fallback: "x") == "e\u{301}")
        #expect(DisplayText.title("🇹🇷 flag", fallback: "x") == "🇹🇷 flag")
    }

    @Test func trimsUnicodeWhitespaceButKeepsInnerSpacing() {
        #expect(DisplayText.title("\u{00A0}\u{3000}Notes\u{2003} ", fallback: "x") == "Notes")
        #expect(DisplayText.title("a  b", fallback: "x") == "a  b")
        #expect(DisplayText.title("\u{202E} a \u{202C}", fallback: "x") == "a")
    }

    @Test func controlCharactersBetweenWhitespaceStillTrim() {
        // Filtering runs before trimming, so control characters can't shield whitespace from the trim.
        #expect(DisplayText.title(" \u{0} Title \u{7} ", fallback: "x") == "Title")
        #expect(DisplayText.title("\t\n\u{0}", fallback: "Finder") == "Finder")
    }

    @Test func returnsFallbackUnchanged() {
        #expect(DisplayText.title("   ", fallback: "  App  ") == "  App  ")
    }

    @Test func removesArabicLetterMark() {
        #expect(DisplayText.title("a\u{061C}b", fallback: "x") == "ab")
    }
}

struct DisplayTextIgnorableTests {
    // Default-ignorable code points that aren't format characters (Hangul fillers, combining grapheme joiner)
    // are invisible too and must not survive between visible letters.
    @Test func removesDefaultIgnorableNonFormatCharacters() {
        #expect(DisplayText.title("Pay\u{3164}Pal", fallback: "x") == "PayPal")
        #expect(DisplayText.title("a\u{034F}b\u{115F}c\u{FFA0}d", fallback: "x") == "abcd")
    }

    @Test func keepsIdeographicVariationSelectors() {
        let withSelector = "\u{845B}\u{E0100}"  // 葛 with an ideographic variation selector
        #expect(DisplayText.title(withSelector, fallback: "x") == withSelector)
    }

    // Only the tag range that builds subdivision flags is kept; the deprecated language tag is dropped.
    @Test func dropsLanguageTagButKeepsFlagTags() {
        #expect(DisplayText.title("a\u{E0001}b", fallback: "x") == "ab")
    }
}
