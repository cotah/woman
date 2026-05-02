import Foundation
import Speech
import AVFoundation

/// Silent continuous speech recognizer for SafeCircle.
///
/// Unlike the speech_to_text Flutter package which starts/stops the audio
/// session (causing iOS to play a "ding" sound each time), this implementation
/// keeps the AVAudioEngine running continuously. The speech recognizer is
/// reset periodically without stopping the audio engine, so there's NO sound.
///
/// Architecture:
/// 1. AVAudioEngine runs permanently (no start/stop = no sound)
/// 2. SFSpeechRecognizer processes audio buffers in real-time
/// 3. Each buffer is ALSO resampled to 16 kHz mono Float32 and appended to
///    a 3-second ring buffer for voiceprint verification (Phase 4)
/// 4. When a recognition session times out, we create a new request but
///    the audio engine keeps running uninterrupted
/// 5. On a final speech result, the ring buffer is snapshotted into
///    little-endian Int16 PCM and sent to Flutter alongside the text via
///    the onResult callback. Flutter then runs voiceprint verification
///    before triggering the alert.
class SilentSpeechRecognizer: NSObject {

    // MARK: - Properties

    private let speechRecognizer: SFSpeechRecognizer?
    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    /// How long each recognition session lasts before resetting (seconds).
    /// Apple limits sessions to ~60s, so we reset at 55s to stay safe.
    private let sessionDurationSeconds: TimeInterval = 55

    /// Timer to reset the recognition session periodically.
    private var sessionTimer: Timer?

    /// Whether the engine is currently running.
    private(set) var isRunning = false

    /// Callback fired on each speech recognition update. Carries the
    /// recognized text, whether it's the final result for the current
    /// utterance, and (only on final results) a snapshot of the recent
    /// audio in 16 kHz mono Int16 little-endian PCM bytes for voiceprint
    /// verification on the Dart side.
    var onResult: ((String, Bool, Data?) -> Void)?

    /// Callback when an error occurs.
    var onError: ((String) -> Void)?

    // MARK: - Voiceprint ring buffer

    /// Target format for voiceprint inference: 16 kHz, mono, Float32.
    /// Matches what the bundled TFLite Wespeaker model expects after
    /// the Dart-side mel-spectrogram pipeline.
    private let voiceprintSampleRate: Double = 16000
    private static let ringBufferCapacity = 48000 // 3 s @ 16 kHz

    /// Ring buffer of recently captured audio (Float32, 16 kHz mono).
    /// Always points to a fixed-size allocation; writes wrap circularly.
    private var ringBuffer = [Float](repeating: 0, count: ringBufferCapacity)
    private var ringBufferWriteIdx = 0
    /// True once the ring buffer has wrapped at least once (i.e. it
    /// contains a full 3 s of audio history).
    private var ringBufferFilled = false
    /// Guards [ringBuffer], [ringBufferWriteIdx], and [ringBufferFilled].
    /// The audio tap thread writes; the recognition callback (delivered
    /// on a different queue) reads via [snapshotRingBuffer].
    private let ringBufferLock = NSLock()

    /// Resampler from the input node's native format to [voiceprintFormat].
    /// Built lazily in [startAudioEngine] when we have the input format.
    private var audioConverter: AVAudioConverter?
    private var voiceprintFormat: AVAudioFormat?

    // MARK: - Init

    override init() {
        // Use device locale for speech recognition
        self.speechRecognizer = SFSpeechRecognizer(locale: Locale.current)
        super.init()
    }

    // MARK: - Public API

    /// Start continuous silent listening.
    /// Returns true if started successfully, false if permissions/setup failed.
    func start() -> Bool {
        guard !isRunning else { return true }

        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            onError?("Speech recognizer not available")
            return false
        }

        // Check authorization
        let authStatus = SFSpeechRecognizer.authorizationStatus()
        guard authStatus == .authorized else {
            onError?("Speech recognition not authorized (status: \(authStatus.rawValue))")
            return false
        }

        do {
            try configureAudioSession()
            try startAudioEngine()
            startRecognitionSession()
            isRunning = true
            NSLog("[SilentSpeech] Started continuous silent listening")
            return true
        } catch {
            onError?("Failed to start: \(error.localizedDescription)")
            NSLog("[SilentSpeech] Start failed: \(error)")
            return false
        }
    }

    /// Stop listening and release all resources.
    func stop() {
        sessionTimer?.invalidate()
        sessionTimer = nil

        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil

        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }

        // Reset ring buffer state for the next start.
        ringBufferLock.lock()
        ringBufferWriteIdx = 0
        ringBufferFilled = false
        ringBufferLock.unlock()

        audioConverter = nil
        voiceprintFormat = nil

        isRunning = false
        NSLog("[SilentSpeech] Stopped")
    }

    /// Request speech recognition permission.
    static func requestAuthorization(completion: @escaping (Bool) -> Void) {
        SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async {
                completion(status == .authorized)
            }
        }
    }

    // MARK: - Audio Session

    /// Configure AVAudioSession for silent background recording.
    /// Uses .measurement mode which suppresses system sounds.
    private func configureAudioSession() throws {
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(
            .playAndRecord,
            mode: .measurement,
            options: [.duckOthers, .defaultToSpeaker, .allowBluetooth, .mixWithOthers]
        )
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        NSLog("[SilentSpeech] Audio session configured (measurement mode, silent)")
    }

    // MARK: - Audio Engine

    /// Start the AVAudioEngine and install a tap to capture audio buffers.
    /// The tap feeds two consumers per buffer:
    ///   1. The Apple speech recognizer (existing behavior).
    ///   2. A 16 kHz mono Float32 ring buffer used for voiceprint snapshots.
    private func startAudioEngine() throws {
        let inputNode = audioEngine.inputNode
        let nativeFormat = inputNode.outputFormat(forBus: 0)

        // Build the resampler once. The native format on iOS varies by
        // device (typically Float32, mono or stereo, 44.1 kHz or 48 kHz);
        // AVAudioConverter handles downmix + sample rate change.
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: voiceprintSampleRate,
            channels: 1,
            interleaved: false
        ) else {
            throw NSError(
                domain: "SilentSpeech", code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Failed to build target voiceprint format"]
            )
        }
        self.voiceprintFormat = targetFormat
        self.audioConverter = AVAudioConverter(from: nativeFormat, to: targetFormat)
        if self.audioConverter == nil {
            NSLog("[SilentSpeech] WARNING: failed to build AVAudioConverter from \(nativeFormat) to \(targetFormat) — voiceprint disabled")
        }

        // Install a tap to capture audio buffers
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: nativeFormat) {
            [weak self] buffer, _ in
            guard let self = self else { return }

            // 1. Feed audio buffer to the speech recognition request
            self.recognitionRequest?.append(buffer)

            // 2. Resample to 16 kHz mono Float32 and append to ring buffer
            //    for voiceprint verification on isFinal results.
            if let resampled = self.resampleForVoiceprint(buffer) {
                self.appendToRingBuffer(resampled)
            }
        }

        audioEngine.prepare()
        try audioEngine.start()
        NSLog("[SilentSpeech] Audio engine started (native: \(nativeFormat))")
    }

    // MARK: - Voiceprint resampling + ring buffer

    /// Resample a native input buffer to 16 kHz mono Float32. Returns nil
    /// on converter error or if the converter wasn't initialized — the
    /// ring buffer simply skips that chunk in those cases (silent
    /// degradation rather than crash).
    private func resampleForVoiceprint(_ inputBuffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let converter = self.audioConverter,
              let target = self.voiceprintFormat,
              inputBuffer.frameLength > 0 else {
            return nil
        }

        // Output capacity must accommodate the worst case (input length *
        // sample rate ratio + small safety margin).
        let ratio = target.sampleRate / inputBuffer.format.sampleRate
        let outputCapacity = AVAudioFrameCount(
            ceil(Double(inputBuffer.frameLength) * ratio) + 16
        )
        guard let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: target, frameCapacity: outputCapacity
        ) else { return nil }

        // AVAudioConverter pulls input via a callback. We provide the buffer
        // exactly once and then signal end-of-stream so it doesn't loop.
        var didProvide = false
        let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
            if didProvide {
                outStatus.pointee = .noDataNow
                return nil
            }
            didProvide = true
            outStatus.pointee = .haveData
            return inputBuffer
        }

        var error: NSError?
        let status = converter.convert(to: outputBuffer, error: &error, withInputFrom: inputBlock)
        if let error = error {
            NSLog("[SilentSpeech] Resample error: \(error.localizedDescription)")
            return nil
        }
        if status == .error || outputBuffer.frameLength == 0 {
            return nil
        }
        return outputBuffer
    }

    /// Append samples from a Float32 mono buffer into the ring buffer,
    /// wrapping at the end. Thread-safe via [ringBufferLock].
    private func appendToRingBuffer(_ pcm: AVAudioPCMBuffer) {
        guard let channelData = pcm.floatChannelData?[0] else { return }
        let count = Int(pcm.frameLength)
        if count <= 0 { return }

        ringBufferLock.lock()
        defer { ringBufferLock.unlock() }

        var srcIdx = 0
        while srcIdx < count {
            let chunk = min(count - srcIdx, Self.ringBufferCapacity - ringBufferWriteIdx)
            for i in 0..<chunk {
                ringBuffer[ringBufferWriteIdx + i] = channelData[srcIdx + i]
            }
            ringBufferWriteIdx += chunk
            srcIdx += chunk
            if ringBufferWriteIdx >= Self.ringBufferCapacity {
                ringBufferWriteIdx = 0
                ringBufferFilled = true
            }
        }
    }

    /// Snapshot the ring buffer as little-endian Int16 PCM bytes, ordered
    /// oldest → newest. Returns nil if there's less than 1 s of audio
    /// available (the voiceprint pipeline rejects shorter clips anyway).
    /// Thread-safe via [ringBufferLock].
    private func snapshotRingBuffer() -> Data? {
        ringBufferLock.lock()
        defer { ringBufferLock.unlock() }

        let availableSamples = ringBufferFilled
            ? Self.ringBufferCapacity
            : ringBufferWriteIdx
        if availableSamples < 16000 {
            // < 1 s of audio captured so far — not enough for a stable
            // embedding. Caller will skip the trigger.
            return nil
        }

        // Read oldest → newest. If wrapped, oldest sample is at the
        // current write index; if not wrapped, it's at index 0.
        let oldestIdx = ringBufferFilled ? ringBufferWriteIdx : 0

        var bytes = Data(count: availableSamples * 2)
        bytes.withUnsafeMutableBytes { (raw: UnsafeMutableRawBufferPointer) in
            guard let dest = raw.baseAddress else { return }
            let int16Dest = dest.assumingMemoryBound(to: Int16.self)
            for i in 0..<availableSamples {
                let srcIdx = (oldestIdx + i) % Self.ringBufferCapacity
                let f = max(-1.0, min(1.0, ringBuffer[srcIdx]))
                int16Dest[i] = Int16(f * 32767.0)
            }
        }
        return bytes
    }

    // MARK: - Speech Recognition Session

    /// Start a new speech recognition session.
    /// The audio engine keeps running — only the recognizer is reset.
    private func startRecognitionSession() {
        // Cancel previous task if any
        recognitionTask?.cancel()
        recognitionTask = nil

        // Create a new recognition request
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()

        guard let request = recognitionRequest,
              let recognizer = speechRecognizer else {
            return
        }

        // Configure for real-time results
        request.shouldReportPartialResults = true

        // Force on-device recognition if available (faster, more private, no network sounds)
        if #available(iOS 13.0, *) {
            request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
        }

        // Start recognition task
        recognitionTask = recognizer.recognitionTask(with: request) {
            [weak self] result, error in
            guard let self = self else { return }

            if let result = result {
                let text = result.bestTranscription.formattedString
                let isFinal = result.isFinal

                if !text.isEmpty {
                    // Snapshot the ring buffer ONLY on final results — interim
                    // results would have partial audio and we don't want to
                    // pay the conversion cost on every keystroke.
                    let audioSnapshot: Data? = isFinal
                        ? self.snapshotRingBuffer()
                        : nil
                    self.onResult?(text, isFinal, audioSnapshot)
                }

                if isFinal {
                    // Session ended naturally — restart silently
                    self.restartRecognitionSession()
                }
            }

            if let error = error {
                let nsError = error as NSError

                // Error code 1 = recognition cancelled (normal during reset)
                // Error code 216 = request rate limited (too many requests)
                // Don't log these as errors
                if nsError.code != 1 && nsError.code != 216 {
                    NSLog("[SilentSpeech] Recognition error: \(error.localizedDescription)")
                    self.onError?(error.localizedDescription)
                }

                // Restart if still running
                if self.isRunning {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        if self.isRunning {
                            self.restartRecognitionSession()
                        }
                    }
                }
            }
        }

        // Schedule session reset (Apple limits sessions to ~60s)
        sessionTimer?.invalidate()
        sessionTimer = Timer.scheduledTimer(
            withTimeInterval: sessionDurationSeconds,
            repeats: false
        ) { [weak self] _ in
            self?.restartRecognitionSession()
        }

        NSLog("[SilentSpeech] Recognition session started (resets in \(Int(sessionDurationSeconds))s)")
    }

    /// Restart the recognition session WITHOUT stopping the audio engine.
    /// This is the key to silent operation — no engine stop = no sound.
    private func restartRecognitionSession() {
        // End the current request (tells the recognizer we're done with this batch)
        recognitionRequest?.endAudio()
        recognitionRequest = nil

        recognitionTask?.cancel()
        recognitionTask = nil

        // Small delay before starting new session
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self = self, self.isRunning else { return }
            self.startRecognitionSession()
        }
    }
}
