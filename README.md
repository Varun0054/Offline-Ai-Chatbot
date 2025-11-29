# TARA - Offline AI Chat 🤖💬

![Flutter](https://img.shields.io/badge/Flutter-%2302569B.svg?style=for-the-badge&logo=Flutter&logoColor=white)
![C++](https://img.shields.io/badge/c++-%2300599C.svg?style=for-the-badge&logo=c%2B%2B&logoColor=white)
![Privacy Focused](https://img.shields.io/badge/Privacy-Focused-success?style=for-the-badge)

**TARA** is a powerful, **fully offline** chat assistant built with Flutter and C++. Experience the power of Large Language Models (LLMs) like TinyLlama and Qwen directly on your device without any internet connection. 🚀

---

## ✨ Features

*   **🔒 100% Offline & Private**: Your data never leaves your device. All inference happens locally.
*   **🤖 TARA AI**: A friendly, helpful assistant powered by optimized local LLMs.
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

## 📸 Screenshots

| Chat Interface | Drawer Menu | Settings |
|:---:|:---:|:---:|
| *(Place screenshot here)* | *(Place screenshot here)* | *(Place screenshot here)* |

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
        *   [TinyLlama-1.1B-Chat-v1.0-GGUF](https://huggingface.co/TheBloke/TinyLlama-1.1B-Chat-v1.0-GGUF) (Fastest)
        *   [Qwen2.5-0.5B-Instruct-GGUF](https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct-GGUF) (Balanced)
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
*   **Inference Engine**: [llama.cpp](https://github.com/ggerganov/llama.cpp) (C++)
*   **Bridge**: Dart FFI (Foreign Function Interface)

---

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

---

## 📄 License

This project is licensed under the MIT License.
