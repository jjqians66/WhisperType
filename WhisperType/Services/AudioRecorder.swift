import Foundation
import AVFoundation
import Accelerate
import Combine

/// Records audio from the microphone using AVAudioEngine,
/// producing 24kHz mono PCM16 data suitable for OpenAI Realtime API.
class AudioRecorder: ObservableObject {
    private var audioEngine: AVAudioEngine?
    private var isRecording = false

    @Published var currentLevel: Float = 0.0
    @Published var frequencyBands: [Float] = Array(repeating: 0, count: 7)

    /// Called for each audio chunk during recording (PCM16 Data).
    var onAudioChunk: ((Data) -> Void)?

    // MARK: - Recording

    /// Start recording from the default microphone.
    /// Audio is delivered as PCM16 24kHz mono via `onAudioChunk`.
    func startRecording() throws {
        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        // Target: 24kHz, mono, Int16 (what OpenAI Realtime API expects)
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 24000,
            channels: 1,
            interleaved: true
        ) else {
            throw RecorderError.formatError
        }

        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            throw RecorderError.converterError
        }

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            guard let self else { return }

            // Update audio level for UI
            self.updateLevel(buffer: buffer)
            self.updateFrequencyBands(buffer: buffer)

            // Convert to 24kHz PCM16
            let frameCount = AVAudioFrameCount(
                Double(buffer.frameLength) * targetFormat.sampleRate / inputFormat.sampleRate
            )
            guard let converted = AVAudioPCMBuffer(
                pcmFormat: targetFormat,
                frameCapacity: frameCount
            ) else { return }

            var error: NSError?
            let status = converter.convert(to: converted, error: &error) { _, outStatus in
                outStatus.pointee = .haveData
                return buffer
            }

            guard status != .error, error == nil else { return }

            // Extract Int16 bytes
            if let int16Data = converted.int16ChannelData {
                let byteCount = Int(converted.frameLength) * MemoryLayout<Int16>.size
                let data = Data(bytes: int16Data[0], count: byteCount)
                self.onAudioChunk?(data)
            }
        }

        engine.prepare()
        try engine.start()
        self.audioEngine = engine
        isRecording = true
    }

    /// Stop recording.
    func stopRecording() {
        guard isRecording, let engine = audioEngine else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        self.audioEngine = nil
        isRecording = false

        DispatchQueue.main.async {
            self.currentLevel = 0.0
            self.frequencyBands = Array(repeating: 0, count: 7)
        }
    }

    // MARK: - Audio Level (RMS)

    private func updateLevel(buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData else { return }
        let frames = Int(buffer.frameLength)
        let channel = channelData[0]

        var sum: Float = 0
        for i in 0..<frames {
            sum += channel[i] * channel[i]
        }
        let rms = sqrt(sum / Float(frames))
        let db = 20 * log10(max(rms, 0.000001))
        let normalized = max(0, min(1, (db + 60) / 60))

        DispatchQueue.main.async {
            self.currentLevel = normalized
        }
    }

    // MARK: - Frequency Bands (FFT for waveform visualization)

    private func updateFrequencyBands(buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData else { return }
        let frames = Int(buffer.frameLength)
        guard frames >= 512 else { return }

        // Use 512-sample FFT window
        let fftSize = 512
        let log2n = vDSP_Length(log2(Float(fftSize)))
        guard let fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else { return }
        defer { vDSP_destroy_fftsetup(fftSetup) }

        var realp = [Float](repeating: 0, count: fftSize / 2)
        var imagp = [Float](repeating: 0, count: fftSize / 2)

        // Copy input and apply window
        var windowed = [Float](repeating: 0, count: fftSize)
        var window = [Float](repeating: 0, count: fftSize)
        vDSP_hann_window(&window, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))
        vDSP_vmul(channelData[0], 1, window, 1, &windowed, 1, vDSP_Length(fftSize))

        // Pack into split complex
        windowed.withUnsafeBufferPointer { ptr in
            ptr.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: fftSize / 2) { complexPtr in
                var splitComplex = DSPSplitComplex(realp: &realp, imagp: &imagp)
                vDSP_ctoz(complexPtr, 2, &splitComplex, 1, vDSP_Length(fftSize / 2))
            }
        }

        // Forward FFT
        var splitComplex = DSPSplitComplex(realp: &realp, imagp: &imagp)
        vDSP_fft_zrip(fftSetup, &splitComplex, 1, log2n, FFTDirection(kFFTDirection_Forward))

        // Calculate magnitudes
        var magnitudes = [Float](repeating: 0, count: fftSize / 2)
        vDSP_zvmags(&splitComplex, 1, &magnitudes, 1, vDSP_Length(fftSize / 2))

        // Group into 7 frequency bands
        let bandCount = 7
        let binsPerBand = (fftSize / 2) / bandCount
        var bands = [Float](repeating: 0, count: bandCount)

        for band in 0..<bandCount {
            let start = band * binsPerBand
            let end = min(start + binsPerBand, fftSize / 2)
            var sum: Float = 0
            for i in start..<end {
                sum += magnitudes[i]
            }
            let avg = sum / Float(end - start)
            let db = 10 * log10(max(avg, 0.000001))
            bands[band] = max(0, min(1, (db + 40) / 40))
        }

        DispatchQueue.main.async {
            self.frequencyBands = bands
        }
    }
}

// MARK: - Errors

enum RecorderError: LocalizedError {
    case formatError
    case converterError
    case notRecording

    var errorDescription: String? {
        switch self {
        case .formatError: return "Could not create audio format"
        case .converterError: return "Could not create audio converter"
        case .notRecording: return "Not currently recording"
        }
    }
}
