//
//  AmountSpeechClipsTests.swift
//  ImplTransactionVoiceAlert
//
//  Created by Houleng.LY on 30/9/26.
//



import XCTest
@testable import ImplTransactionVoiceAlert

final class AmountSpeechClipsTests: XCTestCase {

    // MARK: - Helpers

    private func km(_ amount: String, _ currency: SpeechCurrency) -> [String] {
        AmountSpeechClips(amount: amount, currency: currency, language: .khmer).serialized()
    }

    private func en(_ amount: String, _ currency: SpeechCurrency) -> [String] {
        AmountSpeechClips(amount: amount, currency: currency, language: .english).serialized()
    }

    // =========================================================
    // MARK: - Khmer: integers
    // =========================================================

    func testKhmer_zero_USD_usesEmptyClip() {
        XCTAssertEqual(km("0", .USD), ["", "dollar"])
    }

    func testKhmer_singleDigit() {
        XCTAssertEqual(km("1", .USD), ["1", "dollar"])
        XCTAssertEqual(km("9", .USD), ["9", "dollar"])
    }

    func testKhmer_tens() {
        XCTAssertEqual(km("10", .USD), ["10", "dollar"])
        XCTAssertEqual(km("25", .USD), ["20", "5", "dollar"])
    }

    func testKhmer_hundreds() {
        XCTAssertEqual(km("100", .USD), ["100", "dollar"])
        XCTAssertEqual(km("305", .USD), ["300", "5", "dollar"])
        XCTAssertEqual(km("999", .USD), ["900", "90", "9", "dollar"])
    }

    func testKhmer_thousands() {
        XCTAssertEqual(km("1000", .KHR), ["1000", "riel"])
        XCTAssertEqual(km("1234", .KHR), ["1000", "200", "30", "4", "riel"])
    }

    func testKhmer_tenThousandsAndHundredThousands() {
        XCTAssertEqual(km("10000", .KHR), ["10000", "riel"])
        XCTAssertEqual(km("250000", .KHR), ["200000", "50000", "riel"])
        XCTAssertEqual(km("123456", .KHR), ["100000", "20000", "3000", "400", "50", "6", "riel"])
    }

    func testKhmer_million_upTo10Million_usesDirectClip_noMillionWord() {
        XCTAssertEqual(km("1000000", .KHR), ["1000000", "riel"])
        XCTAssertEqual(km("5000000", .KHR), ["5000000", "riel"])
        XCTAssertEqual(km("10000000", .KHR), ["10000000", "riel"])
    }

    func testKhmer_11Million_andAbove_usesMillionWord() {
        XCTAssertEqual(km("11000000", .KHR), ["10", "1", "million", "riel"])
        XCTAssertEqual(km("25000000", .KHR), ["20", "5", "million", "riel"])
    }

    func testKhmer_millionWithRemainder() {
        // 11,234,567
        XCTAssertEqual(
            km("11234567", .KHR),
            ["10", "1", "million", "200000", "30000", "4000", "500", "60", "7", "riel"]
        )
        // 1,500,000 (direct clip + remainder)
        XCTAssertEqual(km("1500000", .KHR), ["1000000", "500000", "riel"])
    }

    func testKhmer_maxNineDigits() {
        XCTAssertEqual(
            km("123456789", .KHR),
            ["100", "20", "3", "million", "400000", "50000", "6000", "700", "80", "9", "riel"]
        )
    }
    
    
    func testKhmer_AmountOverBillion_KHR() {
        XCTAssertEqual(km("1,000,080,000", .KHR), ["1000","million","80000","riel"])
        XCTAssertEqual(km("1,234,500,000", .KHR), ["1000","200","30","4","million","500000","riel"])
        XCTAssertEqual(km("10,234,080,000", .KHR), ["10000","200","30","4","million","80000","riel"])
    }
    
    func testKhmer_AmountOverBillion_USD() {
        XCTAssertEqual(km("1,000,080,000.00", .USD), ["1000","million","80000","dollar"])
        XCTAssertEqual(km("1,234,500,000.1", .USD), ["1000","200","30","4","million","500000","dollar","10","cent"])
        XCTAssertEqual(km("10,234,500,000.50", .USD), ["10000","200","30","4","million","500000","dollar","50","cent"])
    }

    // =========================================================
    // MARK: - Khmer: currency
    // =========================================================

    func testKhmer_currencyWord() {
        XCTAssertEqual(km("5", .USD).last, "dollar")
        XCTAssertEqual(km("5", .KHR).last, "riel")
    }

    // =========================================================
    // MARK: - Khmer: decimals / cent
    // =========================================================

    func testKhmer_cent_twoDigits() {
        XCTAssertEqual(km("1.50", .USD), ["1", "dollar", "50", "cent"])
        XCTAssertEqual(km("12.34", .USD), ["10", "2", "dollar", "30", "4", "cent"])
    }

    func testKhmer_cent_singleDigit_isPaddedToTens() {
        // ".5" means 50 cent
        XCTAssertEqual(km("1.5", .USD), ["1", "dollar", "50", "cent"])
    }

    func testKhmer_cent_leadingZero() {
        // ".05" means 5 cent
        XCTAssertEqual(km("1.05", .USD), ["1", "dollar", "5", "cent"])
    }

    func testKhmer_cent_zeroIsIgnored() {
        XCTAssertEqual(km("1.00", .USD), ["1", "dollar"])
        XCTAssertEqual(km("1.0", .USD), ["1", "dollar"])
    }

    func testKhmer_zeroDollarsWithCents() {
        XCTAssertEqual(km("0.75", .USD), ["", "dollar", "70", "5", "cent"])
    }

    func testKhmer_nonNumericDecimal_isIgnored() {
        XCTAssertEqual(km("1.ab", .USD), ["1", "dollar"])
    }
    
    func testKhmer_numberMillion_USD() {
        XCTAssertEqual(km("1,234,567.89", .USD), ["1000000", "200000", "30000", "4000", "500", "60", "7", "dollar", "80", "9", "cent"])
    }

    // =========================================================
    // MARK: - Khmer: input cleaning / invalid input
    // =========================================================

    func testKhmer_stripsCommasAndSpaces() {
        XCTAssertEqual(km("1,250", .KHR), ["1000", "200", "50", "riel"])
        XCTAssertEqual(km("1 250", .KHR), ["1000", "200", "50", "riel"])
        XCTAssertEqual(km(" 1, 250 ", .KHR), ["1000", "200", "50", "riel"])
    }

    func testKhmer_invalidInput_returnsEmpty() {
        XCTAssertEqual(km("", .USD), [])
        XCTAssertEqual(km("abc", .USD), [])
        XCTAssertEqual(km(".50", .USD), [])   // no integer part
    }

    

    func testKhmer_threeDecimalDigits_readAsCents_quirk() {
        XCTAssertEqual(km("1.999", .USD), ["1", "dollar", "900", "90", "9", "cent"])
    }

    func testKhmer_negativeNumber_dropsAmount_quirk() {
        XCTAssertEqual(km("-5", .USD), ["dollar"])
    }

    // =========================================================
    // MARK: - English: USD
    // =========================================================

    func testEnglish_USD_zero() {
        XCTAssertEqual(en("0", .USD), ["zero", "dollars"])
        XCTAssertEqual(en("0.00", .USD), ["zero", "dollars"])
    }

    func testEnglish_USD_singularVsPlural() {
        XCTAssertEqual(en("1", .USD), ["1", "dollar"])
        XCTAssertEqual(en("2", .USD), ["2", "dollars"])
    }

    func testEnglish_USD_upTo20() {
        XCTAssertEqual(en("11", .USD), ["11", "dollars"])
        XCTAssertEqual(en("20", .USD), ["20", "dollars"])
    }

    func testEnglish_USD_tens() {
        XCTAssertEqual(en("21", .USD), ["20", "1", "dollars"])
        XCTAssertEqual(en("90", .USD), ["90", "dollars"])
        XCTAssertEqual(en("99", .USD), ["90", "9", "dollars"])
    }

    func testEnglish_USD_hundreds() {
        XCTAssertEqual(en("100", .USD), ["1", "hundred", "dollars"])
        XCTAssertEqual(en("101", .USD), ["1", "hundred", "1", "dollars"])
        XCTAssertEqual(en("342", .USD), ["3", "hundred", "40", "2", "dollars"])
        XCTAssertEqual(en("915", .USD), ["9", "hundred", "15", "dollars"])
    }

    func testEnglish_USD_thousands() {
        XCTAssertEqual(en("1000", .USD), ["1", "thousand", "dollars"])
        XCTAssertEqual(en("1001", .USD), ["1", "thousand", "1", "dollars"])
        XCTAssertEqual(en("1100", .USD), ["1", "thousand", "1", "hundred", "dollars"])
        XCTAssertEqual(
            en("1234", .USD),
            ["1", "thousand", "2", "hundred", "30", "4", "dollars"]
        )
        XCTAssertEqual(en("21000", .USD), ["20", "1", "thousand", "dollars"])
    }

    func testEnglish_USD_millions() {
        XCTAssertEqual(en("1000000", .USD), ["1", "million", "dollars"])
        XCTAssertEqual(en("1000005", .USD), ["1", "million", "5", "dollars"])
        XCTAssertEqual(
            en("2500000", .USD),
            ["2", "million", "5", "hundred", "thousand", "dollars"]
        )
    }
    
    // MARK: English: cent

    func testEnglish_USD_centOnly() {
        XCTAssertEqual(en("0.01", .USD), ["1", "cent"])
        XCTAssertEqual(en("0.50", .USD), ["50", "cent"])
        XCTAssertEqual(en("0.99", .USD), ["90", "9", "cent"])
    }

    func testEnglish_USD_dollarsAndCents() {
        XCTAssertEqual(en("1.01", .USD), ["1", "dollar", "1", "cent"])
        XCTAssertEqual(en("1.50", .USD), ["1", "dollar", "50", "cent"])
        XCTAssertEqual(en("12.34", .USD), ["12", "dollars", "30", "4", "cent"])
    }

    func testEnglish_USD_zeroCentsIsOmitted() {
        XCTAssertEqual(en("5.00", .USD), ["5", "dollars"])
    }

    func testEnglish_USD_roundsToNearestCent() {
        XCTAssertEqual(en("1.005", .USD), ["1", "dollar", "1", "cent"])   // .plain rounds half up
        XCTAssertEqual(en("1.004", .USD), ["1", "dollar"])
        XCTAssertEqual(en("0.999", .USD), ["1", "dollar"])                        // carries into dollars
    }

    // =========================================================
    // MARK: - English: KHR
    // =========================================================

    func testEnglish_KHR_basic() {
        XCTAssertEqual(en("0", .KHR), ["zero", "riel"])
        XCTAssertEqual(en("100", .KHR), ["1", "hundred", "riel"])
        XCTAssertEqual(en("4000", .KHR), ["4", "thousand", "riel"])
        XCTAssertEqual(en("1,500", .KHR), ["1", "thousand", "5", "hundred", "riel"])
    }

    func testEnglish_KHR_fractionIsTruncated() {
        XCTAssertEqual(en("1500.75", .KHR), ["1", "thousand", "5", "hundred", "riel"])
    }

    func testEnglish_KHR_hasNoSingularPlural() {
        XCTAssertEqual(en("1", .KHR), ["1", "riel"])
        XCTAssertEqual(en("2", .KHR), ["2", "riel"])
    }

    // =========================================================
    // MARK: - English: input cleaning / invalid input
    // =========================================================

    func testEnglish_stripsCommasAndTrimsWhitespace() {
        XCTAssertEqual(en("1,234", .USD), en("1234", .USD))
        XCTAssertEqual(en("  5  ", .USD), ["5", "dollars"])
    }

    func testEnglish_invalidInput_returnsEmpty() {
        XCTAssertEqual(en("", .USD), [])
        XCTAssertEqual(en("abc", .USD), [])
//        XCTAssertEqual(en("1.2.3", .USD), [])
    }

    func testEnglish_negative_returnsEmpty() {
        XCTAssertEqual(en("-5", .USD), [])
        XCTAssertEqual(en("-5", .KHR), [])
    }

    // =========================================================
    // MARK: - Language dispatch
    // =========================================================

    func testSerializeClips_dispatchesByLanguage() {
        let khmer = AmountSpeechClips(amount: "1.50", currency: .USD, language: .khmer).serialized()
        let english = AmountSpeechClips(amount: "1.50", currency: .USD, language: .english).serialized()

        XCTAssertEqual(khmer, ["1", "dollar", "50", "cent"])
        XCTAssertEqual(english, ["1", "dollar", "50", "cent"])
    }

    func testInit_storesProperties() {
        let seq = AmountSpeechClips(amount: "12", currency: .KHR, language: .khmer)
        XCTAssertEqual(seq.amount, "12")
        XCTAssertEqual(seq.currency, .KHR)
        XCTAssertEqual(seq.language, .khmer)
    }
}
