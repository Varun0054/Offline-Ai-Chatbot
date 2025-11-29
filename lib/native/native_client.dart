import 'dart:async';
import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:isolate';
import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as path;

// FFI Signatures
// FFI Signatures
typedef InitRuntimeNative = ffi.Int32 Function(ffi.Pointer<Utf8> modelDir, ffi.Pointer<Utf8> quantPreset, ffi.Int32 cpuThreads);
typedef InitRuntimeDart = int Function(ffi.Pointer<Utf8> modelDir, ffi.Pointer<Utf8> quantPreset, int cpuThreads);

typedef ShutdownRuntimeNative = ffi.Void Function();
typedef ShutdownRuntimeDart = void Function();

typedef CreateConversationNative = ffi.Int32 Function();
typedef CreateConversationDart = int Function();

typedef StartCompletionNative = ffi.Int32 Function(ffi.Pointer<Utf8> prompt);
typedef StartCompletionDart = int Function(ffi.Pointer<Utf8> prompt);

typedef ContinueCompletionNative = ffi.Int32 Function(ffi.Pointer<Utf8> buf, ffi.Int32 len);
typedef ContinueCompletionDart = int Function(ffi.Pointer<Utf8> buf, int len);

typedef StopCompletionNative = ffi.Void Function();
typedef StopCompletionDart = void Function();

class NativeClient {
  static final NativeClient _instance = NativeClient._internal();
  factory NativeClient() => _instance;
  NativeClient._internal();

  late ffi.DynamicLibrary _nativeLib;
  late InitRuntimeDart _initRuntime;
  late ShutdownRuntimeDart _shutdownRuntime;
  late CreateConversationDart _createConversation;
  
  late StartCompletionDart _startCompletion;
  late ContinueCompletionDart _continueCompletion;
  late StopCompletionDart _stopCompletion;

  bool _isInitialized = false;

  void initialize() {
    if (_isInitialized) return;

    if (Platform.isWindows) {
      try {
        _nativeLib = ffi.DynamicLibrary.open('offline_chat_native.dll');
      } catch (e) {
        print('Error loading native library: $e');
        return; 
      }
    } else if (Platform.isAndroid) {
      _nativeLib = ffi.DynamicLibrary.open('liboffline_chat_native.so');
    } else if (Platform.isIOS) {
      _nativeLib = ffi.DynamicLibrary.process();
    } else {
      throw UnsupportedError('Platform not supported');
    }

    _initRuntime = _nativeLib
        .lookup<ffi.NativeFunction<InitRuntimeNative>>('init_runtime')
        .asFunction();

    _shutdownRuntime = _nativeLib
        .lookup<ffi.NativeFunction<ShutdownRuntimeNative>>('shutdown_runtime')
        .asFunction();

    _createConversation = _nativeLib
        .lookup<ffi.NativeFunction<CreateConversationNative>>('create_conversation')
        .asFunction();

    _startCompletion = _nativeLib
        .lookup<ffi.NativeFunction<StartCompletionNative>>('start_completion')
        .asFunction();

    _continueCompletion = _nativeLib
        .lookup<ffi.NativeFunction<ContinueCompletionNative>>('continue_completion')
        .asFunction();

    _stopCompletion = _nativeLib
        .lookup<ffi.NativeFunction<StopCompletionNative>>('stop_completion')
        .asFunction();

    _isInitialized = true;
  }

  int initRuntime(String modelDir, String quantPreset, int cpuThreads) {
    if (!_isInitialized) initialize();
    final modelDirPtr = modelDir.toNativeUtf8();
    final quantPresetPtr = quantPreset.toNativeUtf8();
    
    final result = _initRuntime(modelDirPtr, quantPresetPtr, cpuThreads);
    
    calloc.free(modelDirPtr);
    calloc.free(quantPresetPtr);
    return result;
  }

  void shutdown() {
    if (!_isInitialized) return;
    _shutdownRuntime();
  }

  int createConversation() {
    if (!_isInitialized) initialize();
    return _createConversation();
  }

  Isolate? _currentIsolate;
  ReceivePort? _currentReceivePort;
  StreamController<String>? _currentController;

  Stream<String> generateReply(int conversationId, String prompt) {
    // Cancel any existing generation
    stopGeneration();

    // Stream controller to bridge Isolate -> UI
    final controller = StreamController<String>();
    _currentController = controller;
    
    final receivePort = ReceivePort();
    _currentReceivePort = receivePort;
    
    // Spawn the isolate
    Isolate.spawn(_generateReplyIsolate, _GenerateReplyArgs(
      conversationId: conversationId,
      prompt: prompt,
      sendPort: receivePort.sendPort,
      libraryPath: Platform.isAndroid ? 'liboffline_chat_native.so' : 'offline_chat_native.dll',
    )).then((isolate) {
      _currentIsolate = isolate;
    });

    // Listen to messages from the isolate
    receivePort.listen((message) {
      if (message is String) {
        controller.add(message);
      } else if (message == null) {
        // EOS or Done
        controller.close();
        receivePort.close();
        _currentIsolate = null;
      } else if (message is _Error) {
        controller.addError(message.message);
        controller.close();
        receivePort.close();
        _currentIsolate = null;
      }
    });

    return controller.stream;
  }

  void stopGeneration() {
    if (_currentIsolate != null) {
      _currentIsolate!.kill(priority: Isolate.immediate);
      _currentIsolate = null;
    }
    if (_currentReceivePort != null) {
      _currentReceivePort!.close();
      _currentReceivePort = null;
    }
    if (_currentController != null && !_currentController!.isClosed) {
      _currentController!.close();
      _currentController = null;
    }
  }
}

// Helper classes for Isolate communication
class _GenerateReplyArgs {
  final int conversationId;
  final String prompt;
  final SendPort sendPort;
  final String libraryPath;

  _GenerateReplyArgs({
    required this.conversationId,
    required this.prompt,
    required this.sendPort,
    required this.libraryPath,
  });
}

class _Error {
  final String message;
  _Error(this.message);
}

// Top-level function for the Isolate
void _generateReplyIsolate(_GenerateReplyArgs args) {
  // We need to open the library inside the isolate
  final dylib = ffi.DynamicLibrary.open(args.libraryPath);

  // Look up functions
  final startCompletion = dylib
      .lookup<ffi.NativeFunction<StartCompletionNative>>('start_completion')
      .asFunction<StartCompletionDart>();

  final continueCompletion = dylib
      .lookup<ffi.NativeFunction<ContinueCompletionNative>>('continue_completion')
      .asFunction<ContinueCompletionDart>();

  final stopCompletion = dylib
      .lookup<ffi.NativeFunction<StopCompletionNative>>('stop_completion')
      .asFunction<StopCompletionDart>();

  // Start generation
  final promptPtr = args.prompt.toNativeUtf8();
  final startRes = startCompletion(promptPtr);
  calloc.free(promptPtr);

  if (startRes != 0) {
    args.sendPort.send(_Error("Failed to start generation"));
    return;
  }

  final buf = calloc<ffi.Uint8>(1024);

  try {
    while (true) {
      int res = continueCompletion(buf.cast(), 1024);

      if (res == 0) {
        break; // EOS
      }
      if (res < 0) {
        args.sendPort.send(_Error("Error during generation"));
        break;
      }

      String token = buf.cast<Utf8>().toDartString();
      args.sendPort.send(token);
    }
  } catch (e) {
    args.sendPort.send(_Error(e.toString()));
  } finally {
    stopCompletion();
    calloc.free(buf);
    args.sendPort.send(null); // Signal done
  }
}
