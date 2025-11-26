# Offline AI Chat 🤖💬

![Flutter](https://img.shields.io/badge/Flutter-%2302569B.svg?style=for-the-badge&logo=Flutter&logoColor=white)
![C++](https://img.shields.io/badge/c++-%2300599C.svg?style=for-the-badge&logo=c%2B%2B&logoColor=white)
![Privacy Focused](https://img.shields.io/badge/Privacy-Focused-success?style=for-the-badge)

A powerful, **fully offline** chat application built with Flutter and C++. Experience the power of Large Language Models (LLMs) directly on your device without any internet connection. 🚀

---

## ✨ Features

*   **🔒 100% Offline & Private**: Your data never leaves your device. All inference happens locally.
*   **⚡ High Performance**: Powered by `llama.cpp` via Dart FFI for near-native speed.
*   **🧠 Bring Your Own Model**: Support for GGUF models (Llama 3, Mistral, Gemma, etc.).
*   **💾 Local History**: Conversations are saved securely using SQLite.
*   **🎨 Modern UI**: Beautiful Material 3 design with dark mode support.
*   **⚙️ Customizable**: Adjust CPU threads and quantization settings for your device.

---

## 📸 Screenshots

| Home Screen | Chat Interface | Settings |
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
    *   Recommended: [Llama-3-8B-Instruct-GGUF](https://huggingface.co/lmstudio-community/Meta-Llama-3-8B-Instruct-GGUF) or [Mistral-7B-Instruct-v0.3-GGUF](https://huggingface.co/maziyarpanahi/Mistral-7B-Instruct-v0.3-GGUF).
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
        You may need to build the native library first if not configured automatically.
        ```bash
        cd native
        mkdir build && cd build
        cmake ..
        cmake --build . --config Release
        # Ensure offline_chat_native.dll is in the build output or system path.
        ```

---

## 📖 Usage

1.  Open the app.
2.  Go to **Settings** (⚙️ icon).
3.  Select your downloaded model from the dropdown list.
4.  (Optional) Adjust CPU threads (usually 4-8) and quantization preset.
5.  Return to the home screen and start chatting!

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
