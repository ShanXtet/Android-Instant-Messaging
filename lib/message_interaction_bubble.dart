// lib/message_interaction_bubble.dart
//
// A complete Flutter implementation for a chat message bubble component
// with reaction picker and context menu on long press.
//
// Features:
// - Message bubble with customizable text and styling
// - Long press to show reaction emoji picker (floating above bubble)
// - Long press to show context menu (Reply, Copy, Unsend, Pin, Forward, Delete, Select)
// - Clean, modular code structure

import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Main message bubble widget with interaction capabilities
class MessageInteractionBubble extends StatefulWidget {
  final String message;
  final bool isSentByMe;
  final Color? bubbleColor;
  final Function(String)? onReactionSelected;
  final Function(String)? onActionSelected;
  final bool shouldBlur; // If true, this message will be blurred (when another message is selected)
  final VoidCallback? onLongPressStart; // Callback when this message is long-pressed

  const MessageInteractionBubble({
    super.key,
    required this.message,
    this.isSentByMe = true,
    this.bubbleColor,
    this.onReactionSelected,
    this.onActionSelected,
    this.shouldBlur = false,
    this.onLongPressStart,
  });

  @override
  State<MessageInteractionBubble> createState() => _MessageInteractionBubbleState();
}

class _MessageInteractionBubbleState extends State<MessageInteractionBubble>
    with SingleTickerProviderStateMixin {
  OverlayEntry? _reactionOverlay;
  final GlobalKey _bubbleKey = GlobalKey();
  late AnimationController _reactionAnimationController;
  late Animation<double> _reactionScaleAnimation;
  late Animation<double> _reactionOpacityAnimation;
  bool _isLongPressed = false;

  // Available reaction emojis (matching standard messaging apps)
  final List<String> _reactions = ['👍', '❤️', '😂', '😐', '😢', '😡'];

  @override
  void initState() {
    super.initState();
    _reactionAnimationController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _reactionScaleAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _reactionAnimationController,
        curve: Curves.elasticOut,
      ),
    );
    _reactionOpacityAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _reactionAnimationController,
        curve: Curves.easeIn,
      ),
    );
  }

  @override
  void dispose() {
    _removeReactionOverlay();
    _reactionAnimationController.dispose();
    super.dispose();
  }

  /// Shows the reaction picker overlay above the message bubble
  void _showReactionPicker() {
    if (_reactionOverlay != null) return;

    final RenderBox? renderBox =
        _bubbleKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    final position = renderBox.localToGlobal(Offset.zero);
    final size = renderBox.size;

    // Calculate position for reaction picker (above and slightly to the left of bubble)
    final overlayWidth = MediaQuery.of(context).size.width;
    final bubbleCenterX = position.dx + size.width / 2;
    final reactionPickerY = position.dy - 75; // Position above the bubble

    _reactionOverlay = OverlayEntry(
      builder: (context) => Positioned(
        left: bubbleCenterX - 140, // Position slightly to the left
        top: reactionPickerY,
        child: GestureDetector(
          onTap: () => _removeReactionOverlay(),
          child: Material(
            color: Colors.transparent,
            child: IgnorePointer(
              ignoring: false,
              child: ScaleTransition(
                scale: _reactionScaleAnimation,
                child: FadeTransition(
                  opacity: _reactionOpacityAnimation,
                  child: _ReactionPicker(
                    reactions: _reactions,
                    onReactionSelected: (reaction) {
                      widget.onReactionSelected?.call(reaction);
                      _removeReactionOverlay();
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    Overlay.of(context).insert(_reactionOverlay!);
    _reactionAnimationController.forward();
  }

  /// Removes the reaction picker overlay
  void _removeReactionOverlay() {
    if (_reactionOverlay != null) {
      _reactionAnimationController.reverse().then((_) {
        _reactionOverlay?.remove();
        _reactionOverlay = null;
        // Remove highlight when overlay is removed
        if (mounted) {
          setState(() {
            _isLongPressed = false;
          });
        }
      });
    }
  }

  /// Shows the context menu with action options
  Future<void> _showContextMenu(Offset tapPosition) async {
    final RenderBox overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;

    // Position menu below and to the left of the message bubble
    final RenderBox? renderBox =
        _bubbleKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox != null) {
      final position = renderBox.localToGlobal(Offset.zero);
      final size = renderBox.size;
      // Position menu below and slightly to the left
      tapPosition = Offset(position.dx - 20, position.dy + size.height + 8);
    }

    final String? action = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(tapPosition.dx, tapPosition.dy, 0, 0),
        Rect.fromLTWH(0, 0, overlay.size.width, overlay.size.height),
      ),
      items: [
        const PopupMenuItem<String>(
          value: 'reply',
          child: ListTile(
            leading: Icon(Icons.reply, size: 20, color: Colors.black87),
            title: Text('Reply', style: TextStyle(color: Colors.black87)),
            contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            dense: true,
          ),
        ),
        const PopupMenuItem<String>(
          value: 'forward',
          child: ListTile(
            leading: Icon(Icons.forward, size: 20, color: Colors.black87),
            title: Text('Forward', style: TextStyle(color: Colors.black87)),
            contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            dense: true,
          ),
        ),
        const PopupMenuItem<String>(
          value: 'copy',
          child: ListTile(
            leading: Icon(Icons.content_copy, size: 20, color: Colors.black87),
            title: Text('Copy', style: TextStyle(color: Colors.black87)),
            contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            dense: true,
          ),
        ),
        const PopupMenuItem<String>(
          value: 'star',
          child: ListTile(
            leading: Icon(Icons.star_border, size: 20, color: Colors.black87),
            title: Text('Star', style: TextStyle(color: Colors.black87)),
            contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            dense: true,
          ),
        ),
        const PopupMenuItem<String>(
          value: 'delete',
          child: ListTile(
            leading: Icon(Icons.delete_outline, size: 20, color: Colors.black87),
            title: Text('Delete', style: TextStyle(color: Colors.black87)),
            contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            dense: true,
          ),
        ),
        const PopupMenuItem<String>(
          value: 'select',
          child: ListTile(
            leading: Icon(Icons.check_box_outline_blank, size: 20, color: Colors.black87),
            title: Text('Select more', style: TextStyle(color: Colors.black87)),
            contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            dense: true,
          ),
        ),
        const PopupMenuItem<String>(
          value: 'info',
          child: ListTile(
            leading: Icon(Icons.info_outline, size: 20, color: Colors.black87),
            title: Text('Info', style: TextStyle(color: Colors.black87)),
            contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            dense: true,
          ),
        ),
      ],
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      color: Colors.white,
      elevation: 8,
    );

    if (action != null) {
      widget.onActionSelected?.call(action);
    }
  }

  /// Handles long press event
  void _handleLongPress(LongPressStartDetails details) {
    // Notify parent that this message is being long-pressed
    widget.onLongPressStart?.call();
    
    // Highlight this message
    setState(() {
      _isLongPressed = true;
    });
    
    // Show both reaction picker and context menu
    _showReactionPicker();
    _showContextMenu(details.globalPosition).then((_) {
      // Remove highlight when menu closes
      if (mounted) {
        setState(() {
          _isLongPressed = false;
        });
      }
    });
  }
  
  /// Handles long press end to remove highlight if menu wasn't shown
  void _handleLongPressEnd() {
    // Only remove highlight if overlay is not showing (menu closed)
    if (_reactionOverlay == null && mounted) {
      setState(() {
        _isLongPressed = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final defaultColor = widget.isSentByMe
        ? const Color(0xFF3A7BD5)
        : const Color(0xFF00C853);

    return GestureDetector(
      key: _bubbleKey,
      onLongPressStart: _handleLongPress,
      onLongPressEnd: _handleLongPressEnd,
      onTap: _removeReactionOverlay,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        child: widget.shouldBlur
            ? ClipRRect(
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(18),
                  topRight: const Radius.circular(18),
                  bottomLeft: Radius.circular(widget.isSentByMe ? 18 : 4),
                  bottomRight: Radius.circular(widget.isSentByMe ? 4 : 18),
                ),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
                  child: Opacity(
                    opacity: 0.3,
                    child: _buildBubbleContent(defaultColor),
                  ),
                ),
              )
            : _buildBubbleContent(defaultColor),
      ),
    );
  }

  Widget _buildBubbleContent(Color defaultColor) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width * 0.75,
      ),
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      decoration: BoxDecoration(
        color: widget.bubbleColor ?? defaultColor,
        border: _isLongPressed
            ? Border.all(
                color: Theme.of(context).colorScheme.primary.withOpacity(0.6),
                width: 2.5,
              )
            : null,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(18),
          topRight: const Radius.circular(18),
          bottomLeft: Radius.circular(widget.isSentByMe ? 18 : 4),
          bottomRight: Radius.circular(widget.isSentByMe ? 4 : 18),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 4,
            spreadRadius: 0,
            offset: const Offset(0, 2),
          ),
          // Add glow effect when long pressed
          if (_isLongPressed)
            BoxShadow(
              color: Theme.of(context).colorScheme.primary.withOpacity(0.4),
              blurRadius: 12,
              spreadRadius: 2,
              offset: const Offset(0, 0),
            ),
        ],
      ),
      child: Text(
        widget.message,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 15,
          height: 1.4,
        ),
      ),
    );
  }
}

/// Reaction picker widget matching the image design
class _ReactionPicker extends StatelessWidget {
  final List<String> reactions;
  final Function(String) onReactionSelected;

  const _ReactionPicker({
    required this.reactions,
    required this.onReactionSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(50), // Heavily rounded pill shape
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            blurRadius: 8,
            spreadRadius: 1,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // "Tap and hold to super react" text
          Text(
            'Tap and hold to super react',
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey[600],
              fontWeight: FontWeight.w400,
            ),
          ),
          const SizedBox(height: 8),
          // Reaction emojis row
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ...reactions.map((reaction) {
                return GestureDetector(
                  onTap: () => onReactionSelected(reaction),
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    padding: const EdgeInsets.all(4),
                    child: Text(
                      reaction,
                      style: const TextStyle(fontSize: 28),
                    ),
                  ),
                );
              }),
              // Plus icon for more reactions
              GestureDetector(
                onTap: () {
                  // Handle more reactions
                },
                child: Container(
                  margin: const EdgeInsets.only(left: 8),
                  padding: const EdgeInsets.all(4),
                  child: Icon(
                    Icons.add_circle_outline,
                    size: 24,
                    color: Colors.grey[600],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Example usage widget with blur functionality
class MessageBubbleExample extends StatefulWidget {
  const MessageBubbleExample({super.key});

  @override
  State<MessageBubbleExample> createState() => _MessageBubbleExampleState();
}

class _MessageBubbleExampleState extends State<MessageBubbleExample> {
  int? _selectedMessageIndex;

  void _handleMessageLongPress(int index) {
    setState(() {
      _selectedMessageIndex = index;
    });
  }

  void _handleMenuClose() {
    setState(() {
      _selectedMessageIndex = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Message Bubble Example'),
        backgroundColor: Colors.blue,
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.purple.shade300,
              Colors.purple.shade600,
            ],
          ),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Example sent message
              MessageInteractionBubble(
                message: 'Hey, have you been keeping up with the whole cryptocurrency craze?',
                isSentByMe: true,
                shouldBlur: _selectedMessageIndex != null && _selectedMessageIndex != 0,
                onLongPressStart: () => _handleMessageLongPress(0),
                onReactionSelected: (reaction) {
                  _handleMenuClose();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Selected reaction: $reaction'),
                      duration: const Duration(seconds: 1),
                    ),
                  );
                },
                onActionSelected: (action) {
                  _handleMenuClose();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Selected action: $action'),
                      duration: const Duration(seconds: 1),
                    ),
                  );
                  
                  // Handle specific actions
                  if (action == 'copy') {
                    Clipboard.setData(ClipboardData(text: 'Hey, have you been keeping up with the whole cryptocurrency craze?'));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Message copied to clipboard')),
                    );
                  }
                },
              ),
              const SizedBox(height: 20),
              // Example received message
              MessageInteractionBubble(
                message: 'Yes, I\'ve been following it closely!',
                isSentByMe: false,
                shouldBlur: _selectedMessageIndex != null && _selectedMessageIndex != 1,
                onLongPressStart: () => _handleMessageLongPress(1),
                onReactionSelected: (reaction) {
                  _handleMenuClose();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Selected reaction: $reaction'),
                      duration: const Duration(seconds: 1),
                    ),
                  );
                },
                onActionSelected: (action) {
                  _handleMenuClose();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Selected action: $action'),
                      duration: const Duration(seconds: 1),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

