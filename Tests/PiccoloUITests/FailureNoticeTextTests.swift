import Foundation
import Testing

import PiccoloCore

@testable import PiccoloUI

@Suite("Failure notice texts")
struct FailureNoticeTextTests {
    @Test("every notice has a text in every language, and none is the English one except in English")
    func everyLanguage() throws {
        for language in AppLanguage.languages {
            let bundle = try #require(language.textBundle, "no texts for \(language)")
            for notice in FailureNotice.allCases {
                let text = FailureNoticeText.text(for: notice, bundle: bundle)
                #expect(!text.isEmpty, "\(notice) has no text in \(language)")
                #expect(!text.contains("\n"), "\(notice) in \(language) is not one line")
                if language != .en {
                    let english = FailureNoticeText.text(for: notice, bundle: AppLanguage.en.textBundle!)
                    #expect(text != english, "\(notice) is not translated into \(language)")
                }
            }
        }
    }

    @Test("the English texts are short")
    func shortEnglish() throws {
        let bundle = try #require(AppLanguage.en.textBundle)
        for notice in FailureNotice.allCases {
            let text = FailureNoticeText.text(for: notice, bundle: bundle)
            #expect(text.count <= 45, "\(notice): \"\(text)\" is \(text.count) characters")
        }
    }

    @Test("every notice has its own text")
    func distinct() throws {
        let bundle = try #require(AppLanguage.en.textBundle)
        let texts = FailureNotice.allCases.map { FailureNoticeText.text(for: $0, bundle: bundle) }
        #expect(Set(texts).count == texts.count)
    }

    @Test("simplified Chinese calls Accessibility 辅助功能")
    func accessibilityTerm() throws {
        let bundle = try #require(AppLanguage.zhHans.textBundle)
        #expect(FailureNoticeText.text(for: .accessibilityNotGranted, bundle: bundle).contains("辅助功能"))
    }
}
