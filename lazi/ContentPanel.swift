import AppKit
import SwiftUI

/// Floating, borderless panel that stays above all Spaces and full-screen apps.
class ContentPanel: NSPanel {
    private let padding: CGFloat = 20

    init() {
        super.init(contentRect: .zero,
                   styleMask: [.titled, .nonactivatingPanel],
                   backing: .buffered,
                   defer: true)
        setupWindow()
        setupContentView()
    }

    // MARK: – Window & Content Setup
    private func setupWindow() {
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        level = .floating
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = true
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
    }

    private func setupContentView() {
        let hostingView = NSHostingView(rootView: ContentPanelView())
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        contentView = hostingView

        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: contentView!.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: contentView!.trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: contentView!.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: contentView!.bottomAnchor)
        ])

        layoutIfNeeded()
        let size = hostingView.fittingSize
        setContentSize(size)

        if let screen = NSScreen.main?.visibleFrame {
            let x = screen.maxX - size.width - padding
            let y = screen.minY + padding
            setFrameOrigin(NSPoint(x: x, y: y))
        }
    }
}

// MARK: – SwiftUI body displayed in the panel
private struct ContentPanelView: View {
    @StateObject private var recorder = AudioRecorder()
    @StateObject private var transcriber = WhisperTranscriber()

    // Unified UI state
    private enum PanelState {
        case idle
        case recording
        case transcribing
        case success(String)   // transcribed text
        case failure(String)   // error message
    }

    private enum ContextState {
        case none
        case checking
        case result(Bool)
        case error(String)
    }

    @State private var state: PanelState = .idle
    @State private var showCopiedToast = false // simple feedback when user copies
    @State private var contextState: ContextState = .none

    var body: some View {
        VStack(spacing: 16) {
            switch state {
            case .idle:
                Text("Idle").font(.headline)
            case .recording:
                Text("Recording…").font(.headline)
            case .transcribing:
                ProgressView(value: transcriber.progress)
                    .progressViewStyle(LinearProgressViewStyle())
                Text("Transcribing… \(Int(transcriber.progress * 100))%")
                    .font(.headline)
            case .success(let text):
                ScrollView {
                    Text(text)
                        .font(.body)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                HStack {
                    Button("Copy") { copyToClipboard(text) }
                        .keyboardShortcut("c")
                    Spacer()
                    contextButton(text: text)
                }
            case .failure(let message):
                Text("Error: \(message)")
                    .foregroundColor(.red)
            }

            // Record / Stop button (always visible at bottom)
            Button(action: toggle) {
                Text(buttonLabel)
                    .bold()
            }
            .keyboardShortcut("r")
            .disabled(isBusy)
        }
        .padding()
        .frame(width: 260, height: 160)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.95))
                .shadow(radius: 6)
        )
        .foregroundColor(.black)
        // React to a finished recording
        .onChange(of: recorder.lastRecordingURL) { url in
            guard let url else { return }
            transcribe(at: url)
        }
        .onChange(of: transcriber.progress) { _ in
            // Keep UI updating while transcribing
        }
    }

    /// Starts or stops recording.
    private func toggle() {
        switch state {
        case .recording:
            NSLog("[UI] Stop recording tapped")
            recorder.stop()
        case .idle, .success, .failure:
            NSLog("[UI] Start recording tapped")
            do {
                _ = try recorder.start()
                state = .recording
            } catch {
                NSLog("[UI] Failed to start recording: \(error.localizedDescription)")
                state = .failure(error.localizedDescription)
            }
        default:
            break // .transcribing – button disabled
        }
    }

    /// Kicks off transcription for the given audio file.
    private func transcribe(at url: URL) {
        state = .transcribing

        transcriber.transcribe(fileURL: url) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let text):
                    state = .success(text)
                    PersistenceController.shared.save(transcript: text)
                    contextState = .none
                case .failure(let error):
                    state = .failure(error.localizedDescription)
                    contextState = .none
                }
            }
        }
    }

    // Helper – copy to pasteboard
    private func copyToClipboard(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
        NSLog("[UI] Transcription copied to clipboard")
    }

    // MARK: – Convenience helpers
    private var isBusy: Bool {
        if case .transcribing = state { return true }
        return false
    }

    private var buttonLabel: String {
        switch state {
        case .recording: return "Stop"
        default:        return "Record"
        }
    }

    // Provides the Check Context button / status view
    @ViewBuilder
    private func contextButton(text: String) -> some View {
        switch contextState {
        case .none:
            Button("Check Context") { startContextCheck(newText: text) }
        case .checking:
            ProgressView()
        case .result(let val):
            Text(val ? "✅ Refers" : "❌ None")
        case .error(let msg):
            Text("Error").foregroundColor(.red).help(msg)
        }
    }

    private func startContextCheck(newText: String) {
        contextState = .checking
        let history = PersistenceController.shared.fetchLatest(limit: 20)
        OpenAIChatService().askUsesPrevious(newText: newText, history: history) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let flag):
                    contextState = .result(flag)
                case .failure(let error):
                    contextState = .error(error.localizedDescription)
                }
            }
        }
    }
}