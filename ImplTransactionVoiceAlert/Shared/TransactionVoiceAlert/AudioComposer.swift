//
//  AudioComposer.swift
//  ImplTransactionVoiceAlert
//

import AVFoundation
import Accelerate

class AudioComposer {

    // MARK: - Public API

    /// Merges the clips at `urls` into one mono 16-bit WAV at `outputURL`.
    /// - Parameters:
    ///   - speed: playback rate for every clip except the first (1.0 = unchanged).
    ///   - enableStretch: apply `speed` via AVAudioUnitTimePitch.
    ///   - fadeMs: crossfade length at each join, in milliseconds (10-30 is typical).
    ///   - targetPeak: final peak level after normalization (0...1).
    static func compose(urls: [URL],
                        outputURL: URL,
                        speed: Float = 1.0,
                        fadeMs: Double = 20,
                        targetPeak: Float = 0.85) throws {

        guard let firstURL = urls.first,
              let firstFile = try? AVAudioFile(forReading: firstURL) else {
            throw NSError(domain: "MergeAudio", code: -1)
        }
        let sampleRate = firstFile.processingFormat.sampleRate

        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                         sampleRate: sampleRate,
                                         channels: 1,
                                         interleaved: false) else {
            throw NSError(domain: "MergeAudio", code: -2)
        }

        let composer = AudioComposer()

        // 1. Load every clip as mono Float at one sample rate (and optionally stretch)
        let clips = try urls.enumerated().map { i, url -> [Float] in
            let samples = try composer.loadAudioMono(url: url, targetRate: sampleRate)
            if i > 0 {
                return try composer.timeStretch(samples, rate: speed, sampleRate: sampleRate)
            }
            return samples
        }

        // 2. Trim, match loudness, crossfade
        var allSamples = composer.joinClips(clips, sampleRate: sampleRate, fadeMs: fadeMs)
        guard !allSamples.isEmpty else {
            throw NSError(domain: "MergeAudio", code: -6)
        }

        // 3. Normalize
        composer.normalize(&allSamples, targetPeak: targetPeak)

        // 4. Write
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format,
                                            frameCapacity: AVAudioFrameCount(allSamples.count)) else {
            throw NSError(domain: "MergeAudio", code: -3)
        }
        buffer.frameLength = AVAudioFrameCount(allSamples.count)
        allSamples.withUnsafeBufferPointer { ptr in
            buffer.floatChannelData![0].update(from: ptr.baseAddress!, count: allSamples.count)
        }

        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false
        ]
        // Created last, so a failure above doesn't leave an empty file behind
        let outputFile = try AVAudioFile(forWriting: outputURL, settings: outputSettings)
        try outputFile.write(from: buffer)
    }

    // MARK: - Joining

    /// Trims each clip, matches its loudness to the audio so far, and joins it
    /// with an equal-power crossfade. The fade removes exactly `fadeLen` samples from
    /// the tail and returns exactly `fadeLen` samples, so nothing is lost or repeated.
    private func joinClips(_ clips: [[Float]], sampleRate: Double, fadeMs: Double) -> [Float] {
        var allSamples: [Float] = []
        let baseFade = max(1, Int(fadeMs / 1000.0 * sampleRate))

        for clip in clips {
            var samples = trimSilence(clip, sampleRate: sampleRate)
            guard !samples.isEmpty else { continue }

            if allSamples.isEmpty {
                allSamples = samples
                continue
            }

            matchLoudness(tail: allSamples, head: &samples)

            // Never fade over more than half of either side
            let fadeLen = min(baseFade, allSamples.count / 2, samples.count / 2)
            guard fadeLen > 0 else {
                allSamples.append(contentsOf: samples)
                continue
            }

            let fade = equalPowerCrossfade(tail: allSamples.suffix(fadeLen),
                                           head: samples.prefix(fadeLen))

            allSamples.removeLast(fadeLen)
            allSamples.append(contentsOf: fade)
            allSamples.append(contentsOf: samples.suffix(from: fadeLen))
        }
        return allSamples
    }

    /// Fades `tail` out and `head` in with cos/sin gains (constant power).
    /// Both slices must have the same length.
    private func equalPowerCrossfade(tail: ArraySlice<Float>, head: ArraySlice<Float>) -> [Float] {
        let n = min(tail.count, head.count)
        var out = [Float](repeating: 0, count: n)
        let denom = Float(max(n - 1, 1))
        for i in 0..<n {
            let t = Float(i) / denom
            out[i] = tail[tail.startIndex + i] * cos(t * .pi / 2)
                   + head[head.startIndex + i] * sin(t * .pi / 2)
        }
        return out
    }

    // MARK: - Silence trimming

    /// Trims leading/trailing silence below `thresholdDB` relative to the peak,
    /// keeping a 10 ms pad on each side.
    private func trimSilence(_ samples: [Float], sampleRate: Double,
                             thresholdDB: Float = -40) -> [Float] {
        guard !samples.isEmpty else { return samples }

        var peak: Float = 0
        vDSP_maxmgv(samples, 1, &peak, vDSP_Length(samples.count))
        guard peak > 0 else { return samples }
        let threshold = peak * pow(10, thresholdDB / 20)

        var start = 0
        while start < samples.count, abs(samples[start]) < threshold { start += 1 }
        var end = samples.count - 1
        while end > start, abs(samples[end]) < threshold { end -= 1 }

        let padSamples = Int(0.01 * sampleRate)   // 10 ms at any sample rate
        let s = max(0, start - padSamples)
        let e = min(samples.count - 1, end + padSamples)
        return Array(samples[s...e])
    }

    // MARK: - Loudness

    /// Scales `head` so its RMS over `windowLen` samples matches `tail`'s RMS,
    /// preventing a perceptible volume jump at the join.
    /// Skipped if either side is shorter than `windowLen`.
    private func matchLoudness(tail: [Float], head: inout [Float], windowLen: Int = 2048) {
        guard tail.count >= windowLen, head.count >= windowLen else { return }

        var tailRMS: Float = 0
        var headRMS: Float = 0
        vDSP_rmsqv(Array(tail.suffix(windowLen)), 1, &tailRMS, vDSP_Length(windowLen))
        vDSP_rmsqv(Array(head.prefix(windowLen)), 1, &headRMS, vDSP_Length(windowLen))
        guard headRMS > 0.0001 else { return }

        var gain = min(max(tailRMS / headRMS, 0.5), 2.0)   // clamp extreme corrections
        let source = head
        vDSP_vsmul(source, 1, &gain, &head, 1, vDSP_Length(head.count))
    }

    /// Scales the whole signal so its peak equals `targetPeak`.
    private func normalize(_ samples: inout [Float], targetPeak: Float) {
        var peak: Float = 0
        vDSP_maxmgv(samples, 1, &peak, vDSP_Length(samples.count))
        guard peak > 0 else { return }
        var gain = targetPeak / peak
        let source = samples
        vDSP_vsmul(source, 1, &gain, &samples, 1, vDSP_Length(samples.count))
    }

    // MARK: - Time stretch
    /// Changes speed without changing pitch, using AVAudioUnitTimePitch offline.
    private func timeStretch(_ samples: [Float], rate: Float, sampleRate: Double) throws -> [Float] {
        guard rate != 1, !samples.isEmpty else { return samples }

        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                   sampleRate: sampleRate, channels: 1, interleaved: false)!
        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        let timePitch = AVAudioUnitTimePitch()
        timePitch.rate = rate                       // 1.0...32.0; e.g. 1.25 = 25% faster

        engine.attach(player)
        engine.attach(timePitch)
        engine.connect(player, to: timePitch, format: format)
        engine.connect(timePitch, to: engine.mainMixerNode, format: format)

        try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 4096)
        try engine.start()

        let input = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count))!
        input.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer {
            input.floatChannelData![0].update(from: $0.baseAddress!, count: samples.count)
        }
        player.scheduleBuffer(input, completionHandler: nil)
        player.play()

        let outBuf = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat,
                                      frameCapacity: engine.manualRenderingMaximumFrameCount)!
        let expected = Int(Double(samples.count) / Double(rate))
        var out = [Float]()
        out.reserveCapacity(expected)

        while out.count < expected {
            let n = min(AVAudioFrameCount(expected - out.count), outBuf.frameCapacity)
            let status = try engine.renderOffline(n, to: outBuf)
            guard status == .success else { break }
            out.append(contentsOf: UnsafeBufferPointer(start: outBuf.floatChannelData![0],
                                                       count: Int(outBuf.frameLength)))
        }
        engine.stop()
        return out
    }

    // MARK: - Loading

    /// Reads a file, converts it to mono Float32 at `targetRate`.
    func loadAudioMono(url: URL, targetRate: Double) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        let inFormat = file.processingFormat

        guard let outFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                            sampleRate: targetRate,
                                            channels: 1,
                                            interleaved: false),
              let converter = AVAudioConverter(from: inFormat, to: outFormat),
              let inBuf = AVAudioPCMBuffer(pcmFormat: inFormat, frameCapacity: 8192)
        else { throw NSError(domain: "MergeAudio", code: -2) }

        let ratio = targetRate / inFormat.sampleRate
        let outCapacity = AVAudioFrameCount(Double(8192) * ratio) + 1024
        guard let outBuf = AVAudioPCMBuffer(pcmFormat: outFormat, frameCapacity: outCapacity)
        else { throw NSError(domain: "MergeAudio", code: -3) }

        var samples = [Float]()
        var finished = false

        while !finished {
            outBuf.frameLength = 0
            var convError: NSError?

            let status = converter.convert(to: outBuf, error: &convError) { _, inStatus in
                do {
                    inBuf.frameLength = 0
                    try file.read(into: inBuf, frameCount: 8192)
                } catch {
                    inStatus.pointee = .endOfStream
                    return nil
                }
                if inBuf.frameLength == 0 {
                    inStatus.pointee = .endOfStream
                    return nil
                }
                inStatus.pointee = .haveData
                return inBuf
            }

            if status == .error { throw convError ?? NSError(domain: "MergeAudio", code: -4) }

            if outBuf.frameLength > 0, let ch = outBuf.floatChannelData?[0] {
                samples.append(contentsOf: UnsafeBufferPointer(start: ch, count: Int(outBuf.frameLength)))
            }
            if status == .endOfStream { finished = true }
        }
        return samples
    }
}
