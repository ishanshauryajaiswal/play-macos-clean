import Foundation

/// Lightweight client for OpenAI Chat Completion used to decide if a new utterance references prior ones.
struct OpenAIChatService {
    private let apiKey = Config.openAIAPIKey
    private let endpoint = URL(string: "https://api.openai.com/v1/chat/completions")!

    /// Sends the prompt and returns true/false wrapped in Result.
    func askUsesPrevious(newText: String, history: [String], completion: @escaping (Result<Bool, Error>) -> Void) {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 20

        let prompt = "Here is the user's most recent transcription: '\(newText)'\nPrevious transcriptions: \(history)\nIs the user asking to fetch information from any of the previous transcriptions? Please answer with 'true' or 'false'."

        let body: [String: Any] = [
            "model": "gpt-3.5-turbo",
            "messages": [
                ["role": "system", "content": "You are an assistant that helps determine if a user is asking for previously mentioned information."],
                ["role": "user", "content": prompt]
            ],
            "temperature": 0.0,
            "max_tokens": 50,
            "top_p": 1.0,
            "frequency_penalty": 0.0,
            "presence_penalty": 0.0
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
        } catch {
            completion(.failure(error))
            return
        }

        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            guard let data = data else {
                completion(.failure(NSError(domain: "CHAT", code: -1, userInfo: [NSLocalizedDescriptionKey: "Empty response"])) )
                return
            }
            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let choices = json["choices"] as? [[String: Any]],
                   let message = choices.first?["message"] as? [String: Any],
                   let content = message["content"] as? String {
                    let result = content.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
                    completion(.success(result.contains("true")))
                } else {
                    completion(.failure(NSError(domain: "CHAT", code: -2, userInfo: [NSLocalizedDescriptionKey: "Invalid JSON structure"])) )
                }
            } catch {
                completion(.failure(error))
            }
        }
        task.resume()
    }
} 