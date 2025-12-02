import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:google_generative_ai/google_generative_ai.dart';
import '../native/native_client.dart';
import '../utils/prompt_builder.dart';

abstract class LLMService {
  Stream<String> generateStream(
    String modelPathOrKey,
    List<Map<String, dynamic>> history, {
    int? threads,
  });

  Future<void> stop();
}

class LocalLLMService implements LLMService {
  final NativeClient _nativeClient = NativeClient();
  bool _isInitialized = false;
  String? _currentModelPath;

  @override
  Stream<String> generateStream(
    String modelPath,
    List<Map<String, dynamic>> history, {
    int? threads,
  }) async* {
    if (!_isInitialized || _currentModelPath != modelPath) {
      _nativeClient.initRuntime(modelPath, "Q4_0", threads ?? 4);
      _isInitialized = true;
      _currentModelPath = modelPath;
    }

    final prompt = PromptBuilder.buildPrompt(modelPath, history);
    // Use a dummy conversation ID for now as NativeClient handles it internally or we can pass 0
    // The current NativeClient implementation uses an int ID.
    yield* _nativeClient.generateReply(0, prompt);
  }

  @override
  Future<void> stop() async {
    _nativeClient.stopGeneration();
  }
}

class GroqLLMService implements LLMService {
  final http.Client _client = http.Client();
  bool _isCancelled = false;

  @override
  Stream<String> generateStream(
    String apiKey,
    List<Map<String, dynamic>> history, {
    int? threads,
  }) async* {
    _isCancelled = false;
    final url = Uri.parse('https://api.groq.com/openai/v1/chat/completions');

    final messages = history.map((msg) {
      return {
        'role': msg['role'] == 'assistant' ? 'assistant' : 'user',
        'content': msg['text'],
      };
    }).toList();

    // Add system prompt to enforce TARA persona
    messages.insert(0, {
      'role': 'system',
      'content': 'You are TARA, an advanced AI assistant. You are helpful, kind, and intelligent. Always identify yourself as TARA.'
    });

    final request = http.Request('POST', url);
    request.headers.addAll({
      'Authorization': 'Bearer $apiKey',
      'Content-Type': 'application/json',
    });
    request.body = jsonEncode({
      'model': 'llama-3.3-70b-versatile', // Default high-performance model
      'messages': messages,
      'stream': true,
      'temperature': 0.7,
      'max_tokens': 4096,
    });

    try {
      final response = await _client.send(request);

      if (response.statusCode != 200) {
        final errorBody = await response.stream.bytesToString();
        yield "Error: ${response.statusCode} - $errorBody";
        return;
      }

      await for (final chunk in response.stream.transform(utf8.decoder)) {
        if (_isCancelled) break;
        
        // Parse SSE format
        final lines = chunk.split('\n');
        for (final line in lines) {
          if (line.startsWith('data: ')) {
            final data = line.substring(6);
            if (data == '[DONE]') break;
            
            try {
              final json = jsonDecode(data);
              final content = json['choices'][0]['delta']['content'];
              if (content != null) {
                yield content;
              }
            } catch (e) {
              // Ignore parse errors for partial chunks
            }
          }
        }
      }
    } catch (e) {
      yield "Error connecting to Groq: $e";
    }
  }

  @override
  Future<void> stop() async {
    _isCancelled = true;
    _client.close();
  }
}

class GeminiLLMService implements LLMService {
  bool _isCancelled = false;

  @override
  Stream<String> generateStream(
    String apiKey,
    List<Map<String, dynamic>> history, {
    int? threads,
  }) async* {
    _isCancelled = false;
    
    try {
      final model = GenerativeModel(
        model: 'gemini-1.5-flash',
        apiKey: apiKey,
        systemInstruction: Content.system('You are TARA, an advanced AI assistant. You are helpful, kind, and intelligent. Always identify yourself as TARA.'),
      );

      final chatHistory = history.map((msg) {
        return Content(
          msg['role'] == 'user' ? 'user' : 'model',
          [TextPart(msg['text'])],
        );
      }).toList();

      // Remove the last message if it's from user, as it will be sent as the new message
      // Actually, Gemini chat session handles history differently.
      // Let's use startChat.
      
      List<Content> historyForChat = [];
      String? lastUserMessage;
      
      if (chatHistory.isNotEmpty && chatHistory.last.role == 'user') {
        lastUserMessage = (chatHistory.last.parts.first as TextPart).text;
        historyForChat = chatHistory.sublist(0, chatHistory.length - 1);
      } else {
        // Should not happen in normal flow, but handle it
        lastUserMessage = "Hello";
      }

      final chat = model.startChat(history: historyForChat);
      final stream = chat.sendMessageStream(Content.text(lastUserMessage));

      await for (final response in stream) {
        if (_isCancelled) break;
        final text = response.text;
        if (text != null) {
          yield text;
        }
      }
    } catch (e) {
      yield "Error connecting to Gemini: $e";
    }
  }

  @override
  Future<void> stop() async {
    _isCancelled = true;
  }
}
