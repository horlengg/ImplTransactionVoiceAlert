//
//  AppGroupStorageManager.swift
//  ImplTransactionVoiceAlert
//
//  Created by Houleng.LY on 29/9/26.
//


import Foundation


enum MbGroupSessionKey: String {
    case paysoundEnabled = "paysound_enabled"
    case speechVoice = "paysound_voice_type"
    case speechLanguage = "paysound_voice_language"
}

class AppGroupStorageManager {
    
    static let shared = AppGroupStorageManager()
    
    private let userDefaults: UserDefaults?
    
    private init() {
        self.userDefaults = UserDefaults(suiteName: AppGroupStorageManager.identifier)
    }
    
    static var identifier: String {
        guard let id = Bundle.main.object(
            forInfoDictionaryKey: "AppGroupID"
        ) as? String, !id.isEmpty else {
            fatalError("AppGroupID not configured in Info.plist")
        }
        return id
    }

    static var containerURL: URL? {
       FileManager.default.containerURL(
           forSecurityApplicationGroupIdentifier: identifier
       )
   }
    
    // MARK: - Base Storage
    
    private func set(value: Any, key: MbGroupSessionKey) {
        userDefaults?.setValue(value, forKey: key.rawValue)
    }
    
    private func get(_ key: MbGroupSessionKey) -> Any? {
        userDefaults?.value(forKey: key.rawValue)
    }
    
    private func remove(_ key: MbGroupSessionKey) {
        userDefaults?.removeObject(forKey: key.rawValue)
    }
    
    // MARK: - Paysound
    
    func saveEnablePaysound(_ enable: Bool) {
        set(value: enable, key: .paysoundEnabled)
    }
    
    func getEnablePaysound() -> Bool {
        get(.paysoundEnabled) as? Bool ?? false
    }
    
    func saveSpeechVoice(_ voice: String) {
        set(value: voice, key: .speechVoice)
    }
    
    func getSpeechVoice() -> String {
        get(.speechVoice) as? String ?? ""
    }
    
    func saveSpeechLanguage(_ language: String) {
        set(value: language, key: .speechLanguage)
    }
    
    func getSpeechLanguage() -> String {
        get(.speechLanguage) as? String ?? ""
    }
    
    func showAllCaches() {
        
        #if DEBUG
        guard let userDefaults = userDefaults else {
            print("UserDefaults not found for suite: \(AppGroupStorageManager.identifier)")
            return
        }
        
        let dict = userDefaults.dictionaryRepresentation()
        
        print("===== App Group UserDefaults Cache =====")
        print("Suite: \(AppGroupStorageManager.identifier)")
        print("Total keys: \(dict.count)")
        print("==========================================")
        
        dict.sorted { $0.key < $1.key }.forEach { key, value in
            print("\(key): \(value)")
        }
        
        print("==========================================")
        #endif
        
        
    }
    
    func clearUserDefaults() {
        guard let userDefaults = userDefaults else { return }
        
        let keys: [MbGroupSessionKey] = [
            .paysoundEnabled,
            .speechVoice,
            .speechLanguage
        ]
        
        keys.forEach { userDefaults.removeObject(forKey: $0.rawValue) }
    }
    
}
