# TARA - Hybrid Offline-First AI Chat 🤖💬

![Flutter](https://img.shields.io/badge/Flutter-%2302569B.svg?style=for-the-badge&logo=Flutter&logoColor=white)
![C++](https://img.shields.io/badge/c++-%2300599C.svg?style=for-the-badge&logo=c%2B%2B&logoColor=white)
![Privacy Focused](https://img.shields.io/badge/Privacy-Focused-success?style=for-the-badge)
![Hybrid Mode](https://img.shields.io/badge/Hybrid-Online%2FOffline-blueviolet?style=for-the-badge)

**TARA** is a powerful, **Hybrid Offline-First** chat assistant built with Flutter and C++. Experience the best of both worlds: complete privacy with local LLMs (Qwen 1.8B, Qwen 2.5 0.5B) or high-performance cloud inference (Groq, Gemini) when you need it. 🚀

---

## ✨ Features

*   **🌍 Hybrid Architecture**:
    *   **Offline Mode**: 100% private, local inference using `llama.cpp`. No internet required. Supported models: **Qwen 1.8B**, **Qwen 2.5 0.5B**.
    *   **Online Mode**: Switch instantly to cloud providers like **Groq** (Llama 3, Mixtral) or **Google Gemini** for faster, more capable responses.
*   **🤖 TARA AI**: A friendly, helpful assistant powered by your choice of intelligence.
*   **🎨 Modern "ChatFlow" UI**:
    *   **Gradient Aesthetics**: Beautiful Blue-Purple gradient design.
    *   **ChatGPT-Style Navigation**: Direct launch to chat, with a Drawer for history.
    *   **Smart Loading**: Non-intrusive "Thinking..." status in the header.
    *   **Motivational Quotes**: Inspiring quotes displayed on empty chat states.
*   **⚡ High Performance**: Powered by `llama.cpp` via Dart FFI for near-native speed.
*   **🧠 Optimized Inference**:
    *   **Strict ChatML**: Prevents hallucinations and looping.
    *   **Smart Stop Tokens**: Aggressively handles model output to ensure clean replies.
    *   **Loop Detection**: Automatically detects and stops repetitive text.
*   **💾 Local History**: Conversations are saved securely using SQLite.

---



---

## 🛠️ Getting Started

### Prerequisites

*   **Flutter SDK**: [Install Flutter](https://docs.flutter.dev/get-started/install)
*   **C++ Compiler**:
    *   **Windows**: Visual Studio 2019+ with C++ Desktop Development workload.
    *   **Android**: Android NDK (managed automatically by Gradle).

### Installation

1.  **Clone the repository:**
    ```bash
    git clone https://github.com/Varun0054/Offline-Ai-Chatbot.git
    cd Offline-Ai-Chatbot
    ```

2.  **Install dependencies:**
    ```bash
    flutter pub get
    ```

3.  **Download a Model:**
    *   This app requires a **GGUF** format model.
    *   **Recommended**:
        *   [Qwen-1.8B-Finetuned-GGUF](https://huggingface.co/Qwen/Qwen1.5-1.8B-Chat-GGUF) (Recommended for quality)
        *   [Qwen2.5-0.5B-Instruct-GGUF](https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct-GGUF) (Fastest)
    *   **Important**: Create a folder named `Model` inside your `Downloads` directory:
        *   **Windows**: `C:\Users\YourName\Downloads\Model`
        *   **Android**: `/storage/emulated/0/Download/Model`
    *   Place your `.gguf` file inside this folder.

4.  **Run the App:**
    *   **Android**:
        ```bash
        flutter run
        ```
    *   **Windows**:
        ```bash
        flutter run -d windows
        ```

### 🔑 Online Mode Setup (Optional)

To use the Online Mode features:
1.  Go to **Settings** in the app.
2.  Enter your API Key for **Groq** or **Gemini**.
3.  Toggle the "Online Mode" switch in the chat screen.

---

## 📖 Usage

1.  **Launch**: App opens directly to TARA.
2.  **Menu**: Tap the top-left menu icon to access **History** and **Settings**.
3.  **Settings**: Select your downloaded model from the dropdown list.
4.  **Chat**: Start typing! TARA will reply instantly.

---

## 🏗️ Architecture

*   **Frontend**: Flutter (Dart)
*   **State Management**: Provider
*   **Database**: sqflite
*   **Inference Engine**:
    *   **Offline**: [llama.cpp](https://github.com/ggerganov/llama.cpp) (C++)
    *   **Online**: Groq API, Google Gemini API
*   **Bridge**: Dart FFI (Foreign Function Interface)

---

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

---

## 📄 License

This project is licensed under the MIT License.
