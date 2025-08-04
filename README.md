# Lazi - Audio Transcription App

A macOS app for recording audio and transcribing it using OpenAI's Whisper API, with optional LLM prompt generation.

## Features

- 🎙️ Audio recording on macOS
- 🔤 Transcription using OpenAI Whisper API
- 🧠 Optional LLM prompt generation using OpenAI GPT
- 💾 Core Data persistence
- 🔐 User authentication (planned: Supabase)

## Requirements

- macOS 13.0+ (Ventura)
- Xcode 14.0+
- Swift 5.7+
- OpenAI API key

## Setup

1. **Clone the repository:**
   ```bash
   git clone https://github.com/ishanshauryajaiswal/play-macos-clean.git
   cd play-macos-clean
   ```

2. **Open in Xcode:**
   ```bash
   open lazi.xcodeproj
   ```

3. **Configure API Keys:**
   - Set your OpenAI API key as an environment variable:
     ```bash
     export OPENAI_API_KEY="your-openai-api-key-here"
     ```
   - Alternatively, temporarily edit `Config.swift` and replace `YOUR_OPENAI_API_KEY_HERE` with your key (don't commit this change)

4. **Build and Run:**
   - Select your target device/simulator
   - Press `Cmd+R` to build and run

## Project Structure

- `lazi/` - Main app source code
  - `laziApp.swift` - App entry point
  - `ContentPanel.swift` - Main UI panel
  - `AudioRecorder.swift` - Audio recording functionality
  - `WhisperTranscriber.swift` - OpenAI Whisper integration
  - `OpenAIChatService.swift` - OpenAI API service
  - `Config.swift` - Configuration management (API keys)
  - `PersistenceController.swift` - Core Data setup
  - `Item+CoreData.swift` - Core Data model

## Architecture

See `TRD.md` for detailed technical requirements and architecture overview.

## Development Status

This is a work-in-progress project. Current branch: `record-transcribe-DB-working-3`

## License

MIT License 