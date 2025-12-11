// lib/chat_screen_with_context_menu.dart
//
// A complete ChatScreen implementation with long-press context menu functionality.
//
// Features:
// - MessageBubble widget for displaying individual messages
// - Long-press context menu with: Reply, Copy, Pin, Forward, Delete, Select
// - Copy functionality using Clipboard.setData
// - Multi-select mode for bulk operations
//
// Usage:
//   Navigator.push(
//     context,
//     MaterialPageRoute(builder: (context) => const ChatScreen()),
//   );
//
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Message model for the chat screen
class ChatMessage {
  final String id;
  final String content;
  final String senderId;
  final DateTime timestamp;
  final bool isSentByMe;

  ChatMessage({
    required this.id,
    required this.content,
    required this.senderId,
    required this.timestamp,
    required this.isSentByMe,
  });
}

/// Message Bubble Widget
class MessageBubble extends StatelessWidget {
  final String content;
  final bool isSentByMe;
  final String timestamp;

  const MessageBubble({
    super.key,
    required this.content,
    required this.isSentByMe,
    required this.timestamp,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isSentByMe
              ? [
                  const Color(0xFF3A7BD5),
                  const Color(0xFF00D2FF),
                ]
              : [
                  const Color(0xFF00C853),
                  const Color(0xFFB2FF59),
                ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: isSentByMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            content,
            style: const TextStyle(
              fontSize: 15,
              color: Colors.white,
            ),
            textAlign: isSentByMe ? TextAlign.right : TextAlign.left,
          ),
          const SizedBox(height: 4),
          Text(
            timestamp,
            style: const TextStyle(
              fontSize: 11,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

/// Chat Screen with Long-Press Context Menu
class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  // Sample messages for demonstration
  final List<ChatMessage> _messages = [
    ChatMessage(
      id: '1',
      content: 'Hello! How are you doing today?',
      senderId: 'user1',
      timestamp: DateTime.now().subtract(const Duration(minutes: 10)),
      isSentByMe: false,
    ),
    ChatMessage(
      id: '2',
      content: 'I\'m doing great! Thanks for asking. How about you?',
      senderId: 'me',
      timestamp: DateTime.now().subtract(const Duration(minutes: 9)),
      isSentByMe: true,
    ),
    ChatMessage(
      id: '3',
      content: 'I\'m good too! Just working on some Flutter projects.',
      senderId: 'user1',
      timestamp: DateTime.now().subtract(const Duration(minutes: 8)),
      isSentByMe: false,
    ),
    ChatMessage(
      id: '4',
      content: 'That sounds interesting! What kind of projects?',
      senderId: 'me',
      timestamp: DateTime.now().subtract(const Duration(minutes: 7)),
      isSentByMe: true,
    ),
    ChatMessage(
      id: '5',
      content: 'Building a chat app with context menus and modern UI features.',
      senderId: 'user1',
      timestamp: DateTime.now().subtract(const Duration(minutes: 6)),
      isSentByMe: false,
    ),
  ];

  final ScrollController _scrollController = ScrollController();
  final TextEditingController _messageController = TextEditingController();
  
  // Track selected messages for multi-select mode
  final Set<String> _selectedMessageIds = <String>{};
  bool _isSelectMode = false;

  @override
  void dispose() {
    _scrollController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  /// Formats timestamp to a readable string
  String _formatTimestamp(DateTime timestamp) {
    final now = DateTime.now();
    final difference = now.difference(timestamp);

    if (difference.inDays > 0) {
      return '${timestamp.day}/${timestamp.month} ${timestamp.hour}:${timestamp.minute.toString().padLeft(2, '0')}';
    } else if (difference.inHours > 0) {
      return '${timestamp.hour}:${timestamp.minute.toString().padLeft(2, '0')}';
    } else {
      return '${timestamp.minute.toString().padLeft(2, '0')}:${timestamp.second.toString().padLeft(2, '0')}';
    }
  }

  /// Shows the context menu on long press
  Future<void> _showContextMenu(
    BuildContext context,
    ChatMessage message,
    Offset tapPosition,
  ) async {
    final RenderBox overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    
    // Show menu positioned adjacent to the tap position
    // showMenu will automatically adjust if the menu goes off-screen
    final String? selectedAction = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(tapPosition.dx, tapPosition.dy, tapPosition.dx, tapPosition.dy),
        Rect.fromLTWH(0, 0, overlay.size.width, overlay.size.height),
      ),
      items: [
        const PopupMenuItem<String>(
          value: 'reply',
          child: ListTile(
            leading: Icon(Icons.reply, size: 20),
            title: Text('Reply'),
            contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 0),
            dense: true,
          ),
        ),
        const PopupMenuItem<String>(
          value: 'copy',
          child: ListTile(
            leading: Icon(Icons.copy, size: 20),
            title: Text('Copy'),
            contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 0),
            dense: true,
          ),
        ),
        const PopupMenuItem<String>(
          value: 'pin',
          child: ListTile(
            leading: Icon(Icons.push_pin, size: 20),
            title: Text('Pin'),
            contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 0),
            dense: true,
          ),
        ),
        const PopupMenuItem<String>(
          value: 'forward',
          child: ListTile(
            leading: Icon(Icons.forward, size: 20),
            title: Text('Forward'),
            contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 0),
            dense: true,
          ),
        ),
        const PopupMenuItem<String>(
          value: 'delete',
          child: ListTile(
            leading: Icon(Icons.delete_outline, size: 20, color: Colors.red),
            title: Text('Delete', style: TextStyle(color: Colors.red)),
            contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 0),
            dense: true,
          ),
        ),
        const PopupMenuItem<String>(
          value: 'select',
          child: ListTile(
            leading: Icon(Icons.check_circle_outline, size: 20),
            title: Text('Select'),
            contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 0),
            dense: true,
          ),
        ),
      ],
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
      ),
      elevation: 8,
    );

    // Handle the selected action
    if (selectedAction != null && mounted) {
      _handleMenuAction(selectedAction, message);
    }
  }

  /// Handles menu action selection
  void _handleMenuAction(String action, ChatMessage message) {
    switch (action) {
      case 'reply':
        _handleReply(message);
        break;
      case 'copy':
        _handleCopy(message);
        break;
      case 'pin':
        _handlePin(message);
        break;
      case 'forward':
        _handleForward(message);
        break;
      case 'delete':
        _handleDelete(message);
        break;
      case 'select':
        _handleSelect(message);
        break;
    }
  }

  /// Handle Reply action
  void _handleReply(ChatMessage message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Replying to: ${message.content}'),
        duration: const Duration(seconds: 2),
      ),
    );
    // TODO: Implement reply functionality (e.g., show reply preview in composer)
  }

  /// Handle Copy action - Copies message content to clipboard
  void _handleCopy(ChatMessage message) {
    Clipboard.setData(ClipboardData(text: message.content));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Message copied to clipboard'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  /// Handle Pin action
  void _handlePin(ChatMessage message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Pinned: ${message.content.substring(0, message.content.length > 30 ? 30 : message.content.length)}...'),
        duration: const Duration(seconds: 2),
      ),
    );
    // TODO: Implement pin functionality
  }

  /// Handle Forward action
  void _handleForward(ChatMessage message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Forwarding: ${message.content.substring(0, message.content.length > 30 ? 30 : message.content.length)}...'),
        duration: const Duration(seconds: 2),
      ),
    );
    // TODO: Implement forward functionality
  }

  /// Handle Delete action
  void _handleDelete(ChatMessage message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Message'),
        content: const Text('Are you sure you want to delete this message?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              setState(() {
                _messages.removeWhere((m) => m.id == message.id);
              });
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Message deleted'),
                  duration: Duration(seconds: 2),
                ),
              );
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  /// Handle Select action - Enters multi-select mode
  void _handleSelect(ChatMessage message) {
    setState(() {
      _isSelectMode = true;
      if (_selectedMessageIds.contains(message.id)) {
        _selectedMessageIds.remove(message.id);
      } else {
        _selectedMessageIds.add(message.id);
      }
      // Exit select mode if no messages are selected
      if (_selectedMessageIds.isEmpty) {
        _isSelectMode = false;
      }
    });
  }

  /// Sends a new message
  void _sendMessage() {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    setState(() {
      _messages.add(
        ChatMessage(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          content: text,
          senderId: 'me',
          timestamp: DateTime.now(),
          isSentByMe: true,
        ),
      );
    });

    _messageController.clear();
    
    // Scroll to bottom after sending
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Chat'),
        actions: [
          if (_isSelectMode)
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () {
                setState(() {
                  _isSelectMode = false;
                  _selectedMessageIds.clear();
                });
              },
            ),
          if (_isSelectMode && _selectedMessageIds.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              color: Colors.red,
              onPressed: () {
                setState(() {
                  _messages.removeWhere((m) => _selectedMessageIds.contains(m.id));
                  _selectedMessageIds.clear();
                  _isSelectMode = false;
                });
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Messages deleted')),
                );
              },
            ),
        ],
      ),
      body: Column(
        children: [
          // Messages list
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final message = _messages[index];
                final isSelected = _selectedMessageIds.contains(message.id);

                return GestureDetector(
                  onLongPressStart: (LongPressStartDetails details) {
                    if (!_isSelectMode) {
                      // Show context menu at the long-press position
                      _showContextMenu(context, message, details.globalPosition);
                    } else {
                      // In select mode, toggle selection
                      _handleSelect(message);
                    }
                  },
                  onTap: () {
                    if (_isSelectMode) {
                      _handleSelect(message);
                    }
                  },
                  child: Container(
                    color: isSelected ? Colors.blue.withOpacity(0.1) : Colors.transparent,
                    child: Row(
                      mainAxisAlignment: message.isSentByMe
                          ? MainAxisAlignment.end
                          : MainAxisAlignment.start,
                      children: [
                        if (_isSelectMode && !message.isSentByMe)
                          Checkbox(
                            value: isSelected,
                            onChanged: (value) {
                              setState(() {
                                if (value == true) {
                                  _selectedMessageIds.add(message.id);
                                } else {
                                  _selectedMessageIds.remove(message.id);
                                  if (_selectedMessageIds.isEmpty) {
                                    _isSelectMode = false;
                                  }
                                }
                              });
                            },
                          ),
                        MessageBubble(
                          content: message.content,
                          isSentByMe: message.isSentByMe,
                          timestamp: _formatTimestamp(message.timestamp),
                        ),
                        if (_isSelectMode && message.isSentByMe)
                          Checkbox(
                            value: isSelected,
                            onChanged: (value) {
                              setState(() {
                                if (value == true) {
                                  _selectedMessageIds.add(message.id);
                                } else {
                                  _selectedMessageIds.remove(message.id);
                                  if (_selectedMessageIds.isEmpty) {
                                    _isSelectMode = false;
                                  }
                                }
                              });
                            },
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          // Message input field
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Theme.of(context).scaffoldBackgroundColor,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 4,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    decoration: InputDecoration(
                      hintText: 'Type a message...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                    ),
                    maxLines: null,
                    textCapitalization: TextCapitalization.sentences,
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.send),
                  onPressed: _sendMessage,
                  color: Theme.of(context).primaryColor,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
