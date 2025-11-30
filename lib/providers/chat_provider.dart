import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import '../data/database_helper.dart';
import '../native/native_client.dart';
import '../utils/prompt_builder.dart';

class ChatProvider with ChangeNotifier {
  List<Map<String, dynamic>> _conversations = [];
  List<Map<String, dynamic>> _messages = [];
  int? _currentConversationId;
  bool _isGenerating = false;

  List<Map<String, dynamic>> get conversations => _conversations;
  List<Map<String, dynamic>> get messages => _messages;
  bool get isGenerating => _isGenerating;

  int? get currentConversationId => _currentConversationId;
  double _generationSpeed = 0.0;
  double get generationSpeed => _generationSpeed;

  final DatabaseHelper _dbHelper = DatabaseHelper.instance;
  final NativeClient _nativeClient = NativeClient();

  ChatProvider() {
    _loadConversations();
    // Initialize native client (mock/stub)
    // In real app, might want to do this based on settings or user action
    // _nativeClient.initRuntime("path/to/model", "Q4_0", 4);
  }

  Future<void> _loadConversations() async {
    _conversations = await _dbHelper.getConversations();
    notifyListeners();
  }

  Future<void> createNewConversation(String title) async {
    final id = await _dbHelper.createConversation(title);
    await _loadConversations();
    await loadMessages(id);
  }

  Future<void> loadMessages(int conversationId) async {
    _currentConversationId = conversationId;
    final rawMessages = await _dbHelper.getMessages(conversationId);
    // Deep copy to ensure mutability of both list and maps
    _messages = rawMessages.map((m) => Map<String, dynamic>.from(m)).toList();
    notifyListeners();
  }

  Future<void> sendMessage(String text) async {
    if (_currentConversationId == null) return;
    if (_isGenerating) return; // Prevent concurrent generation

    _isGenerating = true;
    notifyListeners();
    print("DEBUG: Starting generation with FIXES applied (Race Condition + Stop Sequence)");

    try {
      // 1. Save user message to DB
      final userMsgId = await _dbHelper.insertMessage(_currentConversationId!, 'user', text);
      
      // OPTIMIZATION: Add to local list immediately instead of reloading from DB
      // This prevents the "flicker" and race condition
      _messages.add({
        'id': userMsgId,
        'conversation_id': _currentConversationId,
        'role': 'user',
        'text': text,
        // Add timestamp if needed, but for now this is enough for UI
      });
      notifyListeners();

      // Initialize runtime if needed
      final modelPath = await _dbHelper.getSetting('model_path');
      final threadsStr = await _dbHelper.getSetting('cpu_threads');
      final threads = int.tryParse(threadsStr ?? '4') ?? 4;

      if (modelPath != null && modelPath.isNotEmpty) {
        String finalModelPath = modelPath;
        
        // Check if model path is an asset path (starts with assets/)
        if (modelPath.startsWith('assets/')) {
          finalModelPath = await _copyAssetToAppDir(modelPath);
        }

        if (!File(finalModelPath).existsSync()) {
           _messages.add({
            'id': -1,
            'conversation_id': _currentConversationId,
            'role': 'assistant',
            'text': "Error: Model file not found at $finalModelPath. Please download the model.",
          });
          notifyListeners();
          _isGenerating = false;
          return;
        }
        
        _nativeClient.initRuntime(finalModelPath, "Q4_0", threads);
        
        // --- Build Prompt with History ---
        final history = _messages; 
        final prompt = PromptBuilder.buildPrompt(finalModelPath, history);
        print("Generated Prompt:\n$prompt"); 
        
        // 2. Create placeholder assistant message in DB
        final assistantMsgId = await _dbHelper.insertMessage(_currentConversationId!, 'assistant', '');
        
        // OPTIMIZATION: Add placeholder to local list immediately
        _messages.add({
          'id': assistantMsgId,
          'conversation_id': _currentConversationId,
          'role': 'assistant',
          'text': '', // Start empty
        });
        notifyListeners();

        // Stream generation
        String fullResponse = "";
        DateTime lastUpdateTime = DateTime.now();
        DateTime startTime = DateTime.now();
        int tokenCount = 0;
        
        await for (final token in _nativeClient.generateReply(_currentConversationId!, prompt)) {
          // Check for stop sequences
          if (token.contains('<|im_end|>') || token.contains('<|im_start|>') || token.contains('</s>')) {
             break; 
          }
          
          fullResponse += token;
          tokenCount++;
          
          // Calculate Speed
          final elapsed = DateTime.now().difference(startTime).inMilliseconds;
          if (elapsed > 0) {
            _generationSpeed = (tokenCount / elapsed) * 1000;
          }

          // Real-time Sanitization for UI
          String displayResponse = fullResponse
              .replaceAll('<|im_end|>', '')
              .replaceAll('<|im_end|', '')
              .replaceAll('<|user|>', '')
              .replaceAll('<|user|', '')
              .replaceAll('<|assistant|>', '')
              .replaceAll('InternalEnumerator', '')
              .replaceAll('TEntity', '')
              .replaceAll('Tentity', '')
              .replaceAll(RegExp(r'\bTarra\b', caseSensitive: false), 'TARA')
              .replaceAll(RegExp(r'\bTaral\b', caseSensitive: false), 'TARA')
              .replaceAll(RegExp(r'\bTaraLove\b', caseSensitive: false), 'TARA');

          // Robust check on the full string for various stop patterns
          // The model might generate "User:" or "Al:" if it gets confused
          if (fullResponse.contains('<|im_end|>') || 
              fullResponse.contains('<|im_start|>') ||
              fullResponse.contains('</s>') ||
              fullResponse.contains('<|user|>') ||
              fullResponse.contains('<|model|>') ||
              fullResponse.contains('\nUser:') ||
              fullResponse.contains('\nAl:') || // Common hallucination
              fullResponse.contains('\nSystem:') ||
              fullResponse.endsWith('User:') || // In case it's at the very end
              fullResponse.endsWith('Al:') ||
              // Check for partial stop tokens at the end (common issue)
              fullResponse.endsWith('<|im_end|') ||
              fullResponse.endsWith('<|im_start|') ||
              fullResponse.endsWith('</s')
          ) {
            // Clean up the stop token from the response
            fullResponse = fullResponse
                .replaceAll('<|im_end|>', '')
                .replaceAll('<|im_end|', '') // Handle partial
                .replaceAll('<|im_start|>', '')
                .replaceAll('<|im_start|', '') // Handle partial
                .replaceAll('</s>', '')
                .replaceAll('<|endoftext|>', '')
                .replaceAll('<|user|>', '')
                .replaceAll('<|assistant|>', '')
                .replaceAll('User:', '')
                .replaceAll('Assistant:', '')
                // Enforce TARA Persona Name
                .replaceAll(RegExp(r'\bTarra\b', caseSensitive: false), 'TARA')
                .replaceAll(RegExp(r'\bTaral\b', caseSensitive: false), 'TARA')
                .replaceAll(RegExp(r'\bTaraLove\b', caseSensitive: false), 'TARA')
                .trim();
            
            // Update local UI state
            final msgIndex = _messages.indexWhere((m) => m['id'] == assistantMsgId);
            if (msgIndex != -1) {
              _messages[msgIndex] = {..._messages[msgIndex], 'text': fullResponse};
              notifyListeners();
            }
            break; 
          }
          
          // Update local UI state
          final msgIndex = _messages.indexWhere((m) => m['id'] == assistantMsgId);
          if (msgIndex != -1) {
            _messages[msgIndex] = {..._messages[msgIndex], 'text': displayResponse};
            
            // OPTIMIZATION: Throttle UI updates to prevent lag
            // Update only if 100ms passed OR 5 tokens generated
            if (DateTime.now().difference(lastUpdateTime).inMilliseconds > 100 || tokenCount % 5 == 0) {
               notifyListeners();
               lastUpdateTime = DateTime.now();
            }
          }
        }
        // Final update to ensure everything is shown
        notifyListeners();
        
        // Final Sanitization before saving to DB
        String finalResponse = fullResponse
            .replaceAll('<|im_end|>', '')
            .replaceAll('<|im_end|', '')
            .replaceAll('<|im_start|>', '')
            .replaceAll('<|im_start|', '')
            .replaceAll('</s>', '')
            .replaceAll('</s', '')
            .replaceAll('<|user|>', '')
            .replaceAll('<|user|', '')
            .replaceAll('<|assistant|>', '')
            .replaceAll('InternalEnumerator', '')
            .replaceAll('TEntity', '')
            .replaceAll('Tentity', '')
            .replaceAll('<|model|>', '')
            .replaceAll(RegExp(r'\nUser:.*'), '')
            .replaceAll(RegExp(r'\nAl:.*'), '')
            .replaceAll('User:', '')
            .replaceAll('Al:', '')
            .replaceAll(RegExp(r'\bTarra\b', caseSensitive: false), 'TARA')
            .replaceAll(RegExp(r'\bTaral\b', caseSensitive: false), 'TARA')
            .replaceAll(RegExp(r'\bTaraLove\b', caseSensitive: false), 'TARA')
            .trim();

        // Final save to DB
        await _dbHelper.updateMessageText(assistantMsgId, finalResponse);

      } else {
        // Handle no model error locally
         _messages.add({
          'id': -1, // Temporary ID
          'conversation_id': _currentConversationId,
          'role': 'assistant',
          'text': "Error: No model selected. Please go to Settings and select a model.",
        });
        notifyListeners();
        return;
      }
      
    } catch (e, stackTrace) {
      print("Error generating reply: $e");
      print(stackTrace);
      // Show error in UI
       _messages.add({
          'id': -1,
          'conversation_id': _currentConversationId,
          'role': 'assistant',
          'text': "Error: $e",
        });
        notifyListeners();
    } finally {
      _isGenerating = false;
      notifyListeners();
      // We do NOT call loadMessages() here to avoid overwriting the state we just carefully built.
      // The state is already consistent with DB (except maybe IDs for error msgs, but that's fine).
    }
  }

  Future<String> _copyAssetToAppDir(String assetPath) async {
    try {
      final filename = assetPath.split('/').last;
      final appDir = await getApplicationDocumentsDirectory();
      final modelDir = Directory("${appDir.path}/models");
      
      if (!await modelDir.exists()) {
        await modelDir.create(recursive: true);
      }
      
      final file = File("${modelDir.path}/$filename");
      
      // Only copy if not exists
      if (!await file.exists()) {
        print("Copying model from assets to ${file.path}...");
        final byteData = await rootBundle.load(assetPath);
        await file.writeAsBytes(byteData.buffer.asUint8List());
        print("Model copied successfully.");
      } else {
        print("Model already exists at ${file.path}");
      }
      
      return file.path;
    } catch (e) {
      print("Error copying asset: $e");
      return assetPath; // Fallback to original path if copy fails
    }
  }

  void stopGeneration() {
    if (_isGenerating) {
      _nativeClient.stopGeneration();
      _isGenerating = false;
      notifyListeners();
    }
  }

  Future<void> deleteConversation(int id) async {
    await _dbHelper.deleteConversation(id);
    if (_currentConversationId == id) {
      _currentConversationId = null;
      _messages = [];
    }
    await _loadConversations();
  }
}
