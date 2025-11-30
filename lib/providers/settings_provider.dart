import 'dart:io';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../data/database_helper.dart';

class SettingsProvider with ChangeNotifier {
  String _modelPath = '';
  int _cpuThreads = 4;
  String _quantization = 'Q4_0';
  List<String> _availableModels = [];

  String get modelPath => _modelPath;
  int get cpuThreads => _cpuThreads;
  String get quantization => _quantization;
  List<String> get availableModels => _availableModels;

  final DatabaseHelper _dbHelper = DatabaseHelper.instance;

  SettingsProvider() {
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    _modelPath = await _dbHelper.getSetting('model_path') ?? '/storage/emulated/0/Download/Model/Qwen-1.8B-Finetuned.i1-Q4_K_M.gguf';
    final threadsStr = await _dbHelper.getSetting('cpu_threads');
    _cpuThreads = threadsStr != null ? int.tryParse(threadsStr) ?? 2 : 2;
    _quantization = await _dbHelper.getSetting('quantization') ?? 'Q4_0';
    notifyListeners();
  }

  Future<void> setModelPath(String path) async {
    _modelPath = path;
    await _dbHelper.setSetting('model_path', path);
    notifyListeners();
  }

  Future<void> setCpuThreads(int threads) async {
    _cpuThreads = threads;
    await _dbHelper.setSetting('cpu_threads', threads.toString());
    notifyListeners();
  }

  Future<void> setQuantization(String preset) async {
    _quantization = preset;
    await _dbHelper.setSetting('quantization', preset);
    notifyListeners();
  }

  Future<void> scanForModels() async {
    // Request permission first
    var status = await Permission.manageExternalStorage.status;
    if (!status.isGranted) {
      status = await Permission.manageExternalStorage.request();
    }
    
    // Fallback for older Android if manageExternalStorage is not applicable
    if (!status.isGranted) {
       var status2 = await Permission.storage.status;
       if (!status2.isGranted) {
         await Permission.storage.request();
       }
    }

    final Directory dir = Directory('/storage/emulated/0/Download/Model');
    if (await dir.exists()) {
      final List<FileSystemEntity> entities = await dir.list().toList();
      _availableModels = entities
          .whereType<File>()
          .where((file) => file.path.endsWith('.gguf'))
          .map((file) => file.path)
          .toList();
      notifyListeners();
    } else {
      // Try creating it if it doesn't exist
      try {
        await dir.create(recursive: true);
      } catch (e) {
        print("Error creating directory: $e");
      }
    }
  }
}
