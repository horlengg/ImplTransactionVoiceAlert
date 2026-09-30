//
//  SpeechVoice.swift
//  ImplTransactionVoiceAlert
//
//  Created by Houleng.LY on 29/9/26.
//

enum SpeechVoice : String, CaseIterable, Identifiable {
    
    case piseth = "Piseth"
    case sreymom  = "Sreymom"

    var id: String { rawValue }

    var gender: String {
        switch self {
        case .piseth: "Male"
        case .sreymom:  "Female"
        }
    }
    
    var name : String {
        rawValue
    }
    
    var code : String {
        name.lowercased()
    }
    
}
