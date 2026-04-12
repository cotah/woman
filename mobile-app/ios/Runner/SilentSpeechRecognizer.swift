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
/// 3. When a recognition session times out, we create a new request
///    but the audio engine keeps running uninterrupted
/// 4. Results are sent to Flutter via a callback
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

    /// Callback when speech is recognized. Sends the recognized text.
    var onResult: ((String, Bool) -> Void)?

    /// Callback when an error occurs.
    var onError: ((String) -> Void)?

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
    private func startAudioEngine() throws {
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        // Install a tap to capture audio buffers
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) {
            [weak self] buffer, _ in
            // Feed audio buffer to the speech recognition request
            self?.recognitionRequest?.append(buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()
        NSLog("[SilentSpeech] Audio engine started")
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
                    self.onResult?(text, isFinal)
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
