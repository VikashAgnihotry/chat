import 'package:flutter/material.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

void main() {
  runApp(const SecureChatApp());
}

// Main application widget
class SecureChatApp extends StatelessWidget {
  const SecureChatApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Secure Chat',
      theme: ThemeData(
        primarySwatch: Colors.teal,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      debugShowCheckedModeBanner: false,
      home: const ChatListScreen(),
    );
  }
}

// --- Data Models (for demonstration) ---

// Represents a single message
class Message {
  final String text;
  final bool isSentByMe;
  final DateTime timestamp;

  Message({required this.text, required this.isSentByMe, required this.timestamp});
}

// Represents a single chat conversation
class Chat {
  final String name;
  final String lastMessage;
  final String avatarUrl;
  final DateTime timestamp;

  Chat({
    required this.name,
    required this.lastMessage,
    required this.avatarUrl,
    required this.timestamp,
  });
}

// --- Screens ---

// Displays the list of all chat conversations
class ChatListScreen extends StatefulWidget {
  const ChatListScreen({super.key});

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  // Mock data for the list of chats
  final List<Chat> chats = [
    Chat(
        name: 'Alice',
        lastMessage: 'See you tomorrow!',
        avatarUrl: 'https://placehold.co/100x100/A8DADC/333333?text=A',
        timestamp: DateTime.now().subtract(const Duration(minutes: 5))),
    Chat(
        name: 'Bob',
        lastMessage: 'Okay, sounds good.',
        avatarUrl: 'https://placehold.co/100x100/F1FAEE/333333?text=B',
        timestamp: DateTime.now().subtract(const Duration(hours: 1))),
    Chat(
        name: 'Project Group',
        lastMessage: 'Don\'t forget the meeting at 3 PM.',
        avatarUrl: 'https://placehold.co/100x100/457B9D/FFFFFF?text=PG',
        timestamp: DateTime.now().subtract(const Duration(hours: 3))),
    Chat(
        name: 'Charlie',
        lastMessage: 'Photo',
        avatarUrl: 'https://placehold.co/100x100/1D3557/FFFFFF?text=C',
        timestamp: DateTime.now().subtract(const Duration(days: 1))),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Chats'),
        actions: [
          IconButton(icon: const Icon(Icons.search), onPressed: () {}),
          IconButton(icon: const Icon(Icons.more_vert), onPressed: () {}),
        ],
      ),
      body: ListView.builder(
        itemCount: chats.length,
        itemBuilder: (context, index) {
          final chat = chats[index];
          return ListTile(
            leading: CircleAvatar(
              backgroundImage: NetworkImage(chat.avatarUrl),
              onBackgroundImageError: (exception, stackTrace) {}, // Handle image load errors
            ),
            title: Text(chat.name),
            subtitle: Text(chat.lastMessage),
            trailing: Text(
              '${chat.timestamp.hour}:${chat.timestamp.minute.toString().padLeft(2, '0')}',
            ),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => ConversationScreen(chat: chat),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          // Action for new chat
        },
        child: const Icon(Icons.chat),
      ),
    );
  }
}

// Displays the messages within a single conversation
class ConversationScreen extends StatefulWidget {
  final Chat chat;
  const ConversationScreen({super.key, required this.chat});

  @override
  State<ConversationScreen> createState() => _ConversationScreenState();
}

class _ConversationScreenState extends State<ConversationScreen> {
  final TextEditingController _messageController = TextEditingController();
  final List<Message> _messages = [];
  late io.Socket _socket;

  @override
  void initState() {
    super.initState();
    // Initialize with some mock data
    _messages.addAll([
      Message(text: 'Hi there!', isSentByMe: false, timestamp: DateTime.now().subtract(const Duration(minutes: 10))),
      Message(text: 'Hello! How are you?', isSentByMe: true, timestamp: DateTime.now().subtract(const Duration(minutes: 9))),
    ]);
    _connectToServer();
  }

  void _connectToServer() {
    try {
      // IMPORTANT: for Android emulator, use 10.0.2.2 to connect to localhost of the host machine.
      // For physical devices, use your computer's local network IP address (e.g., 192.168.1.10).
      _socket = io.io('http://192.168.31.213:3000', <String, dynamic>{
        'transports': ['websocket'],
        'autoConnect': false,
      });

      _socket.connect();

      _socket.onConnect((_) {
        debugPrint('Connected to server: ${_socket.id}');
      });

      // Listen for incoming messages
      _socket.on('receive_message', (data) {
        if (mounted) {
          setState(() {
            _messages.add(Message(
              text: data['text'],
              isSentByMe: false, // Messages received are never from "me"
              timestamp: DateTime.now(),
            ));
          });
        }
      });

      _socket.onDisconnect((_) => debugPrint('Disconnected from server'));
      _socket.onError((err) => debugPrint('Socket Error: $err'));

    } catch (e) {
      debugPrint('Error connecting to socket: $e');
    }
  }

  void _sendMessage() {
    if (_messageController.text.isNotEmpty) {
      final text = _messageController.text;
      _messageController.clear();

      final message = {
        'text': text,
        'senderId': _socket.id // In a real app, this would be a user ID
      };
      // Send the message to the server
      _socket.emit('chat_message', message);

      // Add the message to the local list immediately for a better user experience
      setState(() {
        _messages.add(Message(
          text: text,
          isSentByMe: true,
          timestamp: DateTime.now(),
        ));
      });
    }
  }

  @override
  void dispose() {
    _socket.disconnect(); // Disconnect the socket when the screen is closed
    _messageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.chat.name),
        actions: [
          IconButton(icon: const Icon(Icons.videocam), onPressed: () {}),
          IconButton(icon: const Icon(Icons.call), onPressed: () {}),
          IconButton(icon: const Icon(Icons.more_vert), onPressed: () {}),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              reverse: true, // To show latest messages at the bottom
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                // We display messages in reverse order from the list
                final message = _messages.reversed.toList()[index];
                return MessageBubble(message: message);
              },
            ),
          ),
          _buildMessageComposer(),
        ],
      ),
    );
  }

  // Builds the text input field and send button at the bottom
  Widget _buildMessageComposer() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 12.0),
      color: Colors.white,
      child: Row(
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.grey[200],
                borderRadius: BorderRadius.circular(24.0),
              ),
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(Icons.emoji_emotions_outlined, color: Colors.grey[600]),
                    onPressed: () {},
                  ),
                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      decoration: const InputDecoration(
                        hintText: 'Type a message...',
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.attach_file, color: Colors.grey[600]),
                    onPressed: () {},
                  ),
                  IconButton(
                    icon: Icon(Icons.camera_alt, color: Colors.grey[600]),
                    onPressed: () {},
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8.0),
          FloatingActionButton(
            mini: true,
            onPressed: _sendMessage,
            child: const Icon(Icons.send),
          ),
        ],
      ),
    );
  }
}

// A widget to display a single chat message bubble
class MessageBubble extends StatelessWidget {
  final Message message;

  const MessageBubble({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 6.0),
      alignment: message.isSentByMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
        decoration: BoxDecoration(
            color: message.isSentByMe ? const Color(0xFFDCF8C6) : Colors.white,
            borderRadius: BorderRadius.circular(12.0),
            boxShadow: [
              BoxShadow(
                color: Colors.grey.withValues(),
                spreadRadius: 1,
                blurRadius: 2,
                offset: const Offset(0, 1),
              )
            ]
        ),
        child: Text(
          message.text,
          style: const TextStyle(fontSize: 16.0),
        ),
      ),
    );
  }
}

