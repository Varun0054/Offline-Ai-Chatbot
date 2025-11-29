
class PromptBuilder {
  static String buildPrompt(
    String modelPath,
    List<Map<String, dynamic>> messages,
  ) {
    final isQwen = modelPath.toLowerCase().contains('qwen');
    final isTinyLlama = modelPath.toLowerCase().contains('tinyllama');

    // STRICT CONTEXT: Only send System Message + Last User Message
    // This prevents tiny models from getting confused by history or hallucinating from previous turns.
    
    List<Map<String, dynamic>> limitedMessages = [];
    
    // 1. Add System Message (if present)
    if (messages.isNotEmpty && messages.first['role'] == 'system') {
      limitedMessages.add(messages.first);
    }
    
    // 2. Add Last User Message
    // Find the last message that is from the user
    final lastUserMsgIndex = messages.lastIndexWhere((m) => m['role'] == 'user');
    if (lastUserMsgIndex != -1) {
      limitedMessages.add(messages[lastUserMsgIndex]);
    } else if (messages.isNotEmpty && messages.last['role'] == 'user') {
       // Fallback if lastIndexWhere fails for some reason (unlikely)
       limitedMessages.add(messages.last);
    }

    if (isQwen) {
      return _buildQwenPrompt(limitedMessages);
    } else if (isTinyLlama) {
      return _buildTinyLlamaPrompt(limitedMessages);
    } else {
      // Fallback
      return _buildTinyLlamaPrompt(limitedMessages); 
    }
  }

  static String _buildQwenPrompt(List<Map<String, dynamic>> messages) {
    final buffer = StringBuffer();
    
    // Add default system prompt if not present
    if (messages.isEmpty || messages.first['role'] != 'system') {
       buffer.write('<|im_start|>system\nYou are a helpful AI assistant.<|im_end|>\n');
    }

    for (final msg in messages) {
      final role = msg['role'];
      final content = msg['text'];
      buffer.write('<|im_start|>$role\n$content<|im_end|>\n');
    }
    buffer.write('<|im_start|>assistant\n');
    return buffer.toString();
  }

  static String _buildTinyLlamaPrompt(List<Map<String, dynamic>> messages) {
    final buffer = StringBuffer();

    // 1. System Message (Strict ChatML)
    // Explicitly define persona to prevent hallucinations
    buffer.write("<|im_start|>system\nYou are TARA, a helpful and concise offline AI assistant. Your name is TARA. You are not a human. You do not have a gender. You answer questions directly and briefly. Do not continue fictional stories, do not roleplay, do not create personas, and do not extend conversations that never happened. Always answer directly and factually.<|im_end|>\n");

    // 2. Add History (Last 6 messages / 3 turns)
    // We restore memory but SANITIZE it to prevent "poisoning" from previous bad outputs.
    int startIndex = messages.length > 6 ? messages.length - 6 : 0;
    for (int i = startIndex; i < messages.length; i++) {
      final msg = messages[i];
      final role = msg['role'];
      String content = msg['text'] ?? "";
      
      // CRITICAL: Sanitize content to remove any leaked tags or hallucinations
      // This prevents the model from seeing "<|user|>" or "Taral" in its own history
      content = content
          .replaceAll('<|im_start|>', '')
          .replaceAll('<|im_end|>', '')
          .replaceAll('<|user|>', '')
          .replaceAll('<|assistant|>', '')
          .replaceAll('</s>', '')
          .trim();

      if (role == 'user') {
        buffer.write("<|im_start|>user\n$content<|im_end|>\n");
      } else if (role == 'assistant') {
        buffer.write("<|im_start|>assistant\n$content<|im_end|>\n");
      }
    }

    // 3. Assistant Start Token
    buffer.write("<|im_start|>assistant\n"); 

    return buffer.toString();
  }
}
