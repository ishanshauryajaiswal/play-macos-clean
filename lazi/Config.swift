import Foundation

/// Configuration management for the app
struct Config {
    /// OpenAI API Key - Should be set in environment or configuration
    static let openAIAPIKey: String = {
        // Try to get from environment variable first
        if let envKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"] {
            return envKey
        }
        
        // For development, you can temporarily set your key here
        // IMPORTANT: Never commit your actual API key to version control
        return "YOUR_OPENAI_API_KEY_HERE"
    }()
    
    /// Validates that the API key is properly configured
    static func validateAPIKey() -> Bool {
        return !openAIAPIKey.isEmpty && openAIAPIKey != "YOUR_OPENAI_API_KEY_HERE"
    }
} 