//
//  VoiceAlertDemoViewModel.swift
//  ImplTransactionVoiceAlert
//
//  Created by Houleng.LY on 29/9/26.
//
import SwiftUI
import Combine
import AVFAudio


@MainActor
final class VoiceAlertDemoViewModel: NSObject, ObservableObject, AVAudioPlayerDelegate {

    // Input
    @Published var amount = "100.50"
    @Published var currency: SpeechCurrency = .USD
    @Published var language: SpeechLanguage = .khmer
    @Published var voice: SpeechVoice = SpeechVoice.allCases[0]

    // State
    @Published private(set) var tokens: [String] = []
    @Published private(set) var isBusy = false
    @Published private(set) var isPlaying = false
    @Published private(set) var errorMessage: String?

    private var player: AVAudioPlayer?
    private var lastFileURL: URL?

    private enum PlayerError: LocalizedError {
        case invalidAmount
        case missingClip(String)

        var errorDescription: String? {
            switch self {
            case .invalidAmount: return "Please enter a valid amount."
            case .missingClip(let token): return "Missing audio clip: \(token)"
            }
        }
    }


    func play() {
        guard !isBusy else { return }
        stop()
        errorMessage = nil
        isBusy = true

        let amount = self.amount
        let currency = self.currency
        let language = self.language
        let voice = self.voice

        Task {
            do {
                let result = try await Task.detached(priority: .userInitiated) {
                    try await Self.buildAudio(amount: amount,
                                        currency: currency,
                                        language: language,
                                        voice: voice)
                }.value

                tokens = result.tokens
                cleanupLastFile()
                lastFileURL = result.url

                try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
                try AVAudioSession.sharedInstance().setActive(true)

                let player = try AVAudioPlayer(contentsOf: result.url)
                player.delegate = self
                player.prepareToPlay()
                player.play()
                self.player = player
                isPlaying = true
            } catch {
                errorMessage = error.localizedDescription
            }
            isBusy = false
        }
    }

    func stop() {
        player?.stop()
        player = nil
        isPlaying = false
    }

    // MARK: Input

    /// Keeps only digits and a single ".", with at most 9 integer digits
    /// (the Khmer sequence rejects longer numbers) and 2 decimal places.
    static func sanitizeAmount(_ raw: String) -> String {
        var result = ""
        var seenDot = false
        var integerDigits = 0
        var decimalDigits = 0

        for ch in raw {
            if ("0"..."9").contains(ch) {
                if seenDot {
                    guard decimalDigits < 2 else { continue }
                    decimalDigits += 1
                } else {
                    guard integerDigits < 9 else { continue }
                    integerDigits += 1
                }
                result.append(ch)
            } else if ch == ".", !seenDot {
                if result.isEmpty { result = "0" }   // ".5" → "0.5"
                result.append(".")
                seenDot = true
            }
        }
        return result
    }
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.isPlaying = false
        }
    }


    private static func buildAudio(
        amount: String,
        currency: SpeechCurrency,
        language: SpeechLanguage,
        voice: SpeechVoice
    ) throws -> (url: URL, tokens: [String]) {

        let clipTokens = SpeechSequence(amount: amount,
                                        currency: currency,
                                        language: language).serializeClips()
        guard !clipTokens.isEmpty else { throw PlayerError.invalidAmount }

        let tokens = ["received"] + clipTokens

        let fm = FileManager.default
        let workDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: workDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: workDir) }

        let prefix = "\(language.code)/\(voice.name)"
        let clipURLs: [URL] = try tokens.map { token in
            let assetName = "\(prefix)/\(token)"
            guard let asset = NSDataAsset(name: assetName) else {
                throw PlayerError.missingClip(token)
            }
            let url = workDir
                .appendingPathComponent(assetName.replacingOccurrences(of: "/", with: "_"))
                .appendingPathExtension("mp3")
            try asset.data.write(to: url, options: .atomic)
            return url
        }

        let output = fm.temporaryDirectory
            .appendingPathComponent("paysound-preview-\(UUID().uuidString).caf")
        try AudioComposer.compose(urls: clipURLs,
                                  outputURL: output,
                                  speed: language == .english ? 1.2 : nil)
        return (output, tokens)
    }

    private func cleanupLastFile() {
        if let url = lastFileURL { try? FileManager.default.removeItem(at: url) }
        lastFileURL = nil
    }
}
