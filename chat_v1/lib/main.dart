import 'package:flutter/material.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'dart:async';
import 'dart:convert'; // Needed for base64 encoding
import 'dart:io'; // Needed for File operations
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

// --- SERVICES ---

class EncryptionService {
  static final EncryptionService instance = EncryptionService._internal();
  factory EncryptionService() => instance;
  EncryptionService._internal();

  final _key = encrypt.Key.fromUtf8('my32lengthsupersecretnooneknows!');
  final _iv = encrypt.IV.fromUtf8('my16lengthiv!!!!');
  late final encrypt.Encrypter _encrypter;

  void initialize() {
    _encrypter = encrypt.Encrypter(encrypt.AES(_key, mode: encrypt.AESMode.cbc));
  }

  String encryptText(String plainText) {
    final encrypted = _encrypter.encrypt(plainText, iv: _iv);
    return encrypted.base64;
  }

  String decryptText(String encryptedText) {
    try {
      final encryptedData = encrypt.Encrypted.fromBase64(encryptedText);
      return _encrypter.decrypt(encryptedData, iv: _iv);
    } catch (e) {
      debugPrint("Decryption failed: $e");
      return "Unable to decrypt message";
    }
  }
}

class SocketService {
  static final SocketService _instance = SocketService._internal();
  factory SocketService() => _instance;
  SocketService._internal();

  io.Socket? _socket;
  final StreamController<Message> _messageController = StreamController<Message>.broadcast();
  Stream<Message> get messageStream => _messageController.stream;

  void connect(String userId) {
    if (_socket != null && _socket!.connected) _socket!.disconnect();

    try {
      _socket = io.io('http://192.168.31.213:3000', <String, dynamic>{
        'transports': ['websocket'],
        'autoConnect': false,
      });

      _socket!.connect();
      _socket!.onConnect((_) {
        debugPrint('Socket connected: ${_socket!.id}');
        _socket!.emit('register_user', userId);
      });

      _socket!.on('receive_message', (data) async { // Make async to handle file saving
        String messageText = data['text'];
        MessageType messageType = MessageType.values.firstWhere(
                (e) => e.toString() == data['type'],
            orElse: () => MessageType.text
        );

        // If it's an image, decrypt, decode, and save it
        if (messageType == MessageType.image) {
          final decryptedBase64 = EncryptionService.instance.decryptText(data['text']);
          final imageBytes = base64Decode(decryptedBase64);
          final directory = await getApplicationDocumentsDirectory();
          final fileName = '${DateTime.now().millisecondsSinceEpoch}.png';
          final filePath = '${directory.path}/$fileName';
          final file = File(filePath);
          await file.writeAsBytes(imageBytes);
          messageText = filePath; // The "text" of the message is now the local file path
        } else {
          messageText = EncryptionService.instance.decryptText(data['text']);
        }

        final receivedMessage = Message(
          text: messageText,
          isSentByMe: false,
          timestamp: DateTime.now(),
          chatName: data['senderId'],
          type: messageType,
        );
        _messageController.add(receivedMessage);
      });

      _socket!.onDisconnect((_) => debugPrint('Socket disconnected'));
      _socket!.onError((err) => debugPrint('Socket Error: $err'));
    } catch (e) {
      debugPrint('Error in SocketService: $e');
    }
  }

  io.Socket? get socket => _socket;

  void dispose() {
    _messageController.close();
    _socket?.disconnect();
  }
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  EncryptionService.instance.initialize();
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
      home: const LoginScreen(),
    );
  }
}

// --- DATA MODELS ---

enum MessageType { text, image }

class Message {
  final String text; // For text messages, this is the content. For images, it's the file path.
  final bool isSentByMe;
  final DateTime timestamp;
  final String chatName;
  final MessageType type;

  Message({
    required this.text,
    required this.isSentByMe,
    required this.timestamp,
    required this.chatName,
    this.type = MessageType.text,
  });

  Map<String, dynamic> toMap() {
    return {
      'text': text,
      'isSentByMe': isSentByMe ? 1 : 0,
      'timestamp': timestamp.toIso8601String(),
      'chatName': chatName,
      'type': type.toString(),
    };
  }
}

class Chat {
  String name;
  String lastMessage;
  String avatarUrl;
  DateTime timestamp;

  Chat({
    required this.name,
    required this.lastMessage,
    required this.avatarUrl,
    required this.timestamp,
  });
}

// --- SCREENS ---

class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  void _login(BuildContext context, String userId) {
    SocketService().connect(userId);
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => ChatListScreen(currentUserId: userId),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Select User')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton(onPressed: () => _login(context, 'Me'), child: const Text('Login as "Me"')),
            const SizedBox(height: 20),
            ElevatedButton(onPressed: () => _login(context, 'Alice'), child: const Text('Login as "Alice"')),
            const SizedBox(height: 20),
            ElevatedButton(onPressed: () => _login(context, 'Bob'), child: const Text('Login as "Bob"')),
          ],
        ),
      ),
    );
  }
}

class ChatListScreen extends StatefulWidget {
  final String currentUserId;
  const ChatListScreen({super.key, required this.currentUserId});

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  final List<Chat> chats = [
    Chat(name: 'Alice', lastMessage: 'See you tomorrow!', avatarUrl: 'https://placehold.co/100x100/A8DADC/333333?text=A', timestamp: DateTime.now().subtract(const Duration(minutes: 5))),
    Chat(name: 'Bob', lastMessage: 'Okay, sounds good.', avatarUrl: 'https://placehold.co/100x100/F1FAEE/333333?text=B', timestamp: DateTime.now().subtract(const Duration(hours: 1))),
    Chat(name: 'Me', lastMessage: 'This is my chat.', avatarUrl: 'https://placehold.co/100x100/E63946/FFFFFF?text=Me', timestamp: DateTime.now().subtract(const Duration(hours: 2))),
  ];
  late StreamSubscription<Message> _messageSubscription;

  @override
  void initState() {
    super.initState();
    _messageSubscription = SocketService().messageStream.listen((message) {
      DatabaseHelper.instance.insertMessage(message);
      final lastMessageText = message.type == MessageType.image ? 'Photo' : message.text;
      _updateChatList(message.chatName, lastMessageText, message.timestamp);
    });
  }

  @override
  void dispose() {
    _messageSubscription.cancel();
    super.dispose();
  }

  void _updateChatList(String chatName, String lastMessage, DateTime timestamp) {
    if (mounted) {
      setState(() {
        final chatIndex = chats.indexWhere((chat) => chat.name == chatName);
        if (chatIndex != -1) {
          final chat = chats[chatIndex];
          chat.lastMessage = lastMessage;
          chat.timestamp = timestamp;
          chats.removeAt(chatIndex);
          chats.insert(0, chat);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final displayedChats = chats.where((chat) => chat.name != widget.currentUserId).toList();
    return Scaffold(
      appBar: AppBar(title: Text('Chats (Logged in as ${widget.currentUserId})')),
      body: ListView.builder(
        itemCount: displayedChats.length,
        itemBuilder: (context, index) {
          final chat = displayedChats[index];
          return ListTile(
            leading: CircleAvatar(backgroundImage: NetworkImage(chat.avatarUrl)),
            title: Text(chat.name),
            subtitle: Text(chat.lastMessage),
            trailing: Text('${chat.timestamp.hour}:${chat.timestamp.minute.toString().padLeft(2, '0')}'),
            onTap: () {
              Navigator.push(context, MaterialPageRoute(builder: (context) => ConversationScreen(chat: chat, currentUserId: widget.currentUserId, onNewMessage: _updateChatList)));
            },
          );
        },
      ),
    );
  }
}

class ConversationScreen extends StatefulWidget {
  final Chat chat;
  final String currentUserId;
  final Function(String chatName, String lastMessage, DateTime timestamp) onNewMessage;

  const ConversationScreen({super.key, required this.chat, required this.currentUserId, required this.onNewMessage});

  @override
  State<ConversationScreen> createState() => _ConversationScreenState();
}

class _ConversationScreenState extends State<ConversationScreen> {
  final TextEditingController _messageController = TextEditingController();
  final List<Message> _messages = [];
  final io.Socket? _socket = SocketService().socket;
  late StreamSubscription<Message> _messageSubscription;
  bool _isRecipientTyping = false;
  Timer? _typingTimer;
  late String _recipientUserId;

  @override
  void initState() {
    super.initState();
    _recipientUserId = widget.chat.name;
    _loadMessages();
    _messageSubscription = SocketService().messageStream.listen((message) {
      if (message.chatName == _recipientUserId && mounted) setState(() => _messages.add(message));
    });
    _socket?.on('typing', (data) {
      if (data['senderId'] == _recipientUserId && mounted) setState(() => _isRecipientTyping = true);
    });
    _socket?.on('stop_typing', (data) {
      if (data['senderId'] == _recipientUserId && mounted) setState(() => _isRecipientTyping = false);
    });
  }

  Future<void> _loadMessages() async {
    final loadedMessages = await DatabaseHelper.instance.getMessages(_recipientUserId);
    if (mounted) setState(() => _messages.addAll(loadedMessages));
  }

  Future<void> _sendImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);

    if (pickedFile != null && _socket != null) {
      final imageFile = File(pickedFile.path);
      final imageBytes = await imageFile.readAsBytes();
      final base64Image = base64Encode(imageBytes);

      final encryptedImage = EncryptionService.instance.encryptText(base64Image);

      final messageData = {
        'text': encryptedImage,
        'senderId': widget.currentUserId,
        'recipientId': _recipientUserId,
        'type': MessageType.image.toString(),
      };
      _socket!.emit('chat_message', messageData);

      final sentMessage = Message(
        text: pickedFile.path,
        isSentByMe: true,
        timestamp: DateTime.now(),
        chatName: _recipientUserId,
        type: MessageType.image,
      );
      await DatabaseHelper.instance.insertMessage(sentMessage);
      widget.onNewMessage(widget.chat.name, 'Photo', sentMessage.timestamp);
      setState(() => _messages.add(sentMessage));
    }
  }

  void _sendMessage() {
    if (_messageController.text.isNotEmpty && _socket != null) {
      final text = _messageController.text;
      _messageController.clear();
      _typingTimer?.cancel();
      _socket!.emit('stop_typing', {'senderId': widget.currentUserId, 'recipientId': _recipientUserId});
      final encryptedText = EncryptionService.instance.encryptText(text);

      final messageData = {
        'text': encryptedText,
        'senderId': widget.currentUserId,
        'recipientId': _recipientUserId,
        'type': MessageType.text.toString(),
      };
      _socket!.emit('chat_message', messageData);

      final sentMessage = Message(
        text: text,
        isSentByMe: true,
        timestamp: DateTime.now(),
        chatName: _recipientUserId,
      );
      DatabaseHelper.instance.insertMessage(sentMessage);
      widget.onNewMessage(widget.chat.name, text, sentMessage.timestamp);
      setState(() => _messages.add(sentMessage));
    }
  }

  void _handleTyping(String text) {
    if (_socket != null) {
      if (_typingTimer == null || !_typingTimer!.isActive) {
        _socket!.emit('typing', {'senderId': widget.currentUserId, 'recipientId': _recipientUserId});
      }
      _typingTimer?.cancel();
      _typingTimer = Timer(const Duration(seconds: 2), () {
        _socket!.emit('stop_typing', {'senderId': widget.currentUserId, 'recipientId': _recipientUserId});
      });
    }
  }

  @override
  void dispose() {
    _messageController.dispose();
    _typingTimer?.cancel();
    _messageSubscription.cancel();
    _socket?.off('typing');
    _socket?.off('stop_typing');
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.chat.name),
            if (_isRecipientTyping) const Text('typing...', style: TextStyle(fontSize: 12.0, fontStyle: FontStyle.italic, color: Colors.white70)),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              reverse: true,
              itemCount: _messages.length,
              itemBuilder: (context, index) {
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

  Widget _buildMessageComposer() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 12.0),
      color: Colors.white,
      child: Row(
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(color: Colors.grey[200], borderRadius: BorderRadius.circular(24.0)),
              child: Row(
                children: [
                  IconButton(icon: Icon(Icons.emoji_emotions_outlined, color: Colors.grey[600]), onPressed: () {}),
                  Expanded(child: TextField(controller: _messageController, onChanged: _handleTyping, decoration: const InputDecoration(hintText: 'Type a message...', border: InputBorder.none))),
                  IconButton(icon: Icon(Icons.attach_file, color: Colors.grey[600]), onPressed: _sendImage),
                  IconButton(icon: Icon(Icons.camera_alt, color: Colors.grey[600]), onPressed: _sendImage),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8.0),
          FloatingActionButton(mini: true, onPressed: _sendMessage, child: const Icon(Icons.send)),
        ],
      ),
    );
  }
}

class MessageBubble extends StatelessWidget {
  final Message message;
  const MessageBubble({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    final messageContent = message.type == MessageType.image
        ? Image.file(
      File(message.text),
      width: 200,
      fit: BoxFit.cover,
    )
        : Text(
      message.text,
      style: const TextStyle(fontSize: 16.0),
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 6.0),
      alignment: message.isSentByMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.all(8.0),
        decoration: BoxDecoration(
            color: message.isSentByMe ? const Color(0xFFDCF8C6) : Colors.white,
            borderRadius: BorderRadius.circular(12.0),
            boxShadow: [BoxShadow(color: Colors.grey.withOpacity(0.2), spreadRadius: 1, blurRadius: 2, offset: const Offset(0, 1))]),
        child: messageContent,
      ),
    );
  }
}

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;
  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('chat_app.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);
    return await openDatabase(path, version: 2, onCreate: _createDB, onUpgrade: _upgradeDB);
  }

  Future _upgradeDB(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute("ALTER TABLE messages ADD COLUMN type TEXT DEFAULT 'MessageType.text'");
    }
  }

  Future _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE messages(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        text TEXT NOT NULL,
        isSentByMe INTEGER NOT NULL,
        timestamp TEXT NOT NULL,
        chatName TEXT NOT NULL,
        type TEXT NOT NULL
      )
    ''');
  }

  Future<void> insertMessage(Message message) async {
    final db = await instance.database;
    await db.insert('messages', message.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Message>> getMessages(String chatName) async {
    final db = await instance.database;
    final maps = await db.query('messages', where: 'chatName = ?', whereArgs: [chatName], orderBy: 'timestamp ASC');
    if (maps.isEmpty) return [];

    return List.generate(maps.length, (i) {
      return Message(
        text: maps[i]['text'] as String,
        isSentByMe: (maps[i]['isSentByMe'] as int) == 1,
        timestamp: DateTime.parse(maps[i]['timestamp'] as String),
        chatName: maps[i]['chatName'] as String,
        type: MessageType.values.firstWhere(
                (e) => e.toString() == maps[i]['type'],
            orElse: () => MessageType.text
        ),
      );
    });
  }
}

