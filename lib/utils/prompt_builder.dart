
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
    buffer.write("<|im_start|>system\nYou are a helpful AI assistant.<|im_end|>\n");

    // 2. Last User Message ONLY (Strict Context Trimming)
    // We ignore previous history to prevent the model from looping on its own previous bad output.
    if (messages.isNotEmpty) {
      final lastMsg = messages.last;
      if (lastMsg['role'] == 'user') {
        buffer.write("<|im_start|>user\n${lastMsg['text']}<|im_end|>\n");
      } else {
        // If the last message isn't user (rare), find the last user message
        final lastUserMsg = messages.lastWhere(
          (m) => m['role'] == 'user',
          orElse: () => {},
        );
        if (lastUserMsg.isNotEmpty) {
           buffer.write("<|im_start|>user\n${lastUserMsg['text']}<|im_end|>\n");
        }
      }
    }

    // 3. Assistant Start Token
    buffer.write("<|im_start|>assistant\n"); 

    return buffer.toString();
  }
}
