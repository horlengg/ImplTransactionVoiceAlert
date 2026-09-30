//
//  SpeechLanguage.swift
//  ImplTransactionVoiceAlert
//
//  Created by Houleng.LY on 29/9/26.
//



enum SpeechLanguage: String, CaseIterable, Identifiable {
    
    case khmer = "km-KH"
    case english = "en-US"

    var id: String { rawValue }
    var code: String { rawValue }

    var name : String {
        switch self {
        case .khmer:
            return "ភាសាខ្មែរ"
        case .english:
            return "English"
        }
    }
    
    var prefixCode : String {
        switch self {
        case .khmer:   return "kh"
        case .english: return "en"
        }
    }
    
}
