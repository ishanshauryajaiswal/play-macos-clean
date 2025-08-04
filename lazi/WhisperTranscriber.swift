import Foundation
import Combine

/// Handles transcription of audio files using OpenAI's Whisper API.
/// Usage: create an instance, then call `transcribe(fileURL:completion:)`.
final class WhisperTranscriber: NSObject, ObservableObject {
    // MARK: - Public published progress (0…1)
    @Published var progress: Double = 0.0

    // MARK: - Private
    private let boundary = UUID().uuidString
    private var completion: ((Result<String, Error>) -> Void)?

    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.default
        return URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }()

    private let apiKey = Config.openAIAPIKey

    // MARK: - Transcription
    func transcribe(fileURL: URL, completion: @escaping (Result<String, Error>) -> Void) {
        self.completion = completion
        progress = 0

        let fileSize = (try? Data(contentsOf: fileURL).count) ?? 0
        NSLog("[WHISPER] Preparing transcription for file: \(fileURL.lastPathComponent) – size: \(fileSize) bytes")

        let request = makeRequest(fileName: fileURL.lastPathComponent)
        NSLog("[WHISPER] Request headers: \(request.allHTTPHeaderFields ?? [:])")
        guard let body = makeBody(fileURL: fileURL) else {
            completion(.failure(NSError(domain: "Whisper", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create multipart body"])))
            return
        }

        NSLog("[WHISPER] Uploading multipart body (\(body.count) bytes)…")
        let task = session.uploadTask(with: request, from: body)
        task.resume()
    }

    private func makeRequest(fileName: String) -> URLRequest {
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/audio/transcriptions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        return request
    }

    private func makeBody(fileURL: URL) -> Data? {
        guard let audioData = try? Data(contentsOf: fileURL) else { return nil }

        var body = Data()
        let newLine = "\r\n".data(using: .utf8)!
        func append(_ string: String) { body.append(string.data(using: .utf8)!) }

        // Helper to add simple text field
        func addField(name: String, value: String) {
            append("--\(boundary)\r\n")
            append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
            append("\(value)\r\n")
        }

        // model
        addField(name: "model", value: "whisper-1")

        // language – restrict to English so the model doesn't attempt multi-lingual detection.
        addField(name: "language", value: "en")

        // temperature 0 for deterministic output and possibly better accuracy.
        addField(name: "temperature", value: "0")

        // file
        let mime: String = {
            switch fileURL.pathExtension.lowercased() {
            case "m4a": return "audio/m4a"
            case "mp3": return "audio/mpeg"
            default:     return "audio/wav"
            }
        }()

        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileURL.lastPathComponent)\"\r\n")
        append("Content-Type: \(mime)\r\n\r\n")
        body.append(audioData)
        body.append(newLine)

        append("--\(boundary)--\r\n")
        return body
    }
}

// MARK: - URLSessionTaskDelegate
extension WhisperTranscriber: URLSessionTaskDelegate, URLSessionDataDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64,
                    totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        guard totalBytesExpectedToSend > 0 else { return }
        DispatchQueue.main.async {
            self.progress = Double(totalBytesSent) / Double(totalBytesExpectedToSend)
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        // Handle the response once fully received.
        parseResponseData(data)
    }

    private func parseResponseData(_ data: Data) {
        NSLog("[WHISPER] Raw response: \(String(data: data, encoding: .utf8) ?? "<binary>")")

        do {
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let text = json["text"] as? String {
                completion?(.success(text))
            } else {
                let error = NSError(domain: "Whisper", code: -2, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
                completion?(.failure(error))
            }
        } catch {
            completion?(.failure(error))
        }
    }
} 