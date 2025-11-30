
class PromptBuilder {
  static String buildPrompt(
    String modelPath,
    List<Map<String, dynamic>> messages,
  ) {
    // Default to Qwen/ChatML format as we are migrating away from TinyLlama
    return _buildQwenPrompt(messages);
  }

  static String _buildQwenPrompt(List<Map<String, dynamic>> messages) {
    final buffer = StringBuffer();
    
    // 1. System Message (Strict ChatML)
    // Explicitly define persona to prevent hallucinations
    buffer.write('<|im_start|>system\nYou are TARA, a helpful and concise offline AI assistant. Your name is TARA. You are not a human. You do not have a gender. You answer questions directly and briefly. Do not continue fictional stories, do not roleplay, do not create personas, and do not extend conversations that never happened. If you do not know the answer, say "I do not know". Do not make up facts. Always answer directly and factually.<|im_end|>\n');

    // 2. Add History (Last 6 messages / 3 turns)
    int startIndex = messages.length > 6 ? messages.length - 6 : 0;
    for (int i = startIndex; i < messages.length; i++) {
      final msg = messages[i];
      final role = msg['role'];
      String content = msg['text'] ?? "";
      
      // Sanitize content
      content = content
          .replaceAll('<|im_start|>', '')
          .replaceAll('<|im_end|>', '')
          .replaceAll('<|user|>', '')
          .replaceAll('<|assistant|>', '')
          .trim();

      if (role == 'user') {
        buffer.write('<|im_start|>user\n$content<|im_end|>\n');
      } else if (role == 'assistant') {
        buffer.write('<|im_start|>assistant\n$content<|im_end|>\n');
      }
    }

    // 3. Assistant Start Token
    buffer.write('<|im_start|>assistant\n');
    return buffer.toString();
  }
}
