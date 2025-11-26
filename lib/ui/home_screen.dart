import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/chat_provider.dart';
import 'chat_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Offline AI Chat'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const SettingsScreen()),
              );
            },
          ),
        ],
      ),
      body: Consumer<ChatProvider>(
        builder: (context, chatProvider, child) {
          if (chatProvider.conversations.isEmpty) {
            return const Center(
              child: Text('No conversations yet. Start a new one!'),
            );
          }
          return ListView.builder(
            itemCount: chatProvider.conversations.length,
            itemBuilder: (context, index) {
              final conversation = chatProvider.conversations[index];
              return ListTile(
                title: Text(conversation['title'] ?? 'New Chat'),
                subtitle: Text(
                  DateTime.fromMillisecondsSinceEpoch(conversation['last_modified'])
                      .toString(),
                ),
                onTap: () {
                  chatProvider.loadMessages(conversation['id']);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const ChatScreen(),
                    ),
                  );
                },
                trailing: IconButton(
                  icon: const Icon(Icons.delete),
                  onPressed: () {
                    chatProvider.deleteConversation(conversation['id']);
                  },
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          _showNewChatDialog(context);
        },
        child: const Icon(Icons.add),
      ),
    );
  }

  void _showNewChatDialog(BuildContext context) {
    final TextEditingController controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New Chat'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: 'Enter chat title'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              if (controller.text.isNotEmpty) {
                final chatProvider =
                    Provider.of<ChatProvider>(context, listen: false);
                chatProvider.createNewConversation(controller.text).then((_) {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const ChatScreen(),
                    ),
                  );
                });
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }
}
