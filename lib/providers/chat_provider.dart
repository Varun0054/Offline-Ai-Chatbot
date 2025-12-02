import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import '../data/database_helper.dart';
import '../services/llm_service.dart';
import '../utils/prompt_builder.dart';

class ChatProvider with ChangeNotifier {
  List<Map<String, dynamic>> _conversations = [];
  List<Map<String, dynamic>> _messages = [];
  int? _currentConversationId;
  bool _isGenerating = false;

  // Online Mode State
  bool _isOnlineMode = false;
  String _selectedProvider = 'groq'; // 'groq' or 'gemini'
  String _groqApiKey = '';
  String _geminiApiKey = '';

  List<Map<String, dynamic>> get conversations => _conversations;
  List<Map<String, dynamic>> get messages => _messages;
  bool get isGenerating => _isGenerating;
  bool get isOnlineMode => _isOnlineMode;
  String get selectedProvider => _selectedProvider;
  String get groqApiKey => _groqApiKey;
  String get geminiApiKey => _geminiApiKey;

  int? get currentConversationId => _currentConversationId;
  double _generationSpeed = 0.0;
  double get generationSpeed => _generationSpeed;

  final DatabaseHelper _dbHelper = DatabaseHelper.instance;
  
  // Services
  final LocalLLMService _localService = LocalLLMService();
  final GroqLLMService _groqService = GroqLLMService();
  final GeminiLLMService _geminiService = GeminiLLMService();

  ChatProvider() {
    _loadConversations();
    _loadSettings();
  }

  Future<void> _loadConversations() async {
    _conversations = await _dbHelper.getConversations();
    notifyListeners();
  }

  Future<void> _loadSettings() async {
    // Load online mode settings from DB or SharedPrefs
    // For now, we'll assume they are stored in the generic settings table
    _groqApiKey = await _dbHelper.getSetting('groq_api_key') ?? '';
    _geminiApiKey = await _dbHelper.getSetting('gemini_api_key') ?? '';
    _selectedProvider = await _dbHelper.getSetting('online_provider') ?? 'groq';
    final onlineModeStr = await _dbHelper.getSetting('is_online_mode');
    _isOnlineMode = onlineModeStr == 'true';
    notifyListeners();
  }

  Future<void> toggleOnlineMode(bool value) async {
    _isOnlineMode = value;
    await _dbHelper.setSetting('is_online_mode', value.toString());
    notifyListeners();
  }

  Future<void> setProvider(String provider) async {
    _selectedProvider = provider;
    await _dbHelper.setSetting('online_provider', provider);
    notifyListeners();
  }

  Future<void> setApiKeys({String? groq, String? gemini}) async {
    if (groq != null) {
      _groqApiKey = groq;
      await _dbHelper.setSetting('groq_api_key', groq);
    }
    if (gemini != null) {
      _geminiApiKey = gemini;
      await _dbHelper.setSetting('gemini_api_key', gemini);
    }
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
    _messages = rawMessages.map((m) => Map<String, dynamic>.from(m)).toList();
    notifyListeners();
  }

  Future<void> sendMessage(String text) async {
    if (_currentConversationId == null) return;
    if (_isGenerating) return;

    _isGenerating = true;
    notifyListeners();
    print("DEBUG: Starting generation (Online: $_isOnlineMode, Provider: $_selectedProvider)");

    try {
      // 1. Optimistic UI Update for User Message
      final tempUserMsgId = DateTime.now().millisecondsSinceEpoch; // Temporary ID
      final userMsgMap = {
        'id': tempUserMsgId,
        'conversation_id': _currentConversationId,
        'role': 'user',
        'text': text,
      };
      _messages.add(userMsgMap);
      notifyListeners(); // Show user message immediately

      // 2. Save user message to DB in background
      final userMsgId = await _dbHelper.insertMessage(_currentConversationId!, 'user', text);
      // Update the message in the list with the real ID
      final index = _messages.indexWhere((m) => m['id'] == tempUserMsgId);
      if (index != -1) {
        _messages[index]['id'] = userMsgId;
      }

      // 2. Create placeholder assistant message
      final assistantMsgId = await _dbHelper.insertMessage(_currentConversationId!, 'assistant', '');
      _messages.add({
        'id': assistantMsgId,
        'conversation_id': _currentConversationId,
        'role': 'assistant',
        'text': '',
      });
      notifyListeners();

      // 3. Select Service and Config
      LLMService service;
      String config; // Model path or API Key

      if (_isOnlineMode) {
        if (_selectedProvider == 'groq') {
          service = _groqService;
          config = _groqApiKey;
          if (config.isEmpty) throw Exception("Groq API Key is missing.");
        } else {
          service = _geminiService;
          config = _geminiApiKey;
          if (config.isEmpty) throw Exception("Gemini API Key is missing.");
        }
      } else {
        service = _localService;
        String? modelPath = await _dbHelper.getSetting('model_path');
        if (modelPath == null || modelPath.isEmpty) {
           // Fallback to default path if not set
           modelPath = '/storage/emulated/0/Download/Model/Qwen-1.8B-Finetuned.i1-Q4_K_M.gguf';
        }
        
        if (modelPath.isEmpty) {
           throw Exception("No local model selected.");
        }
        
        // Handle asset path logic
        if (modelPath.startsWith('assets/')) {
          config = await _copyAssetToAppDir(modelPath);
        } else {
          config = modelPath;
        }
        
        if (!File(config).existsSync()) {
           throw Exception("Model file not found at $config");
        }
      }

      // 4. Generate Stream
      String fullResponse = "";
      DateTime lastUpdateTime = DateTime.now();
      DateTime startTime = DateTime.now();
      int tokenCount = 0;

      // Pass history excluding the placeholder we just added
      final historyForPrompt = _messages.sublist(0, _messages.length - 1);

      await for (final token in service.generateStream(config, historyForPrompt)) {
        // Basic stop sequence check (mostly for local)
        if (!_isOnlineMode && (token.contains('<|im_end|>') || token.contains('</s>'))) {
           break; 
        }
        
        fullResponse += token;
        tokenCount++;
        
        // Calculate Speed
        final elapsed = DateTime.now().difference(startTime).inMilliseconds;
        if (elapsed > 0) {
          _generationSpeed = (tokenCount / elapsed) * 1000;
        }

        // Real-time Sanitization (mostly for local)
        String displayResponse = _sanitizeResponse(fullResponse);

        // Update UI
        final msgIndex = _messages.indexWhere((m) => m['id'] == assistantMsgId);
        if (msgIndex != -1) {
          _messages[msgIndex] = {..._messages[msgIndex], 'text': displayResponse};
          
          if (DateTime.now().difference(lastUpdateTime).inMilliseconds > 100 || tokenCount % 5 == 0) {
             notifyListeners();
             lastUpdateTime = DateTime.now();
          }
        }
      }
      
      notifyListeners();
      
      // Final save
      String finalResponse = _sanitizeResponse(fullResponse).trim();
      await _dbHelper.updateMessageText(assistantMsgId, finalResponse);

    } catch (e) {
      print("Error generating reply: $e");
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
    }
  }

  String _sanitizeResponse(String text) {
    if (_isOnlineMode) return text; // Online models usually don't need heavy sanitization
    
    // Local model sanitization logic from before
    return text
        .replaceAll('<|im_end|>', '')
        .replaceAll('<|im_end|', '')
        .replaceAll('<|user|>', '')
        .replaceAll('<|assistant|>', '')
        .replaceAll('InternalEnumerator', '')
        .replaceAll(RegExp(r'\bTarra\b', caseSensitive: false), 'TARA')
        .replaceAll(RegExp(r'\bTaral\b', caseSensitive: false), 'TARA')
        .replaceAll(RegExp(r'\bTaraLove\b', caseSensitive: false), 'TARA');
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
      
      if (!await file.exists()) {
        final byteData = await rootBundle.load(assetPath);
        await file.writeAsBytes(byteData.buffer.asUint8List());
      }
      
      return file.path;
    } catch (e) {
      return assetPath;
    }
  }

  void stopGeneration() {
    if (_isGenerating) {
      if (_isOnlineMode) {
        if (_selectedProvider == 'groq') _groqService.stop();
        else _geminiService.stop();
      } else {
        _localService.stop();
      }
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
