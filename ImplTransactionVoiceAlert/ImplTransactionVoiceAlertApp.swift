//
//  ImplTransactionVoiceAlertApp.swift
//  ImplTransactionVoiceAlert
//
//  Created by Houleng.LY on 29/9/26.
//

import SwiftUI

@main
struct ImplTransactionVoiceAlertApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    var body: some Scene {
        WindowGroup {
            VoiceAlertDemoView()
        }
    }
}
