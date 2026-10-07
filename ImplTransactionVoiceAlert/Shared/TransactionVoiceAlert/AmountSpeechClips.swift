//
//  AmountSpeechClips.swift
//  ImplTransactionVoiceAlert
//
//  Created by Houleng.LY on 29/9/26.
//

import Foundation

struct AmountSpeechClips {
    
    let amount: String
    let currency: SpeechCurrency
    let language: SpeechLanguage

    init(amount: String, currency: SpeechCurrency, language: SpeechLanguage) {
        self.amount = amount
        self.currency = currency
        self.language = language
    }
    
    func serialized() -> [String] {
        if language == .khmer {
            return toKhmerClips()
        }
        return toEnglishClips()
    }
    
    private func toKhmerClips() -> [String] {
        
        var cleanAmt = amount.replacingOccurrences(of: " ", with: "")
        cleanAmt = cleanAmt.replacingOccurrences(of: ",", with: "")
        
//        if cleanAmt.count > 9 {
//            return []
//        }
        
        // Parse integer and decimal parts
        let parts = cleanAmt.components(separatedBy: ".")
        guard let integerValue = Int(parts[0]) else { return [] }
        let decimalString = parts.count > 1 ? parts[1] : nil
        
        var sequence: [String] = []
        
        // Build integer part
        if integerValue == 0 {
            sequence.append("")
        } else {
            sequence.append(contentsOf: decomposeNumber(integerValue))
        }
        
        // Append currency word
        switch currency {
        case .USD:
            sequence.append("dollar")
        case .KHR:
            sequence.append("riel")
        }
        
        // Build decimal/cent part (e.g. ".50" → 50 cents)
        if let decStr = decimalString, let centValue = Int(decStr), centValue > 0 {
            // Pad single digit: "5" → 50 cents, "50" → 50 cents
            let cents: Int
            if decStr.count == 1 {
                cents = centValue * 10
            } else {
                cents = centValue
            }
            sequence.append(contentsOf: decomposeNumber(cents))
            sequence.append("cent")
        }
        
        // Append "received" at the end
//        sequence.append("received")
        
        return sequence
    }

    // MARK: - Private helper

    private func decomposeNumber(_ number: Int) -> [String] {
        guard number > 0 else { return [] }
        
        var result: [String] = []
        var remaining = number
        
        // Millions: only use "million" word for 11,000,000 and above
        if remaining >= 11_000_000 {
            let millions = remaining / 1_000_000
            result.append(contentsOf: decomposeNumber(millions))   // was decomposeBelow1000
            result.append("million")
            remaining %= 1_000_000
        }
        
        // 1,000,000 – 10,000,000: use direct files (no "million" word)
        if remaining >= 1_000_000 {
            let millionsDirect = (remaining / 1_000_000) * 1_000_000
            result.append("\(millionsDirect)")
            remaining %= 1_000_000
        }
        
        // Hundred-thousands: 100,000 – 900,000
        if remaining >= 100_000 {
            let hundredThousands = (remaining / 100_000) * 100_000
            result.append("\(hundredThousands)")
            remaining %= 100_000
        }
        
        // Ten-thousands: 10,000 – 90,000
        if remaining >= 10_000 {
            let tenThousands = (remaining / 10_000) * 10_000
            result.append("\(tenThousands)")
            remaining %= 10_000
        }
        
        // Thousands: 1,000 – 9,000
        if remaining >= 1_000 {
            let thousands = (remaining / 1_000) * 1_000
            result.append("\(thousands)")
            remaining %= 1_000
        }
        
        // Hundreds: 100 – 900
        if remaining >= 100 {
            let hundreds = (remaining / 100) * 100
            result.append("\(hundreds)")
            remaining %= 100
        }
        
        // Tens: 10 – 90
        if remaining >= 10 {
            let tens = (remaining / 10) * 10
            result.append("\(tens)")
            remaining %= 10
        }
        
        // Ones: 1 – 9
        if remaining > 0 {
            result.append("\(remaining)")
        }
        
        return result
    }

    private func decomposeBelow1000(_ number: Int) -> [String] {
        var result: [String] = []
        var remaining = number
        
        if remaining >= 100 {
            let hundreds = (remaining / 100) * 100
            result.append("\(hundreds)")
            remaining %= 100
        }
        if remaining >= 10 {
            let tens = (remaining / 10) * 10
            result.append("\(tens)")
            remaining %= 10
        }
        if remaining > 0 {
            result.append("\(remaining)")
        }
        return result
    }
    
    
    private func toEnglishClips() -> [String] {
        
        let cleaned = amount
            .replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespaces)

        guard let value = Decimal(string: cleaned, locale: Locale(identifier: "en_US_POSIX")),
              value >= 0 else { return [] }
        
        var out : [String] = []

        switch currency {
        case .USD:
            var rounded = value * 100
            var result = Decimal()
            NSDecimalRound(&result, &rounded, 0, .plain)
            let total = NSDecimalNumber(decimal: result).intValue
            let dollars = total / 100
            let cents = total % 100

            if dollars > 0 || cents == 0 {
                out += words(dollars)
                out.append(dollars == 1 ? "dollar" : "dollars")
            }
            if cents > 0 {
//                if dollars > 0 { out.append("and") }
                out += words(cents)
                out.append("cent")
            }

        case .KHR:
            out += words(NSDecimalNumber(decimal: value).intValue)
            out.append("riel")
        }
        return out
    }
    
    private func words(_ n: Int) -> [String] {
        n == 0 ? ["zero"] : spell(n)
    }


    private func spell(_ n: Int) -> [String] {
        guard n > 0 else { return [] }

        if n <= 20 { return [String(n)] }
        if n < 100 {
            let t = n / 10 * 10, o = n % 10
            return [String(t)] + (o > 0 ? [String(o)] : [])
        }
        if n < 1_000 {
            let rest = n % 100
            return [String(n / 100), "hundred"] + (rest > 0 ? spell(rest) : [])
        }

        let (unit, name) = n >= 1_000_000 ? (1_000_000, "million") : (1_000, "thousand")
        let rest = n % unit
        var out = spell(n / unit) + [name]
        if rest > 0 {
            out += spell(rest)
        }
        return out
    }
    
}
