//
//  NotificationService.swift
//  NotificationService
//
//  Created by Houleng.LY on 29/9/26.
//


import UserNotifications
import os
import UIKit

final class NotificationService: UNNotificationServiceExtension {

    private enum Config {
        static let soundFilePrefix = "merged-"
        static let soundMaxAge: TimeInterval = 24 * 60 * 60
    }

    private enum SpeechError: Error {
        case invalidPayload
        case missingClip(String)
        case noAppGroup
    }

    private let log = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "NotificationService",
        category: "spoken-amount"
    )

    private var contentHandler: ((UNNotificationContent) -> Void)?
    private var bestAttemptContent: UNMutableNotificationContent?
    
    private var speechVoice : SpeechVoice {
        SpeechVoice(rawValue : AppGroupStorageManager.shared.getSpeechVoice()) ?? .piseth
    }
    private var speechLanguage : SpeechLanguage {
        SpeechLanguage(rawValue : AppGroupStorageManager.shared.getSpeechLanguage()) ?? .khmer
    }
    
    private var voicePrefixPath : String {
//        guard let lang = speechLanguage, let voice = speechVoice else {return ""}
        return "\(speechLanguage.code)/\(speechVoice.name)"
    }

    override func didReceive(
        _ request: UNNotificationRequest,
        withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
    ) {
        
        let isPaysoundEnabled = AppGroupStorageManager.shared.getEnablePaysound()
        log.info("isPaysoundEnabled : \(isPaysoundEnabled)")
//        
//        guard isPaysoundEnabled else {
//            contentHandler(request.content)
//            return
//        }
        
        self.contentHandler = contentHandler

        guard let content = request.content.mutableCopy() as? UNMutableNotificationContent else {
            contentHandler(request.content)
            return
        }
        bestAttemptContent = content
        do {
            try applyPaysoundAudio(to: content, userInfo: request.content.userInfo)
        } catch {
            log.error("Spoken amount skipped: \(String(describing: error), privacy: .public)")
        }

        contentHandler(content)
    }

    override func serviceExtensionTimeWillExpire() {
        if let contentHandler, let bestAttemptContent {
            contentHandler(bestAttemptContent)
        }
    }

    private func applyPaysoundAudio(
        to content: UNMutableNotificationContent,
        userInfo: [AnyHashable: Any]
    ) throws {
        
        guard let amount = userInfo["trxAmount"] as? String, !amount.isEmpty,
              let currencyCode = userInfo["trxCurrency"] as? String,
              let currency = SpeechCurrency(rawValue: currencyCode)
//              let language = speechLanguage
        else {
            throw SpeechError.invalidPayload
        }
        
        let tokens = ["received"] + SpeechSequence(
            amount: amount,
            currency: currency,
            language: speechLanguage
        ).serializeClips()

        let fm = FileManager.default
        let workDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: workDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: workDir) }

        let clips = try tokens.map { try writeClip(token: $0, to: workDir) }
        let merged = workDir.appendingPathComponent("merged.caf")
        try AudioComposer.compose(urls: clips, outputURL: merged,speed: speechLanguage == .english ? 1.2 : nil)
        let soundName = "\(Config.soundFilePrefix)\(UUID().uuidString).caf"
        do {
            try installSound(from: merged, named: soundName)
            content.sound = UNNotificationSound(named: UNNotificationSoundName(soundName))
            content.body = "\(amount) \(currency) is received to account 10163717 from account 00010442765618"
        } catch {
            log.error("Sound install failed: \(String(describing: error), privacy: .public)")
        }
        do {
            content.attachments = [
                try UNNotificationAttachment(identifier: "merged-audio", url: merged)
            ]
        } catch {
            log.error("Attachment failed: \(String(describing: error), privacy: .public)")
        }
    }

    private func writeClip(token: String, to directory: URL) throws -> URL {
        let assetName = "\(voicePrefixPath)/\(token)"
        guard let asset = NSDataAsset(name: assetName, bundle: Bundle(for: Self.self)) else {
            throw SpeechError.missingClip(token)
        }
        let url = directory
            .appendingPathComponent(assetName.replacingOccurrences(of: "/", with: "_"))
            .appendingPathExtension("mp3")
        if !FileManager.default.fileExists(atPath: url.path) {
            try asset.data.write(to: url, options: .atomic)
        }
        return url
    }

    private func installSound(from source: URL, named name: String) throws {
        guard let container = AppGroupStorageManager.containerURL else { throw SpeechError.noAppGroup }
        let fm = FileManager.default
        let soundsDir = container.appendingPathComponent("Library/Sounds", isDirectory: true)
        try fm.createDirectory(at: soundsDir, withIntermediateDirectories: true)
        pruneOldSounds(in: soundsDir)
        try fm.copyItem(at: source, to: soundsDir.appendingPathComponent(name))
    }

    /// Each notification writes a new file and nothing else removes them, so clean up here.
    private func pruneOldSounds(in directory: URL) {
        let fm = FileManager.default
        let cutoff = Date().addingTimeInterval(-Config.soundMaxAge)
        let files = (try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey]
        )) ?? []

        for file in files where file.lastPathComponent.hasPrefix(Config.soundFilePrefix) {
            let modified = try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
            if let modified, modified < cutoff {
                try? fm.removeItem(at: file)
            }
        }
    }
}
