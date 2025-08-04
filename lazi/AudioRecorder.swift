import AVFoundation
import Combine

/// High-level microphone recorder tailored for speech-to-text back-ends (e.g. OpenAI Whisper).
/// • Records linear PCM 16-kHz WAV for maximum accuracy.
/// • Simple `start()` / `stop()` API & publishes `isRecording` state.
final class AudioRecorder: ObservableObject {
    /// Cached global flag so we don't re-query or re-prompt for microphone access every
    /// time a new `AudioRecorder` instance is created (e.g. every time the panel is shown).
    private static var globalMicAuthorized: Bool {
        get {
            AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        }
    }

    @Published private(set) var isRecording = false
    // Publishes the URL of the most recently completed recording so that the UI can trigger transcription.
    @Published private(set) var lastRecordingURL: URL?
    private let engine = AVAudioEngine()
    private var file: AVAudioFile?
    private let recordingQueue = DispatchQueue(label: "audio.record.queue")
    private var permissionChecked = false
    private var currentFileURL: URL?

    /// Starts a new recording session. Subsequent calls while recording are ignored.
    /// - Returns: The URL where audio will be written.
    @discardableResult
    func start(compressed: Bool = false) throws -> URL {
        NSLog("[LAZI_RECORDER] Starting recording session")
        
        guard !isRecording else { 
            NSLog("[LAZI_RECORDER] Already recording, returning current URL")
            return currentFileURL! 
        }

        do {
            // Ensure microphone permission
            try awaitMicPermission()
            NSLog("[LAZI_RECORDER] Microphone permission granted")

            // Create directory ~/Library/Application Support/<bundle>/Recordings
            let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
                .first!
                .appendingPathComponent(Bundle.main.bundleIdentifier ?? "lazi", isDirectory: true)
                .appendingPathComponent("Recordings", isDirectory: true)
            
            NSLog("[LAZI_RECORDER] Creating directory: \(directory.path)")
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                NSLog("[LAZI_RECORDER] Directory created successfully")
                
                // Verify directory exists
                var isDirectory: ObjCBool = false
                if FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory) && isDirectory.boolValue {
                    NSLog("[LAZI_RECORDER] Directory verified: \(directory.path)")
                } else {
                    NSLog("[LAZI_RECORDER] Directory verification failed: \(directory.path)")
                }
            } catch {
                NSLog("[LAZI_RECORDER] Directory creation failed: \(error.localizedDescription)")
                throw error
            }
            
            let timestamp = Int(Date().timeIntervalSince1970)
            let url = directory.appendingPathComponent("rec_\(timestamp)." + (compressed ? "m4a" : "wav"))
            currentFileURL = url
            NSLog("[LAZI_RECORDER] Recording to file: \(url.path)")

            // MARK: - Audio Session setup (iOS/tvOS only)
            #if os(iOS) || os(tvOS)
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
            try session.setActive(true)
            NSLog("[LAZI_RECORDER] AVAudioSession configured")
            #endif

            // Grab the hardware format directly from the microphone
            let inputNode = engine.inputNode
            let inputFormat = inputNode.outputFormat(forBus: 0)
            NSLog("[LAZI_RECORDER] Input format: \(inputFormat)")

            // We'll always tap using the microphone's native format.
            let tapFormat = inputFormat
            
            // Prepare destination file settings
            if compressed {
                // AAC (M4A) – much smaller than uncompressed WAV.
                let aacSettings: [String: Any] = [
                    AVFormatIDKey: kAudioFormatMPEG4AAC,
                    AVSampleRateKey: inputFormat.sampleRate,
                    AVNumberOfChannelsKey: inputFormat.channelCount,
                    AVEncoderBitRateKey: 64000
                ]
                NSLog("[LAZI_RECORDER] Creating compressed AAC file with settings: \(aacSettings)")
                file = try AVAudioFile(forWriting: url, settings: aacSettings)
            } else {
                // Uncompressed WAV (native Float32)
                let fileFormat = inputFormat
                NSLog("[LAZI_RECORDER] File format (native Float32): \(fileFormat)")
                file = try AVAudioFile(forWriting: url, settings: fileFormat.settings)
            }
            NSLog("[LAZI_RECORDER] AVAudioFile created")

            // Reset & prepare engine if it was previously running
            engine.stop()
            engine.reset()

            // Install tap directly on the input node so we avoid the mixer entirely.
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: tapFormat) { [weak self] buffer, _ in
                guard let self, let file = self.file else { return }
                self.recordingQueue.async {
                    do {
                        try file.write(from: buffer)
                    } catch {
                        NSLog("[LAZI_RECORDER] Write error: \(error.localizedDescription)")
                    }
                }
            }
            NSLog("[LAZI_RECORDER] Tap installed on input node")

            try engine.start()
            NSLog("[LAZI_RECORDER] Audio engine started")

            DispatchQueue.main.async {
                self.isRecording = true
                NSLog("[LAZI_RECORDER] Recording state updated to true")
            }

            return url
            
        } catch {
            NSLog("[LAZI_RECORDER] Start failed: \(error.localizedDescription)")
            throw error
        }
    }

    /// Stops recording and returns the final file URL.
    func stop() {
        NSLog("[LAZI_RECORDER] Stopping recording")
        
        guard isRecording else { 
            NSLog("[LAZI_RECORDER] Not currently recording")
            return 
        }
        
        do {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
            
            // Close file properly
            if let file = file {
                NSLog("[LAZI_RECORDER] Closing file: \(file.url.path)")
                NSLog("[LAZI_RECORDER] Final file length: \(file.length) frames")
            }
            file = nil
            
            NSLog("[LAZI_RECORDER] Recording stopped successfully")
            
            DispatchQueue.main.async { 
                self.isRecording = false
                NSLog("[LAZI_RECORDER] Recording state updated to false")
            }
            
            // Verify file exists
            if let url = currentFileURL {
                let fileManager = FileManager.default
                if fileManager.fileExists(atPath: url.path) {
                    do {
                        let attributes = try fileManager.attributesOfItem(atPath: url.path)
                        let fileSize = attributes[.size] as? Int64 ?? 0
                        NSLog("[LAZI_RECORDER] File saved successfully: \(url.path), size: \(fileSize) bytes")
                        // Publish the completed recording URL so that downstream components can react.
                        DispatchQueue.main.async {
                            self.lastRecordingURL = url
                        }
                    } catch {
                        NSLog("[LAZI_RECORDER] Failed to get file attributes: \(error.localizedDescription)")
                    }
                } else {
                    NSLog("[LAZI_RECORDER] ERROR: File does not exist at expected path: \(url.path)")
                }
            }
            
        } catch {
            NSLog("[LAZI_RECORDER] Stop error: \(error.localizedDescription)")
        }
    }

    // MARK: - Permission
    private func awaitMicPermission() throws {
        NSLog("[LAZI_RECORDER] Checking microphone permission")
        
        guard !permissionChecked else { 
            NSLog("[LAZI_RECORDER] Permission already checked")
            return 
        }
        
        permissionChecked = true

        // Fast-path: if the app has already been granted permission in this or a previous
        // launch, skip any further checks/prompts.
        if Self.globalMicAuthorized {
            NSLog("[LAZI_RECORDER] Microphone already authorized – skipping permission prompt")
            return
        }

        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        NSLog("[LAZI_RECORDER] Current authorization status: \(status.rawValue)")

        // If permission already granted, return immediately without prompting.
        guard status == .notDetermined else {
            if status != .authorized {
                NSLog("[LAZI_RECORDER] Microphone access denied previously")
                throw NSError(domain: "LAZI_RECORDER", code: 1, userInfo: [NSLocalizedDescriptionKey: "Microphone access denied"])
            }
            return
        }

        // Request access (this will show prompt only first time).
        let sema = DispatchSemaphore(value: 0)
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            NSLog("[LAZI_RECORDER] Permission request result: \(granted)")
            sema.signal()
        }

        let result = sema.wait(timeout: .now() + 5)
        if result == .timedOut {
            NSLog("[LAZI_RECORDER] Permission request timed out")
            throw NSError(domain: "LAZI_RECORDER", code: 1, userInfo: [NSLocalizedDescriptionKey: "Microphone permission request timed out"])
        }

        let finalStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        NSLog("[LAZI_RECORDER] Authorization status after request: \(finalStatus.rawValue)")

        guard finalStatus == .authorized else {
            NSLog("[LAZI_RECORDER] Microphone access denied after prompt")
            throw NSError(domain: "LAZI_RECORDER", code: 1, userInfo: [NSLocalizedDescriptionKey: "Microphone access denied"])
        }

        // Update global cache on success
        if finalStatus == .authorized {
            NSLog("[LAZI_RECORDER] Microphone permission granted – caching for future")
        }
    }
} 