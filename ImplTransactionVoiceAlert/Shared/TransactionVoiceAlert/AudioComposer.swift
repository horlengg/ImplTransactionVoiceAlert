//
//  AudioComposer.swift
//  ImplTransactionVoiceAlert
//
//  Created by Houleng.LY on 29/9/26.
//

import AVFoundation
import Accelerate

class AudioComposer {
    /// Read an entire AVAudioFile into a Float array (mono assumed; extend per-channel if needed).
    private func readAllSamples(_ file: AVAudioFile) throws -> [Float] {
        let format = file.processingFormat
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(file.length)) else {
            throw NSError(domain: "MergeAudio", code: -4)
        }
        try file.read(into: buffer)
        guard let channelData = buffer.floatChannelData else {
            throw NSError(domain: "MergeAudio", code: -5)
        }
        return Array(UnsafeBufferPointer(start: channelData[0], count: Int(buffer.frameLength)))
    }

    /// Very simple autocorrelation-based pitch period estimate (in samples) over a window.
    /// minF0/maxF0 in Hz bound the search range.
    private func estimatePitchPeriod(_ samples: [Float], sampleRate: Double,
                                      minF0: Double = 75, maxF0: Double = 400) -> Int {
        let minLag = Int(sampleRate / maxF0)
        let maxLag = Int(sampleRate / minF0)
        guard samples.count > maxLag * 2 else { return Int(sampleRate / 150) } // fallback ~150Hz
        var bestLag = minLag
        var bestCorr: Float = -.infinity
        let n = min(samples.count - maxLag, 2048)
        for lag in minLag...maxLag {
            var corr: Float = 0
            vDSP_dotpr(samples, 1, Array(samples[lag...]), 1, &corr, vDSP_Length(n))
            if corr > bestCorr {
                bestCorr = corr
                bestLag = lag
            }
        }
        return bestLag
    }

    /// Pitch marks via peak-picking on the signal energy envelope, spaced by the local period.
    private func generatePitchMarks(_ samples: [Float], period: Int) -> [Int] {
        var marks: [Int] = []
        var pos = period / 2
        // find the local max magnitude sample within +/- period/4 to act as an epoch anchor
        while pos < samples.count {
            let searchStart = max(0, pos - period / 4)
            let searchEnd = min(samples.count - 1, pos + period / 4)
            var peakIdx = pos
            var peakVal: Float = -1
            for i in searchStart...searchEnd {
                let v = abs(samples[i])
                if v > peakVal { peakVal = v; peakIdx = i }
            }
            marks.append(peakIdx)
            pos = peakIdx + period
        }
        return marks
    }

    private func hannWindow(_ length: Int) -> [Float] {
        var w = [Float](repeating: 0, count: length)
        vDSP_hann_window(&w, vDSP_Length(length), Int32(vDSP_HANN_NORM))
        return w
    }

    // MARK: - Pitch-synchronous crossfade join

    /// Crossfades the tail of `a` into the head of `b` using pitch-synchronous OLA windows.
    /// `crossfadePeriods` = how many pitch periods to blend over (2-4 is typical).
    private func psolaCrossfadeJoin(tail: [Float], head: [Float], sampleRate: Double,
                                     crossfadePeriods: Int = 3) -> [Float] {
        let periodA = estimatePitchPeriod(tail, sampleRate: sampleRate)
        let periodB = estimatePitchPeriod(head, sampleRate: sampleRate)
        let avgPeriod = (periodA + periodB) / 2
        let fadeLen = avgPeriod * crossfadePeriods

        guard tail.count >= fadeLen, head.count >= fadeLen else {
            // not enough material to crossfade meaningfully — fall back to a short linear fade
            return simpleLinearCrossfade(tail: tail, head: head, fadeLen: min(tail.count, head.count, 256))
        }

        let aRegion = Array(tail.suffix(fadeLen))
        let bRegion = Array(head.prefix(fadeLen))

        let marksA = generatePitchMarks(aRegion, period: periodA)
        let marksB = generatePitchMarks(bRegion, period: periodB)

        var out = [Float](repeating: 0, count: fadeLen)
        var norm = [Float](repeating: 0, count: fadeLen)

        // Overlap-add pitch periods from A (fading out) and B (fading in), each windowed with Hann.
        func overlapAdd(_ samples: [Float], marks: [Int], period: Int, gainCurve: (Float) -> Float) {
            let winLen = period * 2
            let win = hannWindow(winLen)
            for m in marks {
                let start = m - period
                guard start >= 0, start + winLen <= samples.count else { continue }
                let t = Float(m) / Float(fadeLen) // 0...1 position within the crossfade
                let gain = gainCurve(t)
                for i in 0..<winLen {
                    let outIdx = start + i
                    guard outIdx >= 0, outIdx < fadeLen else { continue }
                    let sample = samples[start + i] * win[i] * gain
                    out[outIdx] += sample
                    norm[outIdx] += win[i]
                }
            }
        }

        overlapAdd(aRegion, marks: marksA, period: periodA, gainCurve: { 1 - $0 }) // fade out
        overlapAdd(bRegion, marks: marksB, period: periodB, gainCurve: { $0 })     // fade in

        for i in 0..<fadeLen where norm[i] > 0.0001 {
            out[i] /= norm[i]
        }

        return out
    }

    private func simpleLinearCrossfade(tail: [Float], head: [Float], fadeLen: Int) -> [Float] {
        var out = [Float](repeating: 0, count: fadeLen)
        for i in 0..<fadeLen {
            let t = Float(i) / Float(fadeLen)
            out[i] = tail[tail.count - fadeLen + i] * (1 - t) + head[i] * t
        }
        return out
    }

    static func compose(urls: [URL], outputURL: URL,speed: Float? = nil) throws {
        guard let firstFile = try? AVAudioFile(forReading: urls[0]) else {
            throw NSError(domain: "MergeAudio", code: -1)
        }
        let sampleRate = firstFile.processingFormat.sampleRate   // or a fixed 22050/24000

        // Mono processing format (this replaces firstFile.processingFormat)
        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                         sampleRate: sampleRate,
                                         channels: 1,
                                         interleaved: false) else {
            throw NSError(domain: "MergeAudio", code: -2)
        }

        let composer = AudioComposer()
        let clips = try urls.enumerated().map { i, url -> [Float] in
            let samples = try composer.loadAudioMono(url: url, targetRate: sampleRate)
            if let speed {
                return i == 0 ? samples
                              : try composer.timeStretch(samples, rate: speed, sampleRate: sampleRate)
            }
            return samples
        }
        var allSamples = try composer.synthesizePitch(clips: clips, sampleRate: sampleRate)

        // Optional: raise the level (your peak was ~0.23)
        if let peak = allSamples.map({ abs($0) }).max(), peak > 0 {
            let gain = 0.85 / peak
            for i in allSamples.indices { allSamples[i] *= gain }
        }

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
            AVNumberOfChannelsKey: 1,                 // was format.channelCount
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false
        ]
        // Created last, so a failure above doesn't leave an empty file behind
        let outputFile = try AVAudioFile(forWriting: outputURL, settings: outputSettings)
        try outputFile.write(from: buffer)
    }
    
    private func synthesizePitch(clips: [[Float]], sampleRate: Double) throws -> [Float] {
        var allSamples: [Float] = []

        for clip in clips {
            var samples = trimSilence(clip)
            guard !samples.isEmpty else { continue }

            if allSamples.isEmpty {
                allSamples = samples
                continue
            }

            matchLoudness(tail: allSamples, head: &samples)

            // Clamp the fade so a bad pitch estimate can't produce a nonsense length
            let period = max(1, estimatePitchPeriod(samples, sampleRate: sampleRate))
            let maxFade = min(allSamples.count, samples.count) / 2
            let fadeLen = min(period * 3, maxFade)

            guard fadeLen > 0 else {
                allSamples.append(contentsOf: samples)
                continue
            }

            let tail = Array(allSamples.suffix(fadeLen))
            let head = Array(samples.prefix(fadeLen))
            let crossfaded = psolaCrossfadeJoin(tail: tail, head: head, sampleRate: sampleRate)

            allSamples.removeLast(fadeLen)
            allSamples.append(contentsOf: crossfaded)
            allSamples.append(contentsOf: samples.suffix(from: fadeLen))
        }
        return allSamples
    }


    // MARK: - Silence trimming

    /// Trims leading/trailing silence below `thresholdDB` relative to peak.
    private func trimSilence(_ samples: [Float], thresholdDB: Float = -40) -> [Float] {
        guard !samples.isEmpty else { return samples }
        var peak: Float = 0
        vDSP_maxmgv(samples, 1, &peak, vDSP_Length(samples.count))
        guard peak > 0 else { return samples }
        let threshold = peak * pow(10, thresholdDB / 20)

        var start = 0
        while start < samples.count, abs(samples[start]) < threshold { start += 1 }
        var end = samples.count - 1
        while end > start, abs(samples[end]) < threshold { end -= 1 }

        // Keep a small pad (~10ms) so the PSOLA crossfade has clean pitch periods to work with
        let padSamples = 441 // ~10ms @ 44.1kHz, adjust to your sampleRate
        let s = max(0, start - padSamples)
        let e = min(samples.count - 1, end + padSamples)
        return Array(samples[s...e])
    }

    // MARK: - Loudness matching at the seam

    /// Scales `head` so its RMS over `windowLen` samples matches `tail`'s RMS,
    /// preventing a perceptible volume jump at the join.
    private func matchLoudness(tail: [Float], head: inout [Float], windowLen: Int = 2048) {
        guard tail.count >= windowLen, head.count >= windowLen else { return }
        var tailRMS: Float = 0
        var headRMS: Float = 0
        vDSP_rmsqv(Array(tail.suffix(windowLen)), 1, &tailRMS, vDSP_Length(windowLen))
        vDSP_rmsqv(Array(head.prefix(windowLen)), 1, &headRMS, vDSP_Length(windowLen))
        guard headRMS > 0.0001 else { return }
        let gain = min(max(tailRMS / headRMS, 0.5), 2.0) // clamp to avoid extreme correction
        var g = gain
        vDSP_vsmul(head, 1, &g, &head, 1, vDSP_Length(head.count))
    }
    
    private func timeStretch(_ samples: [Float], rate: Float, sampleRate: Double) throws -> [Float] {
        guard rate != 1, !samples.isEmpty else { return samples }

        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                   sampleRate: sampleRate, channels: 1, interleaved: false)!
        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        let timePitch = AVAudioUnitTimePitch()
        timePitch.rate = rate                       // 1.0...32.0; e.g. 1.25 = 25% faster, pitch preserved

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
