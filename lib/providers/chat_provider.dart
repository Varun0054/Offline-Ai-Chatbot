import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import '../data/database_helper.dart';
import '../native/native_client.dart';

class ChatProvider with ChangeNotifier {
  List<Map<String, dynamic>> _conversations = [];
  List<Map<String, dynamic>> _messages = [];
  int? _currentConversationId;
  bool _isGenerating = false;

  List<Map<String, dynamic>> get conversations => _conversations;
  List<Map<String, dynamic>> get messages => _messages;
  bool get isGenerating => _isGenerating;
  int? get currentConversationId => _currentConversationId;

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

    // 1. Save user message
    await _dbHelper.insertMessage(_currentConversationId!, 'user', text);
    await loadMessages(_currentConversationId!);

    // 2. Generate reply
    _isGenerating = true;
    notifyListeners();

    try {
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
        
        _nativeClient.initRuntime(finalModelPath, "Q4_0", threads);
      } else {
        await _dbHelper.insertMessage(_currentConversationId!, 'assistant', "Error: No model selected. Please go to Settings and select a model.");
        return;
      }

      // Create placeholder assistant message
      final assistantMsgId = await _dbHelper.insertMessage(_currentConversationId!, 'assistant', '');
      await loadMessages(_currentConversationId!);

      // Stream generation
      String fullResponse = "";
      
      await for (final token in _nativeClient.generateReply(_currentConversationId!, text)) {
        fullResponse += token;
        
        // Update local state for UI
        final msgIndex = _messages.indexWhere((m) => m['id'] == assistantMsgId);
        if (msgIndex != -1) {
          _messages[msgIndex] = {..._messages[msgIndex], 'text': fullResponse};
          notifyListeners();
        }
      }
      
      // Final save
      await _dbHelper.updateMessageText(assistantMsgId, fullResponse);
      
    } catch (e, stackTrace) {
      print("Error generating reply: $e");
      print(stackTrace);
      await _dbHelper.insertMessage(_currentConversationId!, 'assistant', "Error: $e");
    } finally {
      _isGenerating = false;
      await loadMessages(_currentConversationId!);
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

  Future<void> deleteConversation(int id) async {
    await _dbHelper.deleteConversation(id);
    if (_currentConversationId == id) {
      _currentConversationId = null;
      _messages = [];
    }
    await _loadConversations();
  }
}
