import 'dart:io';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('offline_chat.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }

    final dbPath = await getApplicationDocumentsDirectory();
    final path = join(dbPath.path, filePath);

    return await openDatabase(
      path,
      version: 1,
      onCreate: _createDB,
    );
  }

  Future _createDB(Database db, int version) async {
    const idType = 'INTEGER PRIMARY KEY AUTOINCREMENT';
    const textType = 'TEXT';
    const intType = 'INTEGER';
    const blobType = 'BLOB';

    // Conversations
    await db.execute('''
      CREATE TABLE conversations (
        id $idType,
        title $textType,
        created_at $intType,
        last_modified $intType
      )
    ''');

    // Messages
    await db.execute('''
      CREATE TABLE messages (
        id $idType,
        conversation_id $intType,
        role $textType,
        text $textType,
        tokens $intType,
        created_at $intType,
        FOREIGN KEY (conversation_id) REFERENCES conversations (id) ON DELETE CASCADE
      )
    ''');

    // Embeddings
    await db.execute('''
      CREATE TABLE embeddings (
        id $idType,
        message_id $intType,
        vector $blobType,
        created_at $intType,
        FOREIGN KEY (message_id) REFERENCES messages (id) ON DELETE CASCADE
      )
    ''');

    // Settings
    await db.execute('''
      CREATE TABLE settings (
        key $textType PRIMARY KEY,
        value $textType
      )
    ''');
  }

  // CRUD Operations

  // Conversation
  Future<int> createConversation(String title) async {
    final db = await instance.database;
    final now = DateTime.now().millisecondsSinceEpoch;
    return await db.insert('conversations', {
      'title': title,
      'created_at': now,
      'last_modified': now,
    });
  }

  Future<List<Map<String, dynamic>>> getConversations() async {
    final db = await instance.database;
    return await db.query('conversations', orderBy: 'last_modified DESC');
  }

  Future<int> deleteConversation(int id) async {
    final db = await instance.database;
    return await db.delete(
      'conversations',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // Messages
  Future<int> insertMessage(int conversationId, String role, String text) async {
    final db = await instance.database;
    final now = DateTime.now().millisecondsSinceEpoch;
    
    // Update conversation last_modified
    await db.update(
      'conversations',
      {'last_modified': now},
      where: 'id = ?',
      whereArgs: [conversationId],
    );

    return await db.insert('messages', {
      'conversation_id': conversationId,
      'role': role,
      'text': text,
      'tokens': 0, // Placeholder
      'created_at': now,
    });
  }

  Future<List<Map<String, dynamic>>> getMessages(int conversationId) async {
    final db = await instance.database;
    return await db.query(
      'messages',
      where: 'conversation_id = ?',
      whereArgs: [conversationId],
      orderBy: 'created_at ASC',
    );
  }

  Future<void> updateMessageText(int id, String text) async {
    final db = await instance.database;
    await db.update(
      'messages',
      {'text': text},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // Settings
  Future<void> setSetting(String key, String value) async {
    final db = await instance.database;
    await db.insert(
      'settings',
      {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<String?> getSetting(String key) async {
    final db = await instance.database;
    final maps = await db.query(
      'settings',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [key],
    );

    if (maps.isNotEmpty) {
      return maps.first['value'] as String;
    }
    return null;
  }
}
