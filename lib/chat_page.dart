// lib/chat_page.dart — UI/animation-focused makeover
// NOTE: All networking / socket / data-manipulation methods are left intact.
// Changes are limited to visuals, theming, and animations.

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';
import 'video_player_widget.dart';
import 'package:video_player/video_player.dart';
import 'call_page.dart';
import 'api.dart';
import 'auth_store.dart';
import 'login_page.dart';
import 'socket_service.dart';
import 'foreground_chat.dart';
import 'file_service.dart';
import 'voice_message_service.dart';
import 'voice_message_player.dart';
import 'widgets/voice_recording_ui.dart';
import 'emoji_picker_widget.dart';
import 'config/app_config.dart';
import 'widgets/call_activity_message.dart';
import 'widgets/call_status_banner.dart';
import 'forward_message_page.dart';
import 'models/call_log.dart';
import 'services/call_log_service.dart';
import 'services/theme_service.dart';
import 'services/sync_service.dart';
import 'profile.dart';
import 'widgets/avatar_with_status.dart';
import 'widgets/reply_bubble.dart' show ReplyBubble, FullScreenVideoPlayerPage;

class ChatPage extends StatefulWidget {
  final String? peerId;
  final String partnerEmail;
  final String? peerName;
  final String? conversationId;

  const ChatPage({
    super.key,
    this.peerId,
    required this.partnerEmail,
    this.peerName,
    this.conversationId,
  });

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage>
    with SingleTickerProviderStateMixin {
  final _input = TextEditingController();
  final _inputFocusNode = FocusNode();
  final _scroll = ScrollController();

  String? myId;
  String? peerId;
  bool loading = true;
  bool composerEnabled = false;
  bool _sending = false;
  Map<String, dynamic>? _peerProfile; // Store peer profile data including avatar

  bool _hasText = false;
  bool _uploadingFile = false;
  bool _showEmojiPicker = false;
  bool _isRecordingVoice = false;

  final List<Map<String, dynamic>> _items = [];
  final FileService _fileService = FileService();
  final VoiceMessageService _voiceService = VoiceMessageService();
  final Set<String> _seenIds = <String>{};
  final Set<String> _deletingIds = <String>{};
  String? conversationId;

  final Set<String> _pendingDeletedIds = <String>{};
  final Set<String> _deletedForMeIds =
      <String>{}; // Store messages deleted for me only

  DateTime? _deliveredUpToPeer;
  DateTime? _readUpToPeer;

  Timer? _readDebounce;
  bool _peerOnline = false;
  DateTime? _peerPresenceAt;
  Timer? _presenceTicker;
  bool _peerTyping = false;
  Timer? _peerTypingClear;
  DateTime _lastTypingSent = DateTime.fromMillisecondsSinceEpoch(0);
  String? _editingId;
  String _editingOriginalText = '';
  
  // Reply functionality
  Map<String, dynamic>? _replyingToMessage;
  
  // Store pending reply data for messages we just sent (until they come back via socket)
  // Key: message ID (from HTTP response) or message text (fallback)
  final Map<String, Map<String, dynamic>> _pendingReplyData = {};
  final Map<String, Map<String, dynamic>> _pendingReplyByText = {};
  
  // Swipe to reply gesture tracking
  String? _swipingMessageId;
  double _swipeOffset = 0.0;
  static const double _swipeThreshold = 80.0; // Minimum swipe distance to trigger reply
  
  // Select mode for multi-select
  bool _isSelectMode = false;
  final Set<String> _selectedMessageIds = <String>{};

  // Track which message has context menu open
  String? _contextMenuMessageId;

  // In-chat search UI (triggered from profile search button)
  bool _showSearchBar = false;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  Widget _buildSearchBar(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(22), // pill shape
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: TextField(
        controller: _searchController,
        focusNode: _searchFocusNode,
        keyboardAppearance: Theme.of(context).brightness == Brightness.dark
            ? Brightness.dark
            : Brightness.light,
        style: TextStyle(
          fontSize: 15,
          color: colorScheme.onSurface,
        ),
        decoration: InputDecoration(
          prefixIcon: Icon(
            Icons.search,
            size: 20,
            color: colorScheme.onSurfaceVariant,
          ),
          hintText: 'Search Conservations',
          hintStyle: TextStyle(
            fontSize: 15,
            color: colorScheme.onSurfaceVariant.withOpacity(0.7),
          ),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          disabledBorder: InputBorder.none,
          errorBorder: InputBorder.none,
          focusedErrorBorder: InputBorder.none,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 10),
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context) {
    // 1) Select-mode app bar
    if (_isSelectMode) {
      return AppBar(
        systemOverlayStyle: const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.dark,
        ),
        title: Text('${_selectedMessageIds.length} selected'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () {
            setState(() {
              _isSelectMode = false;
              _selectedMessageIds.clear();
            });
          },
        ),
        actions: [
          // Select all / Deselect all button
          Builder(
            builder: (context) {
              // Count messages with valid IDs (excluding empty IDs)
              final validMessageIds = _items
                  .map((item) => _extractMessageId(item))
                  .where((id) => id.isNotEmpty)
                  .toSet();
              final allSelected = validMessageIds.length > 0 &&
                  _selectedMessageIds.length == validMessageIds.length &&
                  validMessageIds.every((id) => _selectedMessageIds.contains(id));
              
              return IconButton(
                icon: Icon(allSelected ? Icons.deselect : Icons.select_all),
                tooltip: allSelected ? 'Deselect all' : 'Select all',
                onPressed: () {
                  if (allSelected) {
                    _deselectAllMessages();
                  } else {
                    _selectAllMessages();
                  }
                },
              );
            },
          ),
          if (_selectedMessageIds.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              color: Colors.red,
              tooltip: 'Delete',
              onPressed: _deleteSelectedMessages,
            ),
        ],
      );
    }

    final theme = Theme.of(context);

    // 2) Normal chat app bar (profile + call + video)
    return AppBar(
      systemOverlayStyle: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness:
            theme.brightness == Brightness.dark ? Brightness.light : Brightness.dark,
      ),
      backgroundColor: theme.colorScheme.primary,
      foregroundColor: theme.colorScheme.onPrimary,
      elevation: 0,
      leading: IconButton(
        icon: Icon(Icons.arrow_back, color: theme.colorScheme.onPrimary),
        onPressed: () => Navigator.pop(context),
      ),
      titleSpacing: 0,
      title: GestureDetector(
        onTap: peerId != null
            ? () async {
                final result = await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ProfilePage(
                      peerId: peerId,
                      peerName: widget.peerName,
                      peerEmail: widget.partnerEmail,
                    ),
                  ),
                );
                if (result == 'search') {
                  _openSearchOverlay();
                }
              }
            : null,
        child: Row(
          children: [
            const SizedBox(width: 8),
            // Profile picture
            ClipOval(
              child: _peerProfile?['avatarUrl'] != null &&
                      (_peerProfile!['avatarUrl']?.toString() ?? '').isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: _peerProfile!['avatarUrl'].toString(),
                      width: 40,
                      height: 40,
                      fit: BoxFit.cover,
                      errorWidget: (context, url, error) {
                        final fallback =
                            (widget.peerName ?? widget.partnerEmail ?? '')
                                .trim();
                        final initial =
                            fallback.isNotEmpty ? fallback[0].toUpperCase() : '?';
                        return CircleAvatar(
                          radius: 20,
                          backgroundColor:
                              theme.colorScheme.onPrimary.withOpacity(0.2),
                          child: Text(
                            initial,
                            style: TextStyle(
                              color: theme.colorScheme.onPrimary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        );
                      },
                      placeholder: (context, url) => CircleAvatar(
                        radius: 20,
                        backgroundColor:
                            theme.colorScheme.onPrimary.withOpacity(0.2),
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            theme.colorScheme.onPrimary,
                          ),
                        ),
                      ),
                    )
                  : CircleAvatar(
                      radius: 20,
                      backgroundColor:
                          theme.colorScheme.onPrimary.withOpacity(0.2),
                      child: Text(
                        (widget.peerName ?? widget.partnerEmail)
                            .substring(0, 1)
                            .toUpperCase(),
                        style: TextStyle(
                          color: theme.colorScheme.onPrimary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.peerName ?? widget.partnerEmail,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: theme.colorScheme.onPrimary,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _peerTyping
                            ? 'typing…'
                            : (_peerOnline
                                ? 'Active Now'
                                : (_peerPresenceAt != null
                                    ? 'last seen ${_agoLabel(_peerPresenceAt!)}'
                                    : 'offline')),
                        style: TextStyle(
                          color: theme.colorScheme.onPrimary,
                          fontSize: 12,
                          fontStyle: _peerTyping
                              ? FontStyle.italic
                              : FontStyle.normal,
                        ),
                      ),
                      if (_peerOnline && !_peerTyping) ...[
                        const SizedBox(width: 6),
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: Colors.green,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        IconButton(
          icon: Icon(Icons.call, color: theme.colorScheme.onPrimary),
          tooltip: 'Voice call',
          onPressed: (peerId != null && composerEnabled)
              ? () {
                  // Track outgoing call
                  setState(() {
                    _activeCallStatus = 'ringing';
                    _isActiveCallOutgoing = true;
                    _isActiveCallVideo = false;
                  });

                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => CallPage(
                        peerId: peerId!,
                        peerName: widget.peerName ?? widget.partnerEmail,
                        outgoing: true,
                        video: false, // audio-only
                      ),
                    ),
                  ).then((_) {
                    // Clear call status when returning
                    if (mounted) {
                      setState(() {
                        _activeCallId = null;
                        _activeCallStatus = null;
                      });
                    }
                  });
                }
              : null,
        ),
        IconButton(
          icon: Icon(Icons.videocam, color: theme.colorScheme.onPrimary),
          tooltip: 'Video call',
          onPressed: (peerId != null && composerEnabled)
              ? () {
                  // Track outgoing call
                  setState(() {
                    _activeCallStatus = 'ringing';
                    _isActiveCallOutgoing = true;
                    _isActiveCallVideo = true;
                  });

                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => CallPage(
                        peerId: peerId!,
                        peerName: widget.peerName ?? widget.partnerEmail,
                        outgoing: true,
                        video: true,
                      ),
                    ),
                  ).then((_) {
                    // Clear call status when returning
                    if (mounted) {
                      setState(() {
                        _activeCallId = null;
                        _activeCallStatus = null;
                      });
                    }
                  });
                }
              : null,
        ),
      ],
    );
  }

  // 🎨 Animation-only additions
  late final AnimationController _presencePulse;
  late final Animation<double> _presenceScale;
  bool _showScrollToBottom = false;
  
  // Call status tracking for Viber-style banner
  String? _activeCallId;
  String? _activeCallStatus; // 'ringing', 'connecting', 'active'
  bool _isActiveCallOutgoing = false;
  bool _isActiveCallVideo = false;
  Timer? _callStatusTimer;

  void _markReadNow() {
    if (conversationId == null || myId == null) return;
    SocketService.I.emit('read_up_to', {
      'conversationId': conversationId,
      'by': myId,
      'at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  // createdAt ကို cursor နှစ်ခု (_deliveredUpToPeer, _readUpToPeer) နဲ့နှိုင်းပြီး status ဆုံးဖြတ်
  String _msgStatusFor(Map<String, dynamic> m) {
    final createdIso = (m['createdAt'] ?? '').toString();
    final created = DateTime.tryParse(createdIso);
    if (created == null) return '';

    final delivered =
        _deliveredUpToPeer != null && !created.isAfter(_deliveredUpToPeer!);
    final read = _readUpToPeer != null && !created.isAfter(_readUpToPeer!);

    if (read) return 'seen';
    if (delivered) return 'delivered';
    return 'sent';
  }

  void _onEdited(dynamic data) {
    final m = Map<String, dynamic>.from(data);
    // gate by conversation (if known)
    final cid = (m['conversationId'] ?? m['conversation'])?.toString();
    if (conversationId != null && cid != null && cid != conversationId) return;

    final mid = (m['_id'] ?? m['id'])?.toString() ?? '';
    if (mid.isEmpty) return;

    final idx = _items.indexWhere(
      (e) => (e['_id'] ?? e['id']).toString() == mid,
    );
    if (idx >= 0) {
      setState(() {
        _items[idx]['text'] = (m['text'] ?? '').toString();
        _items[idx]['edited'] = true;
        _items[idx]['editedAt'] = m['editedAt'];
      });
    }
  }

  Color _msgStatusColor(String status) {
    switch (status) {
      case 'seen':
        return const Color(0xFF0084FF); // Messenger blue for seen
      case 'delivered':
        return const Color(0xFF8B4513); // Brown color for delivered (like Messenger)
      default:
        return Colors.grey[600] ?? Colors.grey; // Gray for sent
    }
  }

  @override
  void initState() {
    super.initState();
    peerId = widget.peerId;
    conversationId = widget.conversationId;

    _presencePulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    _presenceScale = Tween<double>(
      begin: .85,
      end: 1.15,
    ).animate(CurvedAnimation(parent: _presencePulse, curve: Curves.easeInOut));

    _scroll.addListener(() {
      // With reverse: true, position 0 is at the bottom (last message)
      // So we check if we're near position 0 (within 64 pixels)
      final atBottom = _scroll.offset <= 64.0;
      if (_showScrollToBottom == (!atBottom)) return;
      setState(() => _showScrollToBottom = !atBottom);
    });

    _input.addListener(() {
      final nowHasText = _input.text.trim().isNotEmpty;
      if (nowHasText != _hasText) {
        setState(() => _hasText = nowHasText);
      }

      // Telegram-style: Keep emoji picker open even when typing
      // Don't auto-close the emoji picker - let user manually toggle it via the emoji button
      // The emoji picker will only close when:
      // 1. User taps the keyboard icon to switch to keyboard
      // 2. User sends a message
      // 3. User starts voice recording

      // ✅ emit typing on changes
      if (nowHasText) {
        _sendTyping(true);
      } else {
        _sendTyping(false);
      }
    });
    SocketService.I.off('call:incoming', _onCallIncoming);
    SocketService.I.off('call:ringing', _onCallRinging);
    SocketService.I.off('call:ended', _onCallEnded);
    SocketService.I.off('call:answer', _onCallAnswer);
    SocketService.I.off('call:hangup', _onCallHangup);
    SocketService.I.off('message_edited', _onEdited);
    SocketService.I.off('typing', _onTyping);
    SocketService.I.off('presence', _onPresence);
    SocketService.I.off('presence:initial', _onPresenceInitial);
    SocketService.I.off('message', _onMessage);
    SocketService.I.off('message_deleted', _onDeleted);
    SocketService.I.off('chat_request_accepted', _onAccepted);
    SocketService.I.off('delivered', _onDeliveredEvt);
    SocketService.I.off('read_up_to', _onReadUpToEvt);
    SocketService.I.on('call:incoming', _onCallIncoming);
    SocketService.I.on('call:ringing', _onCallRinging);
    SocketService.I.on('call:ended', _onCallEnded);
    SocketService.I.on('call:answer', _onCallAnswer);
    SocketService.I.on('call:hangup', _onCallHangup);
    SocketService.I.on('call:declined', _onCallDeclined);
    SocketService.I.on('call:answer', _onCallAnswer);
    SocketService.I.on('call:hangup', _onCallHangup);
    SocketService.I.on('message_edited', _onEdited);
    SocketService.I.on('presence', _onPresence);
    SocketService.I.on('presence:initial', _onPresenceInitial);
    SocketService.I.on('message', _onMessage);
    SocketService.I.on('message_deleted', _onDeleted);
    SocketService.I.on('chat_request_accepted', _onAccepted);
    SocketService.I.on('delivered', _onDeliveredEvt);
    SocketService.I.on('read_up_to', _onReadUpToEvt);
    SocketService.I.on('typing', _onTyping);

    // Sync messages and fetch presence when socket reconnects
    SocketService.I.on('__connect__', (_) async {
      // Wait a bit for presence:initial to arrive first
      await Future.delayed(const Duration(milliseconds: 500));
      
      // Fetch presence for the peer
      if (peerId != null && mounted) {
        await _fetchInitialPresence();
      }
      
      // Sync messages
      if (conversationId != null && conversationId!.isNotEmpty) {
        debugPrint('🔄 Socket reconnected, syncing messages for conversation $conversationId');
        SyncService.instance.syncConversationMessages(conversationId!).then((messages) {
          // Check if we have any new messages that weren't in _items
          if (mounted && messages.isNotEmpty) {
            final existingIds = _items.map((e) => (e['_id'] ?? e['id']).toString()).toSet();
            final newMessages = messages.where((m) {
              final id = (m['_id'] ?? m['id']).toString();
              return !existingIds.contains(id);
            }).toList();
            
            if (newMessages.isNotEmpty) {
              setState(() {
                _items.addAll(newMessages);
                _items.sort((a, b) {
                  final aTime = DateTime.tryParse(a['createdAt']?.toString() ?? '') ?? DateTime(0);
                  final bTime = DateTime.tryParse(b['createdAt']?.toString() ?? '') ?? DateTime(0);
                  return aTime.compareTo(bTime);
                });
              });
              debugPrint('💬 Added ${newMessages.length} new messages from sync');
            }
          }
        });
      }
    });

    _presenceTicker = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!_peerOnline && _peerPresenceAt != null && mounted) {
        setState(() {});
      }
    });

    _init();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) async {
        // Fetch presence immediately if socket is already connected
        if (SocketService.I.isConnected) {
          await _fetchInitialPresence();
        } else {
          // Otherwise wait for socket to connect (presence:initial will handle it)
          _fetchInitialPresence();
        }
      },
    );
  }

  void _openSearchOverlay() {
    setState(() {
      _showSearchBar = true;
    });
    // Focus the search field after the frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        FocusScope.of(context).requestFocus(_searchFocusNode);
      }
    });
  }

  void _closeSearchOverlay() {
    setState(() {
      _showSearchBar = false;
      _searchController.clear();
    });
    FocusScope.of(context).unfocus();
  }

  Future<void> _init() async {
    final u = await AuthStore.getUser();
    if (u == null) return _logout();
    myId = u['id'].toString();
    // Load deleted for me messages from persistent storage before loading history
    await _loadDeletedForMeIds();

    // Load peer profile data (non-blocking - don't wait for it to complete)
    if (peerId != null) {
      _loadPeerProfile().catchError((e) {
        debugPrint('⚠️ Profile loading error (non-blocking): $e');
      });
    }

    if (peerId != null) {
      ForegroundChat.currentPeerId = peerId;
      
      // If conversationId exists, load history normally
      if (conversationId != null && conversationId!.isNotEmpty) {
        composerEnabled = true;
        await _loadHistory();
        _markReadNow();
      } else {
        // No conversationId yet - try to find or create conversation
        // This happens when opening chat from Active Users or Contacts
        composerEnabled = true; // Enable composer - conversation will be created on first message
        
        // Try to load any existing conversation with this peer
        try {
          await _loadHistory(); // This will attempt to load messages if conversation exists
        } catch (e) {
          debugPrint('⚠️ No existing conversation found, will create on first message: $e');
        }
      }
    } else {
      // No peerId - create chat request using phone number
      try {
        await _loadPeerProfile().timeout(const Duration(seconds: 3));
      } catch (e) {
        debugPrint('⚠️ Profile loading timeout (using fallback): $e');
      }
      final phone = _peerProfile?['phone']?.toString() ?? widget.partnerEmail;
      await postJson('/api/conversations/chat-requests', {
        'from': myId,
        'toPhone': phone,
      });
      composerEnabled = false;
    }

    setState(() => loading = false);
    // Scroll to bottom after loading completes and UI is built
    _scrollToLastMessage();
    _markReadNow();
  }

  /// Normalize avatar URL to use current server IP
  /// This fixes issues where avatar URLs have old/different IP addresses
  String? _normalizeAvatarUrl(String? avatarUrl) {
    if (avatarUrl == null || avatarUrl.isEmpty || avatarUrl == 'null') {
      return null;
    }
    
    try {
      // Extract the path from the URL (everything after the domain/IP)
      final uri = Uri.parse(avatarUrl);
      final path = uri.path;
      
      // If it's already using the current server, return as-is
      if (avatarUrl.contains(apiBase.replaceFirst('http://', '').replaceFirst('https://', ''))) {
        return avatarUrl;
      }
      
      // Replace with current server base URL
      // Extract just the path (e.g., /uploads/xxx.jpg)
      if (path.isNotEmpty) {
        final normalizedUrl = '$apiBase$path';
        debugPrint('🔄 Normalized avatar URL: $avatarUrl -> $normalizedUrl');
        return normalizedUrl;
      }
      
      return avatarUrl;
    } catch (e) {
      debugPrint('⚠️ Error normalizing avatar URL: $e');
      return avatarUrl; // Return original if parsing fails
    }
  }

  Future<void> _loadPeerProfile() async {
    if (peerId == null) return;
    try {
      debugPrint('📥 Loading peer profile for: $peerId');
      final r = await getJson('/api/users/by-ids?ids=$peerId').timeout(
        const Duration(seconds: 10), // Increased timeout for real devices
      );
      if (r.statusCode == 200) {
        final map = Map<String, dynamic>.from(jsonDecode(r.body));
        final profile = map[peerId];
        if (profile != null) {
          // Normalize avatar URL to use current server IP
          final profileData = Map<String, dynamic>.from(profile);
          final originalAvatarUrl = profileData['avatarUrl']?.toString();
          if (originalAvatarUrl != null && originalAvatarUrl.isNotEmpty) {
            profileData['avatarUrl'] = _normalizeAvatarUrl(originalAvatarUrl);
          }
          
          setState(() {
            _peerProfile = profileData;
          });
          debugPrint('✅ Peer profile loaded successfully: name=${_peerProfile?['name']}, avatarUrl=${_peerProfile?['avatarUrl']}');
        } else {
          debugPrint('⚠️ Peer profile not found in response for: $peerId');
        }
      } else {
        debugPrint('❌ Failed to load peer profile: HTTP ${r.statusCode}');
      }
    } catch (e) {
      debugPrint('❌ Failed to load peer profile: $e');
      // Don't block the UI if profile fails to load - continue with available data
      // The profile might load later or we can use the provided peerName/partnerEmail
    }
  }

  String _agoLabel(DateTime when) {
    final now = DateTime.now();
    final diff = now.difference(when);
    if (diff.inSeconds < 10) return 'just now';
    if (diff.inMinutes < 1) return '${diff.inSeconds}s ago';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    final h = when.hour == 0
        ? 12
        : (when.hour > 12 ? when.hour - 12 : when.hour);
    final mm = when.minute.toString().padLeft(2, '0');
    final ampm = when.hour >= 12 ? 'pm' : 'am';
    return '${when.month}/${when.day} $h:$mm $ampm';
  }

  void _onTyping(dynamic data) {
    if (peerId == null) return;
    final m = Map<String, dynamic>.from(data ?? {});
    final from = (m['from'] ?? '').toString();
    if (from != peerId) return; // only current peer
    final typing = m['typing'] == true;

    _peerTypingClear?.cancel();
    setState(() => _peerTyping = typing);

    // auto-hide after 4s if no further events
    if (typing) {
      _peerTypingClear = Timer(const Duration(seconds: 4), () {
        if (mounted) setState(() => _peerTyping = false);
      });
    }
  }

  // Throttled "I'm typing" signal to server
  void _sendTyping(bool typing) {
    if (!composerEnabled || peerId == null) return;
    final now = DateTime.now();
    if (typing) {
      // throttle ~1200ms
      if (now.difference(_lastTypingSent).inMilliseconds < 1200) return;
      _lastTypingSent = now;
    }
    SocketService.I.emit('typing', {
      'to': peerId,
      'conversationId': conversationId,
      'typing': typing,
    });
  }

  void _onPresence(dynamic data) {
    if (peerId == null) return;
    final m = Map<String, dynamic>.from(data);
    final uid = (m['uid'] ?? '').toString();
    if (uid != peerId) return;
    final on = m['online'] == true;
    final atStr = (m['at'] ?? '').toString();
    final at = DateTime.tryParse(atStr)?.toLocal();
    setState(() {
      _peerOnline = on;
      if (at != null) _peerPresenceAt = at;
    });
    debugPrint('✅ Updated peer online status from presence event: online=$on, peerId=$peerId');
  }

  void _onPresenceInitial(dynamic data) {
    if (peerId == null) return;
    try {
      final m = Map<String, dynamic>.from(data ?? {});
      final users = Map<String, dynamic>.from(m['users'] ?? {});
      debugPrint('📡 Chat page received presence:initial with ${users.length} users, looking for peerId=$peerId');
      final peerStatus = users[peerId];
      if (peerStatus != null) {
        final status = Map<String, dynamic>.from(peerStatus);
        final on = status['online'] == true || status['isOnline'] == true;
        final atStr = (status['at'] ?? status['lastSeen'] ?? '').toString();
        final at = DateTime.tryParse(atStr)?.toLocal();
        setState(() {
          _peerOnline = on;
          if (at != null) _peerPresenceAt = at;
        });
        debugPrint('✅ Updated peer online status from presence:initial: online=$on, peerId=$peerId');
      } else {
        debugPrint('⚠️ Peer $peerId not found in presence:initial data. Available users: ${users.keys.toList()}');
      }
    } catch (e) {
      debugPrint('❌ Error handling presence:initial in chat page: $e');
    }
  }

  void _onCallIncoming(dynamic data) {
    // data: { callId, from, sdp, kind }
    if (!mounted) return;
    final m = Map<String, dynamic>.from(data ?? {});
    final from = (m['from'] ?? '').toString();
    final callId = (m['callId'] ?? '').toString();
    final kind = (m['kind'] ?? 'audio').toString();

    // Check if this call is for the current chat peer
    if (peerId != null && from == peerId) {
      // Update call status for banner
      setState(() {
        _activeCallId = callId;
        _activeCallStatus = 'ringing';
        _isActiveCallOutgoing = false;
        _isActiveCallVideo = kind == 'video';
      });
      
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => CallPage(
            peerId: peerId!,
            peerName: widget.peerName ?? widget.partnerEmail,
            outgoing: false, // 👈 incoming
            video: kind == 'video',
            initialCallId: callId,
            initialOffer: m['sdp'],
          ),
        ),
      ).then((_) {
        // Clear call status when returning from call page
        if (mounted) {
          setState(() {
            _activeCallId = null;
            _activeCallStatus = null;
          });
        }
      });
    } else {
      // Not for this chat - show notification
      final who = from.isNotEmpty ? from : 'Someone';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$who is calling…')));
    }
  }

  void _onCallRinging(dynamic data) {
    // data: { callId, to, kind }
    if (!mounted) return;
    final m = Map<String, dynamic>.from(data ?? {});
    final callId = (m['callId'] ?? '').toString();
    final to = (m['to'] ?? '').toString();
    final kind = (m['kind'] ?? 'audio').toString();
    
    // Check if this is for the current peer
    if (peerId != null && to == peerId) {
      setState(() {
        _activeCallId = callId;
        _activeCallStatus = 'ringing';
        _isActiveCallOutgoing = true;
        _isActiveCallVideo = kind == 'video';
      });
    }
  }

  void _onCallEnded(dynamic data) {
    // data: { callId, by }
    if (!mounted) return;
    final m = Map<String, dynamic>.from(data ?? {});
    final callId = (m['callId'] ?? '').toString();
    
    // Clear call status if this call ended
    if (_activeCallId == callId || _activeCallId == null) {
      setState(() {
        _activeCallId = null;
        _activeCallStatus = null;
      });
      _callStatusTimer?.cancel();
    }
  }
  
  void _onCallAnswer(dynamic data) {
    // data: { callId, from, sdp, kind } (from backend when call is accepted)
    if (!mounted) return;
    final m = Map<String, dynamic>.from(data ?? {});
    final callId = (m['callId'] ?? '').toString();
    
    // Update call status when answered (this event is sent to caller when callee accepts)
    if (_activeCallId == callId ||
        (_activeCallId == null && callId.isNotEmpty)) {
      setState(() {
        _activeCallId = callId;
        _activeCallStatus = 'connecting';
        // Update to active after a short delay
        _callStatusTimer?.cancel();
        _callStatusTimer = Timer(const Duration(seconds: 2), () {
          if (mounted && _activeCallId == callId) {
            setState(() {
              _activeCallStatus = 'active';
            });
          }
        });
      });
    }
  }
  
  void _onCallHangup(dynamic data) {
    // data: { callId }
    if (!mounted) return;
    final m = Map<String, dynamic>.from(data ?? {});
    final callId = (m['callId'] ?? '').toString();
    
    // Clear call status
    if (_activeCallId == callId || _activeCallId == null) {
      setState(() {
        _activeCallId = null;
        _activeCallStatus = null;
      });
      _callStatusTimer?.cancel();
    }
  }
  
  void _onCallDeclined(dynamic data) {
    // data: { callId, from }
    if (!mounted) return;
    final m = Map<String, dynamic>.from(data ?? {});
    final callId = (m['callId'] ?? '').toString();
    
    // Clear call status when declined
    if (_activeCallId == callId || _activeCallId == null) {
      setState(() {
        _activeCallId = null;
        _activeCallStatus = null;
      });
      _callStatusTimer?.cancel();
    }
  }

  Future<void> _fetchInitialPresence() async {
    if (peerId == null) return;
    try {
      final r = await getJson(
        '/api/users/presence?ids=$peerId&verbose=true',
      ).timeout(const Duration(seconds: 8));
      if (r.statusCode == 200) {
        final body = Map<String, dynamic>.from(jsonDecode(r.body));
        // API returns { success: true, presence: { peerId: {...} } }
        final presenceMap = Map<String, dynamic>.from(body['presence'] ?? body);
        final obj = Map<String, dynamic>.from(presenceMap[peerId] ?? {});
        final on = obj['online'] == true || obj['isOnline'] == true;
        final at = DateTime.tryParse((obj['at'] ?? obj['lastSeen'] ?? '').toString())?.toLocal();
        setState(() {
          _peerOnline = on;
          _peerPresenceAt = at;
        });
        debugPrint('✅ Fetched initial presence for $peerId: online=$on');
      }
    } catch (e) {
      debugPrint('❌ Error fetching initial presence: $e');
    }
  }

  void _onDeliveredEvt(dynamic data) {
    // data = { messageId, conversationId, by, at }
    final m = Map<String, dynamic>.from(data ?? {});
    final cid = (m['conversationId'] ?? '').toString();
    final by = (m['by'] ?? '').toString(); // receiver uid
    if (conversationId == null || cid != conversationId) return;
    if (peerId == null || by != peerId) return;

    final atIso = (m['at'] ?? '').toString();
    final ts = DateTime.tryParse(atIso);
    if (ts == null) return;

    if (_deliveredUpToPeer == null || !ts.isBefore(_deliveredUpToPeer!)) {
      setState(() => _deliveredUpToPeer = ts);
    }
  }

  void _onReadUpToEvt(dynamic data) {
    // data = { conversationId, by, at }
    final m = Map<String, dynamic>.from(data ?? {});
    final cid = (m['conversationId'] ?? '').toString();
    final by = (m['by'] ?? '').toString();
    if (conversationId == null || cid != conversationId) return;
    if (peerId == null || by != peerId) return;

    final atIso = (m['at'] ?? '').toString();
    final ts = DateTime.tryParse(atIso);
    if (ts == null) return;

    setState(() {
      _readUpToPeer = ts;
      _deliveredUpToPeer =
          (_deliveredUpToPeer == null || _deliveredUpToPeer!.isBefore(ts))
          ? ts
          : _deliveredUpToPeer;
    });
  }

  Future<void> _loadCursorsOnce() async {
    if (conversationId == null || myId == null || peerId == null) return;

    final url = Uri.parse('$apiBase/api/conversations?me=$myId&status=active');
    final r = await http.get(url, headers: await authHeaders());
    if (r.statusCode != 200) return;
    final list = (jsonDecode(r.body) as List).cast<Map<String, dynamic>>();
    final it = list.firstWhere(
      (e) => (e['_id']?.toString() ?? '') == conversationId,
      orElse: () => {},
    );
    if (it.isEmpty) return;

    final delivered = Map<String, dynamic>.from(it['deliveredUpTo'] ?? {});
    final read = Map<String, dynamic>.from(it['readUpTo'] ?? {});
    final dIso = (delivered[peerId] ?? '').toString();
    final rIso = (read[peerId] ?? '').toString();

    setState(() {
      _deliveredUpToPeer = DateTime.tryParse(dIso);
      _readUpToPeer = DateTime.tryParse(rIso);
    });
  }

  void _onAccepted(dynamic data) async {
    if (peerId != null) return;
    final map = (data is Map) ? Map<String, dynamic>.from(data) : {};
    final partnerId = map['partnerId']?.toString();
    final cid = map['conversationId']?.toString();
    if (partnerId == null) return;
    peerId = partnerId;
    if (cid != null && cid.isNotEmpty) conversationId = cid;
    ForegroundChat.currentPeerId = peerId;
    composerEnabled = true;
    setState(() {});
    await _loadHistory();
    _scrollToBottom();
  }

  void _applyDeleteLocally(String id) {
    final idx = _items.indexWhere(
      (e) => (e['_id'] ?? e['id'] ?? '').toString() == id,
    );
    if (idx >= 0) {
      _items[idx]['deleted'] = true;
      _items[idx]['text'] = '';
    }
  }

  void _onMessage(dynamic data) {
    if (peerId == null && conversationId == null) return;
    final m = Map<String, dynamic>.from(data);
    
    // Debug logging for video messages
    final fileType = m['fileType']?.toString();
    if (fileType == 'video') {
      debugPrint('Received video message: fileType=$fileType, fileName=${m['fileName']}, fileUrl=${m['fileUrl']}');
    }

    final cid = (m['conversationId'] ?? m['conversation'])?.toString();
    if (cid != null && cid.isNotEmpty) {
      conversationId ??= cid; // adopt first time
      if (conversationId != cid) return; // not this thread
    } else {
      final from = m['from']?.toString();
      final to = m['to']?.toString();
      final mine = myId;
      if (mine == null) return;
      final isThis = (peerId != null)
          ? ((from == peerId && to == mine) || (to == peerId && from == mine))
          : ((from == peerId) || (to == peerId));
      if (!isThis) return;
    }

    final id = _extractMessageId(m);
    if (id.isNotEmpty) {
      if (_seenIds.contains(id)) return;
      _seenIds.add(id);
    }

    // For call activity messages, verify they belong to this conversation
    if (m['messageType']?.toString() == 'call_activity' ||
        m['callActivity'] == true) {
      final from = m['from']?.toString();
      final to = m['to']?.toString();
      final toEmail = m['toEmail']?.toString();
      final msgConversationId = (m['conversationId'] ?? m['conversation'])
          ?.toString();
      
      // First check by conversationId (most reliable)
      if (conversationId != null && msgConversationId != null) {
        if (msgConversationId != conversationId) {
          debugPrint(
            'Call activity message not for this conversation. MsgConvId: $msgConversationId, CurrentConvId: $conversationId',
          );
          return; // Skip messages not for this conversation
        }
      } else if (peerId != null && myId != null) {
        // If no conversationId, check by participants
        // The message should be between current user (myId) and this peer (peerId)
        // Note: peerId might be email or user ID, so check both
        final isFromMeToPeer =
            from == myId &&
            (to == peerId ||
                toEmail == widget.partnerEmail ||
                toEmail == peerId);
        final isFromPeerToMe =
            (from == peerId || from == widget.partnerEmail) && to == myId;
        
        if (!isFromMeToPeer && !isFromPeerToMe) {
          debugPrint(
            'Call activity message not for this chat. From: $from, To: $to, ToEmail: $toEmail, MyId: $myId, PeerId: $peerId, PartnerEmail: ${widget.partnerEmail}',
          );
          return; // Skip messages not for this conversation
        }
      } else {
        // If we can't verify, skip to be safe
        debugPrint(
          'Cannot verify call activity message - skipping. PeerId: $peerId, ConversationId: $conversationId',
        );
        return;
      }
      
      // Check for duplicates by callStartTime and participants
      final callStartTime = m['callStartTime']?.toString();
      if (callStartTime != null) {
        final existing = _items.where((item) {
          final itemStartTime = item['callStartTime']?.toString();
          final itemId = (item['_id'] ?? item['id'] ?? '').toString();
          final currentId = id.isNotEmpty ? id : '';
          
          final isCallActivity =
              (item['messageType']?.toString() == 'call_activity' ||
                                  item['callActivity'] == true);
          
          // Check by ID first (most reliable)
          if (currentId.isNotEmpty && itemId == currentId) {
            return true;
          }
          
          // Check by start time and participants (must match exactly)
          if (isCallActivity && itemStartTime == callStartTime) {
            // Check if same participants (in either direction)
            final itemFrom = item['from']?.toString() ?? '';
            final itemTo = item['to']?.toString() ?? '';
            final itemToEmail = item['toEmail']?.toString() ?? '';
            
            // Match if same participants regardless of direction
            final sameParticipants = 
                (itemFrom == from &&
                    (itemTo == to ||
                        itemTo == toEmail ||
                        itemToEmail == to ||
                        itemToEmail == widget.partnerEmail)) ||
                (itemFrom == to && itemTo == from) ||
                (itemFrom == widget.partnerEmail && itemTo == myId);
            
            if (sameParticipants) {
              debugPrint(
                'Duplicate call activity detected: StartTime=$callStartTime, From=$from, To=$to, ItemFrom=$itemFrom, ItemTo=$itemTo',
              );
              return true;
            }
          }
          
          return false;
        }).toList();
        
        if (existing.isNotEmpty) {
          debugPrint(
            'Duplicate call activity message detected, skipping. StartTime: $callStartTime, From: $from, To: $to',
          );
          return;
        }
      }
    }

    // Check if this is a message we sent that should have reply data
    final from = m['from']?.toString();
    if (from == myId && id.isNotEmpty) {
      // Check if we have pending reply data for this message (by ID first)
      Map<String, dynamic>? replyData;
      if (_pendingReplyData.containsKey(id)) {
        replyData = _pendingReplyData[id]!;
        _pendingReplyData.remove(id); // Clean up
        debugPrint('✅ FOUND REPLY DATA by ID for message $id');
      } else {
        // Try to match by text content (fallback)
        final messageText = m['text']?.toString() ?? '';
        if (messageText.isNotEmpty && _pendingReplyByText.containsKey(messageText)) {
          replyData = _pendingReplyByText[messageText]!;
          _pendingReplyByText.remove(messageText); // Clean up
          debugPrint('✅ FOUND REPLY DATA by text for message $id: "$messageText"');
        } else {
          debugPrint('❌ NO PENDING REPLY DATA for message $id (from socket), text="$messageText"');
        }
      }
      
      // Attach reply data if found (only if backend didn't send it)
      if (replyData != null && (m['replyTo'] == null && m['replyToMessage'] == null)) {
        m['replyTo'] = replyData['replyTo'];
        m['replyToMessage'] = replyData['replyToMessage'];
        debugPrint('✅ ATTACHED REPLY DATA to socket message $id: ${m['replyToMessage']}');
      }
    }
    
    // For received messages, ensure reply data is preserved (backend should send it, but log if present)
    if (from != myId && (m['replyTo'] != null || m['replyToMessage'] != null)) {
      debugPrint('📩 RECEIVED MESSAGE WITH REPLY DATA: from=$from, replyTo=${m['replyTo']}, replyToMessage=${m['replyToMessage']}');
      
      // Ensure replyToMessage has proper structure if it exists
      if (m['replyToMessage'] != null && m['replyToMessage'] is Map) {
        final replyMsg = Map<String, dynamic>.from(m['replyToMessage']);
        debugPrint('📩 REPLY MESSAGE STRUCTURE: $replyMsg');
        
        // Ensure 'from' field exists in replyToMessage for proper sender name resolution
        if (replyMsg['from'] == null && replyMsg['sender'] != null) {
          replyMsg['from'] = replyMsg['sender'];
          m['replyToMessage'] = replyMsg;
          debugPrint('📩 FIXED replyToMessage.from from sender field');
        }
      }
    }
    
    // Don't add messages that were deleted "for me"
    final messageId = _extractMessageId(m);
    if (!_deletedForMeIds.contains(messageId)) {
      setState(() => _items.add(m));
      _scrollToBottom();
    }

    final to = m['to']?.toString();
    if (to == myId && id.isNotEmpty) {
      SocketService.I.emit('delivered', {'messageId': id});
      _markReadNow();
    }
  }

  Future<void> _loadHistory() async {
    if (myId == null) return;

    Uri uri;
    if (conversationId != null && conversationId!.isNotEmpty) {
      uri = Uri.parse('$apiBase/api/messages?conversation=$conversationId');
    } else if (peerId != null) {
      uri = Uri.parse('$apiBase/api/messages?userA=$myId&userB=$peerId');
    } else {
      return;
    }

    final r = await http.get(uri, headers: await authHeaders());
    if (r.statusCode == 200) {
      final list = (jsonDecode(r.body) as List).cast<Map<String, dynamic>>();

      // Count messages with reply data for debugging
      int replyCount = 0;
      for (final e in list) {
        final id = (e['_id'] ?? e['id'] ?? '').toString();
        if (_pendingDeletedIds.contains(id)) {
          e['deleted'] = true;
          e['text'] = '';
        }
        // Restore deletedForMe state if this message was deleted for me
        if (_deletedForMeIds.contains(id)) {
          e['deletedForMe'] = true;
          e['text'] = '';
        }
        
        // Check and log reply data
        if (e['replyTo'] != null || e['replyToMessage'] != null) {
          replyCount++;
          final replyTo = e['replyTo'];
          final replyToMessage = e['replyToMessage'];
          debugPrint('📚 LOADED MESSAGE WITH REPLY: id=$id');
          debugPrint('   replyTo: $replyTo (type: ${replyTo.runtimeType})');
          debugPrint('   replyToMessage: $replyToMessage (type: ${replyToMessage.runtimeType})');
          if (replyToMessage is Map) {
            debugPrint('   replyToMessage content: $replyToMessage');
          }
          
          // Ensure reply data is properly preserved (convert to proper types if needed)
          if (replyTo != null && replyTo.toString().isNotEmpty) {
            e['replyTo'] = replyTo.toString();
          }
          if (replyToMessage != null) {
            // Ensure replyToMessage is a Map if it's an object
            if (replyToMessage is Map) {
              e['replyToMessage'] = Map<String, dynamic>.from(replyToMessage);
            } else {
              // If it's not a Map, try to preserve it as-is
              e['replyToMessage'] = replyToMessage;
            }
          }
        }
      }
      
      if (replyCount > 0) {
        debugPrint('📚 LOADED HISTORY: Found $replyCount messages with reply data out of ${list.length} total messages');
      }

      // Debug: Log a sample of messages to verify data structure
      if (list.isNotEmpty) {
        final sampleMsg = list.first;
        debugPrint('📚 SAMPLE MESSAGE STRUCTURE: keys=${sampleMsg.keys.toList()}, hasReplyTo=${sampleMsg.containsKey('replyTo')}, hasReplyToMessage=${sampleMsg.containsKey('replyToMessage')}');
      }

      // Filter out messages that were deleted "for me" - don't show them at all
      final filteredList = list.where((e) {
        final id = (e['_id'] ?? e['id'] ?? '').toString();
        // Don't include messages that were deleted for me
        return !_deletedForMeIds.contains(id);
      }).toList();
      
      _items
        ..clear()
        ..addAll(filteredList);
      
      // Debug: Verify reply data is in _items after loading
      final itemsWithReply = _items.where((item) => 
        item['replyTo'] != null || item['replyToMessage'] != null
      ).length;
      if (itemsWithReply > 0) {
        debugPrint('📚 VERIFIED: $itemsWithReply messages in _items have reply data after loading');
      } else {
        debugPrint('⚠️ WARNING: No messages in _items have reply data after loading history');
      }
      _seenIds
        ..clear()
        ..addAll(
          list
              .map((e) => (e['_id'] ?? e['id'] ?? '').toString())
              .where((s) => s.isNotEmpty),
        );

      _pendingDeletedIds.removeWhere(
        (id) =>
            _items.any((e) => ((e['_id'] ?? e['id'] ?? '').toString() == id)),
      );

      if ((conversationId == null || conversationId!.isEmpty) &&
          list.isNotEmpty) {
        String adopted = '';
        for (final e in list) {
          final cid = (e['conversation'] ?? e['conversationId'] ?? '')
              .toString();
          if (cid.isNotEmpty) {
            adopted = cid;
            break;
          }
        }
        if (adopted.isNotEmpty &&
            (conversationId == null || conversationId!.isEmpty)) {
          conversationId = adopted;
          // Reload deleted IDs now that we have a conversation ID
          await _loadDeletedForMeIds();
          // Re-apply deletions to current messages
          for (final e in _items) {
            final id = (e['_id'] ?? e['id'] ?? '').toString();
            if (_deletedForMeIds.contains(id)) {
              e['deletedForMe'] = true;
              e['text'] = '';
            }
          }
          _markReadNow();
        }
      }

      await _loadCursorsOnce();

      if (mounted) {
        setState(() {});
        // Scroll to bottom after messages are loaded and UI is updated
        _scrollToLastMessage();
      }
    } else if (r.statusCode == 401) {
      _logout();
    } else {
      // optional: error toast/log
    }
  }

  Future<void> _send({
    String? fileUrl,
    String? fileName,
    String? fileType,
    int? audioDuration,
  }) async {
    if (_sending || !composerEnabled) return;

    final text = _input.text.trim();
    if (text.isEmpty && fileUrl == null) return;

    _input.clear();
    _sendTyping(false);
    _sending = true;
    if (_showEmojiPicker) {
      setState(() {
        _showEmojiPicker = false;
      });
    }
    try {
      // For images, videos, and voice messages, set text to empty if no text is provided
      final isImageOrVideo = fileType == 'image' || fileType == 'video';
      final isVoice = fileType == 'audio' || fileType == 'voice';
      // Clean text for voice messages - remove mic emoji if present
      String cleanedText = text;
      if (isVoice && cleanedText.trim() == '🎤') {
        cleanedText = '';
      }
      // Capture current reply target (if any) so we can also attach it to
      // the locally-added payload after sending.
      final Map<String, dynamic>? currentReplyTarget =
          _replyingToMessage != null ? Map<String, dynamic>.from(_replyingToMessage!) : null;

      final messageData = <String, dynamic>{
        'from': myId,
        'text': cleanedText.isNotEmpty
            ? cleanedText
            : (fileUrl != null && !isImageOrVideo && !isVoice ? '📎 ${fileName ?? "File"}' : ''),
      };
      
      // Priority: conversationId > toId > toPhone
      // Use conversationId if available (most reliable)
      if (conversationId != null && conversationId!.isNotEmpty) {
        messageData['conversationId'] = conversationId;
      } 
      // Use peerId (toId) if available (more reliable than phone) - THIS IS THE KEY FIX
      else if (peerId != null && peerId!.isNotEmpty) {
        messageData['toId'] = peerId;
        debugPrint('📤 Sending message using toId: $peerId (conversation will be auto-created)');
      }
      // Fallback to phone number
      else {
        final phone = _peerProfile?['phone']?.toString() ?? widget.partnerEmail;
        if (phone != null && phone.isNotEmpty) {
          messageData['toPhone'] = phone;
          debugPrint('📤 Sending message using toPhone: $phone');
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Cannot send message: Recipient information missing')),
            );
          }
          _sending = false;
          return;
        }
      }
      
      // Add replyTo if replying to a message
      Map<String, dynamic>? replyDataToStore;
      if (currentReplyTarget != null) {
        final replyId = _extractMessageId(currentReplyTarget);
        if (replyId.isNotEmpty) {
          messageData['replyTo'] = replyId;
          // Also include original message data for preview
          final replyFileType = currentReplyTarget['fileType']?.toString();
          final replyFileUrl = currentReplyTarget['fileUrl']?.toString();
          final replyFileName = currentReplyTarget['fileName']?.toString();
          final replyAudioDuration = currentReplyTarget['audioDuration'];
          
          debugPrint('📎 CREATING REPLY DATA: replyId=$replyId, fileType=$replyFileType, fileUrl=$replyFileUrl, fileName=$replyFileName, audioDuration=$replyAudioDuration');
          debugPrint('📎 CREATING REPLY DATA: currentReplyTarget keys=${currentReplyTarget.keys.toList()}');
          
          replyDataToStore = <String, dynamic>{
            'replyTo': replyId,
            'replyToMessage': <String, dynamic>{
              'id': replyId,
              'text': currentReplyTarget['text']?.toString() ?? '',
              'fileType': replyFileType,
              'fileName': replyFileName,
              'fileUrl': replyFileUrl,
              'audioDuration': replyAudioDuration,
              'from': currentReplyTarget['from']?.toString(),
            },
          };
          messageData['replyToMessage'] = replyDataToStore['replyToMessage'];
          
          debugPrint('📎 CREATED REPLY DATA: replyToMessage=${replyDataToStore['replyToMessage']}');
          
          // Store reply data by message text BEFORE sending (for socket matching)
          final messageTextKey = cleanedText.isNotEmpty ? cleanedText : (fileUrl != null ? 'file_${DateTime.now().millisecondsSinceEpoch}' : 'empty_${DateTime.now().millisecondsSinceEpoch}');
          _pendingReplyByText[messageTextKey] = replyDataToStore;
          debugPrint('SENDING REPLY: replyId=$replyId, replyText=${replyDataToStore['replyToMessage']['text']}, storing by text="$messageTextKey"');
        }
        // Clear reply after sending
        _replyingToMessage = null;
      }
      
      if (fileUrl != null) {
        messageData['fileUrl'] = fileUrl;
        messageData['fileName'] = fileName;
        messageData['fileType'] = fileType;
        if (audioDuration != null) {
          messageData['audioDuration'] = audioDuration.toString();
        }
      }

      // Debug logging for video messages
      if (fileType == 'video') {
        debugPrint('Sending video message: fileUrl=$fileUrl, fileName=$fileName, fileType=$fileType');
      }

      final res = await postJson('/api/messages', messageData);

      if (!mounted) return;

      if (res.statusCode == 200) {
        // Update conversationId if it was returned in response (for new conversations)
        try {
          final body = jsonDecode(res.body);
          final msgData = body['data'] ?? body;
          final returnedConvId = msgData['conversationId'] ?? msgData['conversation']?.toString();
          if (returnedConvId != null && returnedConvId.isNotEmpty && conversationId != returnedConvId) {
            debugPrint('📝 Updated conversationId from response: $conversationId -> $returnedConvId');
            setState(() {
              conversationId = returnedConvId;
            });
          }
        } catch (e) {
          debugPrint('⚠️ Could not parse conversationId from response: $e');
        }
      }

      if (res.statusCode != 200) {
        String msg;
        if (res.statusCode == 403) {
          msg = 'Receiver has not accepted your request yet.';
        } else if (res.statusCode == 404) {
          try {
            final body = jsonDecode(res.body);
            msg = body['message'] ?? 'Recipient not found. The user may need to register first.';
          } catch (e) {
            msg = 'Recipient not found. The user may need to register first.';
          }
        } else {
          msg = 'Send failed (${res.statusCode})';
        }
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 4)));
        return;
      }

      try {
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        final payload = Map<String, dynamic>.from(body['message'] ?? {});

        if (payload.isNotEmpty) {
          final id = _extractMessageId(payload);
          if (id.isNotEmpty && !_seenIds.contains(id)) {
            _seenIds.add(id);
            
            // If backend didn't return reply data, attach it from what we sent
            if (replyDataToStore != null) {
              if (payload['replyTo'] == null && payload['replyToMessage'] == null) {
                payload['replyTo'] = replyDataToStore['replyTo'];
                payload['replyToMessage'] = replyDataToStore['replyToMessage'];
                debugPrint('✅ ATTACHED REPLY DATA to HTTP response message $id');
              } else {
                debugPrint('✅ HTTP response already has reply data for message $id');
              }
              // Store in pending for socket fallback (by ID and by text)
              _pendingReplyData[id] = replyDataToStore;
              final messageText = payload['text']?.toString() ?? '';
              if (messageText.isNotEmpty) {
                _pendingReplyByText[messageText] = replyDataToStore;
                debugPrint('📝 STORED REPLY DATA by text: "$messageText"');
              }
            }
            
            debugPrint('📨 ADDING MESSAGE: id=$id, hasReplyTo=${payload['replyTo'] != null}, hasReplyToMessage=${payload['replyToMessage'] != null}, text=${payload['text']}');
            setState(() => _items.add(payload));
            _scrollToBottom();
          }
          final cid =
              (payload['conversationId'] ?? payload['conversation'] ?? '')
                  .toString();
          if (cid.isNotEmpty) conversationId = cid;
        }
      } catch (_) {
        /* ignore; rely on socket */
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Network error: $e')));
    } finally {
      _sending = false;
    }
  }

  Future<void> _pickAndSendImage(ImageSource source) async {
    if (_uploadingFile || !composerEnabled) return;
    
    setState(() => _uploadingFile = true);
    try {
      final XFile? image = await _fileService.pickImage(source: source);
      if (image == null || !mounted) {
        setState(() => _uploadingFile = false);
        return;
      }

      // Show uploading indicator
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(width: 12),
              Text('Uploading image...'),
            ],
          ),
          duration: Duration(seconds: 30),
        ),
      );

      final fileUrl = await _fileService.uploadImage(image);
      if (!mounted) {
        setState(() => _uploadingFile = false);
        return;
      }

      ScaffoldMessenger.of(context).hideCurrentSnackBar();

      if (fileUrl != null) {
        await _send(fileUrl: fileUrl, fileName: image.name, fileType: 'image');
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Failed to upload image')));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      setState(() => _uploadingFile = false);
    }
  }

  Future<void> _pickAndSendVideo(ImageSource source) async {
    if (_uploadingFile || !composerEnabled) return;

    setState(() => _uploadingFile = true);
    try {
      final XFile? video = await _fileService.pickVideo(source: source);
      if (video == null || !mounted) {
        setState(() => _uploadingFile = false);
        return;
      }

      // Show uploading indicator
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(width: 12),
              Text('Uploading video...'),
            ],
          ),
          duration: Duration(seconds: 60),
        ),
      );

      final fileUrl = await _fileService.uploadImage(video);
      if (!mounted) {
        setState(() => _uploadingFile = false);
        return;
      }

      ScaffoldMessenger.of(context).hideCurrentSnackBar();

      if (fileUrl != null) {
        debugPrint('Video uploaded successfully: $fileUrl, fileName: ${video.name}');
        await _send(
          fileUrl: fileUrl,
          fileName: video.name,
          fileType: 'video',
        );
      } else {
        debugPrint('Failed to upload video: fileUrl is null');
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Failed to upload video')));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      setState(() => _uploadingFile = false);
    }
  }

  Future<void> _pickAndSendFile() async {
    if (_uploadingFile || !composerEnabled) return;
    
    setState(() => _uploadingFile = true);
    try {
      final file = await _fileService.pickFile();
      if (file == null || file.path == null || !mounted) {
        setState(() => _uploadingFile = false);
        return;
      }

      // Show uploading indicator
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 12),
              Expanded(child: Text('Uploading ${file.name}...')),
            ],
          ),
          duration: const Duration(seconds: 60),
        ),
      );

      final fileUrl = await _fileService.uploadPlatformFile(file);
      if (!mounted) {
        setState(() => _uploadingFile = false);
        return;
      }

      ScaffoldMessenger.of(context).hideCurrentSnackBar();

      if (fileUrl != null) {
        await _send(
          fileUrl: fileUrl,
          fileName: file.name,
          fileType: file.extension ?? 'file',
        );
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Failed to upload file')));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      setState(() => _uploadingFile = false);
    }
  }

  Future<void> _openFileUrl(String? url) async {
    if (url == null || url.isEmpty) return;
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    try {
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open file')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open file: $e')),
      );
    }
  }

  void _showAttachmentOptions() {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Photo from Gallery'),
              onTap: () {
                Navigator.pop(context);
                _pickAndSendImage(ImageSource.gallery);
              },
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Take Photo'),
              onTap: () {
                Navigator.pop(context);
                _pickAndSendImage(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.videocam),
              title: const Text('Video from Gallery'),
              onTap: () {
                Navigator.pop(context);
                _pickAndSendVideo(ImageSource.gallery);
              },
            ),
            ListTile(
              leading: const Icon(Icons.videocam_outlined),
              title: const Text('Record Video'),
              onTap: () {
                Navigator.pop(context);
                _pickAndSendVideo(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.insert_drive_file),
              title: const Text('Choose File'),
              onTap: () {
                Navigator.pop(context);
                _pickAndSendFile();
              },
            ),
          ],
        ),
      ),
    );
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      // With reverse: true, position 0 is at the bottom (last message)
      _scroll.animateTo(
        0,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      );
      _markReadNow();
    });
  }

  // Scroll to last message when entering conversation
  // Note: With reverse: true, ListView automatically starts at bottom, 
  // but we still ensure it's positioned correctly
  void _scrollToLastMessage() {
    // With reverse: true, ListView starts at bottom automatically
    // But we ensure it's positioned correctly after items load
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scroll.hasClients && _items.isNotEmpty) {
        try {
          // With reverse: true, position 0 is at the bottom (last message)
          // So we ensure we're at the start (which is the bottom)
          if (_scroll.position.pixels != 0) {
            _scroll.jumpTo(0);
          }
        } catch (e) {
          debugPrint('Error scrolling to last message: $e');
        }
      }
    });
  }

  String _extractMessageId(Map<String, dynamic> m) {
    final candidates = [
      m['_id'],
      m['id'],
      m['messageId'],
      m['msgId'],
      (m['message'] is Map) ? (m['message'] as Map)['_id'] : null,
    ];
    for (final c in candidates) {
      if (c == null) continue;
      final s = c.toString();
      if (s.isNotEmpty) return s;
    }
    return '';
  }

  void _startEdit(Map<String, dynamic> m) {
    final id = (m['_id'] ?? m['id'] ?? '').toString();
    if (id.isEmpty) return;
    final myText = (m['text'] ?? '').toString();
    _editingId = id;
    _editingOriginalText = myText;
    _input.text = myText;

    _input.selection = TextSelection.fromPosition(
      TextPosition(offset: _input.text.length),
    );
    setState(() {});
  }

  Future<void> _saveEdit() async {
    if (_editingId == null) return;
    final newText = _input.text.trim();
    if (newText.isEmpty) return;

    final url = Uri.parse('$apiBase/api/messages/${_editingId}');
    final r = await http.patch(
      url,
      headers: await authHeaders(),
      body: jsonEncode({'text': newText}),
    );

    if (!mounted) return;

    if (r.statusCode == 200) {
      final idx = _items.indexWhere(
        (e) => (e['_id'] ?? e['id'] ?? '').toString() == _editingId,
      );
      if (idx >= 0) {
        setState(() {
          _items[idx]['text'] = newText;
          _items[idx]['edited'] = true;
          _items[idx]['editedAt'] = DateTime.now().toUtc().toIso8601String();
        });
      }
      _cancelEdit();
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Edit failed (${r.statusCode})')));
    }
  }

  void _cancelEdit() {
    _editingId = null;
    _editingOriginalText = '';
    _input.clear();
    setState(() {});
  }
  
  void _cancelReply() {
    _replyingToMessage = null;
    setState(() {});
  }
  
  void _startReply(Map<String, dynamic> message) {
    debugPrint('📎 START REPLY: message keys=${message.keys.toList()}');
    debugPrint('📎 START REPLY: fileType=${message['fileType']}, fileUrl=${message['fileUrl']}, fileName=${message['fileName']}');
    _replyingToMessage = message;
    _inputFocusNode.requestFocus();
    setState(() {});
  }
  
  // Scroll to a specific message by ID
  void _scrollToMessage(String messageId) {
    final index = _items.indexWhere(
      (e) => _extractMessageId(e) == messageId,
    );
    if (index >= 0 && _scroll.hasClients) {
      // With reverse: true, we need to calculate the position
      // The last message is at position 0, so we need to scroll to (total - index)
      final reversedIndex = _items.length - 1 - index;
      final itemExtent = 100.0; // Approximate height per message
      final targetPosition = reversedIndex * itemExtent;
      
      _scroll.animateTo(
        targetPosition,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
      
      // Highlight the message briefly
      setState(() {
        _contextMenuMessageId = messageId;
      });
      
      Future.delayed(const Duration(milliseconds: 2000), () {
        if (mounted) {
          setState(() {
            _contextMenuMessageId = null;
          });
        }
      });
    }
  }
  
  // Build WhatsApp-style in-bubble reply preview widget
  Widget _buildReplyPreview(Map<String, dynamic> message, bool isMine) {
    final replyTo = message['replyTo'] ?? message['replyToMessage'];
    if (replyTo == null) return const SizedBox.shrink();
    
    // Get reply message data (could be from replyToMessage or need to find in _items)
    Map<String, dynamic>? replyMessage;
    if (replyTo is Map) {
      replyMessage = Map<String, dynamic>.from(replyTo);
    } else {
      // Find the original message in _items
      final replyId = replyTo.toString();
      try {
        final found = _items.firstWhere(
          (e) => _extractMessageId(e) == replyId,
        );
        replyMessage = Map<String, dynamic>.from(found);
      } catch (_) {
        replyMessage = null;
      }
    }
    
    if (replyMessage == null || replyMessage.isEmpty) return const SizedBox.shrink();
    
    final replyFrom = replyMessage['from']?.toString() ?? '';
    final replyIsMine = replyFrom == myId;
    final replyText = replyMessage['text']?.toString() ?? '';
    final replyFileType = replyMessage['fileType']?.toString();
    final replyFileName = replyMessage['fileName']?.toString();
    final replyFileUrl = replyMessage['fileUrl']?.toString();
    
    final isReplyVoice = replyFileType == 'audio' || replyFileType == 'voice';
    final isReplyImage = replyFileType == 'image' || 
        (replyFileUrl != null && _fileService.isImageFile(replyFileName));
    final isReplyVideo = replyFileType == 'video' ||
        (replyFileName != null && 
         (replyFileName.toLowerCase().endsWith('.mp4') ||
          replyFileName.toLowerCase().endsWith('.mov') ||
          replyFileName.toLowerCase().endsWith('.avi')));
    
    String previewText = '';
    if (isReplyVoice) {
      previewText = '🎤 Voice message';
    } else if (isReplyImage) {
      previewText = '📷 Photo';
    } else if (isReplyVideo) {
      previewText = '🎥 Video';
    } else if (replyFileUrl != null) {
      previewText = '📎 ${replyFileName ?? "File"}';
    } else {
      final cleanedText = replyText.replaceAll('🎤', '').trim();
      previewText = cleanedText.isEmpty ? 'Message' : cleanedText;
    }
    
    // WhatsApp-style: colored block with vertical bar on the left
    // Use a soft green tone similar to WhatsApp for replied section
    final Color barColor = const Color(0xFF25D366); // WhatsApp green
    final Color backgroundColor = const Color(0xFFE7FCE3); // light green background
    
    return GestureDetector(
      onTap: () {
        if (replyMessage != null && replyMessage.isNotEmpty) {
          final replyId = _extractMessageId(replyMessage);
          if (replyId.isNotEmpty) {
            _scrollToMessage(replyId);
          }
        }
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(6),
          border: Border(
            left: BorderSide(
              color: barColor,
              width: 3,
            ),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Vertical colored line is in the border
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Sender name (green, bold – like WhatsApp)
                  Text(
                    replyIsMine ? 'You' : (widget.peerName ?? widget.partnerEmail),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF128C7E), // WhatsApp name green
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  // Message preview
                  Text(
                    previewText,
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.black87,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            // Small thumbnail for images
            if (isReplyImage && replyFileUrl != null)
              Container(
                width: 40,
                height: 40,
                margin: const EdgeInsets.only(left: 8),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.grey[300]!),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: CachedNetworkImage(
                    imageUrl: replyFileUrl,
                    fit: BoxFit.cover,
                    errorWidget: (context, url, error) => const Icon(Icons.image, size: 20),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
  
  void _toggleEmojiPicker() {
    setState(() {
      final wasShowing = _showEmojiPicker;
      _showEmojiPicker = !_showEmojiPicker;
      
      if (_showEmojiPicker && !wasShowing) {
        // Showing emoji picker - hide keyboard but keep TextField visible
        // Use a combination approach: hide keyboard but maintain focus state
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _showEmojiPicker) {
            // Hide keyboard using SystemChannels
            SystemChannels.textInput.invokeMethod('TextInput.hide');
            // Ensure TextField remains visible by keeping it in the widget tree
            // Don't unfocus - this is what causes the TextField to disappear
          }
        });
      } else if (!_showEmojiPicker && wasShowing) {
        // Hiding emoji picker - show keyboard
        // Use a longer delay and check focus state to avoid conflicts
        Future.delayed(const Duration(milliseconds: 300), () {
          if (mounted && !_showEmojiPicker && _inputFocusNode.canRequestFocus) {
            // Only request focus if not already focused to avoid unnecessary requests
            if (!_inputFocusNode.hasFocus) {
              _inputFocusNode.requestFocus();
            }
          }
        });
      }
    });
  }
  
  Future<void> _copyMessage(Map<String, dynamic> message) async {
    final text = message['text']?.toString() ?? '';
    if (text.isNotEmpty) {
      await Clipboard.setData(ClipboardData(text: text));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Message copied to clipboard'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }
  
  Future<void> _forwardMessage(Map<String, dynamic> message) async {
    if (!mounted) return;
    
    // Show forward page as bottom sheet (Telegram-style)
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => ForwardMessagePage(message: message),
    );
  }
  
  Future<void> _pinMessage(String messageId) async {
    // TODO: Implement pin message (requires backend support)
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Pin feature coming soon')));
    }
  }
  
  Future<void> _starMessage(String messageId) async {
    // TODO: Implement star/favorite message (requires backend support)
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Message starred')));
    }
  }
  
  void _showMessageInfo(Map<String, dynamic> message) {
    final id = _extractMessageId(message);
    final createdAt = message['createdAt']?.toString() ?? 'Unknown';
    final edited = message['edited'] == true;
    final editedAt = message['editedAt']?.toString();
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Message Info'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Message ID: ${id.isEmpty ? 'Unknown' : id}'),
            const SizedBox(height: 8),
            Text('Sent: ${_fmtTime(createdAt)}'),
            if (edited) ...[
              const SizedBox(height: 8),
              Text('Edited: ${editedAt != null ? _fmtTime(editedAt) : 'Unknown'}'),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
  
  void _toggleSelectMode() {
    setState(() {
      _isSelectMode = !_isSelectMode;
      if (!_isSelectMode) {
        _selectedMessageIds.clear();
      }
    });
  }
  
  void _toggleMessageSelection(String messageId) {
    setState(() {
      if (_selectedMessageIds.contains(messageId)) {
        _selectedMessageIds.remove(messageId);
      } else {
        _selectedMessageIds.add(messageId);
      }
      if (_selectedMessageIds.isEmpty) {
        _isSelectMode = false;
      }
    });
  }
  
  void _selectAllMessages() {
    setState(() {
      // Select all messages (including call activity messages)
      for (final item in _items) {
        final id = _extractMessageId(item);
        if (id.isNotEmpty) {
          _selectedMessageIds.add(id);
        }
      }
    });
  }
  
  void _deselectAllMessages() {
    setState(() {
      _selectedMessageIds.clear();
      _isSelectMode = false;
    });
  }
  
  Future<void> _deleteSelectedMessages() async {
    if (_selectedMessageIds.isEmpty) return;
    
    // Check if any selected messages are owned by the user (for "Delete for everyone" option)
    final hasOwnMessages = _selectedMessageIds.any((id) {
      final idx = _items.indexWhere(
        (e) => (e['_id']?.toString() == id) || (e['id']?.toString() == id),
      );
      if (idx >= 0) {
        return _items[idx]['from']?.toString() == myId;
      }
      return false;
    });
    
    final deleteType = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(
          'Delete ${_selectedMessageIds.length} message${_selectedMessageIds.length > 1 ? 's' : ''}?',
        ),
        content: Text(
          hasOwnMessages
              ? 'This will delete the messages. Choose an option:'
              : 'These messages will be deleted only for you. The other person will still see them.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, null),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'me'),
            style: TextButton.styleFrom(foregroundColor: Colors.orange),
            child: const Text('Delete for me'),
          ),
          // Only show "Delete for everyone" if there are own messages
          if (hasOwnMessages)
            FilledButton(
              onPressed: () => Navigator.pop(context, 'everyone'),
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('Delete for everyone'),
            ),
        ],
      ),
    );
    
    if (deleteType == 'me') {
      // Collect indices to remove (in reverse order to avoid index shifting issues)
      final indicesToRemove = <int>[];
      for (final id in _selectedMessageIds) {
        final idx = _items.indexWhere(
          (e) => (e['_id']?.toString() == id) || (e['id']?.toString() == id),
        );
        if (idx >= 0) {
          final message = _items[idx];
          final isCallActivity = message['messageType']?.toString() == 'call_activity' ||
              message['callActivity'] == true;
          final isMine = message['from']?.toString() == myId;
          
          // For call activity messages, add to deletedForMeIds and remove from UI
          // For regular messages, use the delete API
          if (isCallActivity) {
            // Add to deletedForMeIds so they don't reappear when reloading
            _deletedForMeIds.add(id);
            indicesToRemove.add(idx);
          } else {
            await _deleteMessage(id, deleteForEveryone: false, isMine: isMine);
            indicesToRemove.add(idx);
          }
        }
      }
      // Save deletedForMeIds after processing all messages
      if (_deletedForMeIds.isNotEmpty) {
        await _saveDeletedForMeIds();
      }
      // Remove items in reverse order to maintain correct indices
      if (mounted && indicesToRemove.isNotEmpty) {
        setState(() {
          indicesToRemove.sort((a, b) => b.compareTo(a)); // Sort descending
          for (final idx in indicesToRemove) {
            if (idx >= 0 && idx < _items.length) {
              _items.removeAt(idx);
            }
          }
          _selectedMessageIds.clear();
          _isSelectMode = false;
        });
      } else if (mounted) {
        setState(() {
          _selectedMessageIds.clear();
          _isSelectMode = false;
        });
      }
    } else if (deleteType == 'everyone' && hasOwnMessages) {
      // Collect indices to remove (in reverse order to avoid index shifting issues)
      final indicesToRemove = <int>[];
      for (final id in _selectedMessageIds) {
        final idx = _items.indexWhere(
          (e) => (e['_id']?.toString() == id) || (e['id']?.toString() == id),
        );
        if (idx >= 0) {
          final message = _items[idx];
          final isCallActivity = message['messageType']?.toString() == 'call_activity' ||
              message['callActivity'] == true;
          final isMine = message['from']?.toString() == myId;
          
          // For call activity messages, add to deletedForMeIds and remove from UI
          if (isCallActivity) {
            // Add to deletedForMeIds so they don't reappear when reloading
            _deletedForMeIds.add(id);
            indicesToRemove.add(idx);
          } else {
            // Only delete for everyone if it's the user's own message
            if (isMine) {
              await _deleteMessage(id, deleteForEveryone: true, isMine: isMine);
            } else {
              // For other people's messages, just delete for me
              await _deleteMessage(id, deleteForEveryone: false, isMine: false);
            }
            indicesToRemove.add(idx);
          }
        }
      }
      // Save deletedForMeIds after processing all messages
      if (_deletedForMeIds.isNotEmpty) {
        await _saveDeletedForMeIds();
      }
      // Remove items in reverse order to maintain correct indices
      if (mounted && indicesToRemove.isNotEmpty) {
        setState(() {
          indicesToRemove.sort((a, b) => b.compareTo(a)); // Sort descending
          for (final idx in indicesToRemove) {
            if (idx >= 0 && idx < _items.length) {
              _items.removeAt(idx);
            }
          }
          _selectedMessageIds.clear();
          _isSelectMode = false;
        });
      } else if (mounted) {
        setState(() {
          _selectedMessageIds.clear();
          _isSelectMode = false;
        });
      }
    }
  }
  
  Future<String?> _showMessageActionMenu(
    Map<String, dynamic> message,
    bool isMine,
    Offset tapPosition,
  ) async {
    final id = _extractMessageId(message);
    
    // Set the message ID to show visual feedback
    setState(() {
      _contextMenuMessageId = id;
    });
    
    final RenderBox overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    
    // Position menu below the message bubble (standard messaging app pattern)
    // The tapPosition will be adjusted if we have message bubble context
    //message reply,Forward,Copy,Delete,Info,Select,Edit Function တွေကို သတ်မှတ်ထားတဲ့ နေရာ
    
    final result = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(tapPosition.dx - 20, tapPosition.dy + 10, 0, 0),
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
          value: 'delete',
          child: ListTile(
            leading: Icon(Icons.delete_outline, size: 20, color: Colors.black87),
            title: Text('Delete', style: TextStyle(color: Colors.black87)),
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
        const PopupMenuItem<String>(
          value: 'select',
          child: ListTile(
            leading: Icon(Icons.check_box_outline_blank, size: 20, color: Colors.black87),
            title: Text('Select', style: TextStyle(color: Colors.black87)),
            contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            dense: true,
          ),
        ),
        if (isMine)
          const PopupMenuItem<String>(
            value: 'edit',
            child: ListTile(
              leading: Icon(Icons.edit, size: 20, color: Colors.black87),
              title: Text('Edit', style: TextStyle(color: Colors.black87)),
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
    
    // Clear the visual feedback when menu closes
    if (mounted) {
      setState(() {
        _contextMenuMessageId = null;
      });
    }
    
    return result;
  }

  void _onDeleted(dynamic data) async {
    final m = Map<String, dynamic>.from(data);
    final id = _extractMessageId(m);
    if (id.isEmpty) return;

    final cid = m['conversationId']?.toString();
    if (conversationId != null && cid != null && cid != conversationId) return;

    final idx = _items.indexWhere(
      (e) => (e['_id']?.toString() == id) || (e['id']?.toString() == id),
    );
    if (idx >= 0) {
      if (!mounted) return;
      setState(() {
        _items[idx]['deleted'] = true;
        _items[idx]['text'] = '';
        _deletingIds.remove(id);
      });
      return;
    }

    _pendingDeletedIds.add(id);
    await _reconcileDeleted(id);
  }

  /// Get the storage key for deleted for me messages (conversation-specific)
  String _getDeletedForMeStorageKey() {
    if (conversationId != null && conversationId!.isNotEmpty) {
      return 'deleted_for_me_$conversationId';
    } else if (peerId != null && myId != null) {
      // Use sorted IDs to ensure same key regardless of order
      final ids = [myId!, peerId!]..sort();
      return 'deleted_for_me_${ids[0]}_${ids[1]}';
    }
    return 'deleted_for_me_default';
  }

  /// Get alternative storage keys to check (for migration)
  List<String> _getAlternativeStorageKeys() {
    final keys = <String>[];
    if (conversationId != null &&
        conversationId!.isNotEmpty &&
        peerId != null &&
        myId != null) {
      // Also check peerId-based key (for migration)
      final ids = [myId!, peerId!]..sort();
      keys.add('deleted_for_me_${ids[0]}_${ids[1]}');
    }
    return keys;
  }

  /// Load deleted for me message IDs from SharedPreferences
  Future<void> _loadDeletedForMeIds() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = _getDeletedForMeStorageKey();
      
      // Load from primary key
      final jsonStr = prefs.getString(key);
      if (jsonStr != null && jsonStr.isNotEmpty) {
        final List<dynamic> ids = jsonDecode(jsonStr);
        _deletedForMeIds.addAll(ids.map((id) => id.toString()));
      }
      
      // Check alternative keys for migration (when conversationId is discovered)
      final altKeys = _getAlternativeStorageKeys();
      for (final altKey in altKeys) {
        if (altKey != key) {
          final altJsonStr = prefs.getString(altKey);
          if (altJsonStr != null && altJsonStr.isNotEmpty) {
            final List<dynamic> altIds = jsonDecode(altJsonStr);
            _deletedForMeIds.addAll(altIds.map((id) => id.toString()));
            // Migrate to new key and remove old key
            await _saveDeletedForMeIds();
            await prefs.remove(altKey);
          }
        }
      }
    } catch (e) {
      debugPrint('Error loading deleted for me IDs: $e');
    }
  }

  /// Save deleted for me message IDs to SharedPreferences
  Future<void> _saveDeletedForMeIds() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = _getDeletedForMeStorageKey();
      final jsonStr = jsonEncode(_deletedForMeIds.toList());
      await prefs.setString(key, jsonStr);
    } catch (e) {
      debugPrint('Error saving deleted for me IDs: $e');
    }
  }

  Future<void> _deleteMessage(
    String id, {
    bool deleteForEveryone = true,
    required bool isMine,
  }) async {
    setState(() => _deletingIds.add(id));

    // Viber-style: Only allow "Delete for everyone" for own messages
    if (!deleteForEveryone) {
      // Delete for me only - handle locally (works for any message)
      _deletedForMeIds.add(id); // Store in set to persist across reloads
      await _saveDeletedForMeIds(); // Persist to SharedPreferences
      setState(() {
        _applyDeleteLocally(id);
        _deletingIds.remove(id);
        // Mark as deleted locally for this user only
        final idx = _items.indexWhere(
          (e) => (e['_id']?.toString() == id) || (e['id']?.toString() == id),
        );
        if (idx >= 0) {
          _items[idx]['deletedForMe'] = true;
          _items[idx]['text'] = '';
        }
      });
      return;
    }

    // Delete for everyone - only works for own messages (enforced by backend)
    if (!isMine) {
      // Safety check: Should not happen, but handle gracefully
      if (!mounted) return;
      setState(() => _deletingIds.remove(id));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You can only delete your own messages for everyone'),
        ),
      );
      return;
    }

    // Delete for everyone - call API (only for own messages)
    final r = await http.delete(
      Uri.parse('$apiBase/api/messages/$id'),
      headers: await authHeaders(),
    );

    if (r.statusCode == 200) {
      try {
        final body = jsonDecode(r.body) as Map<String, dynamic>;
        final mid = (body['message']?['_id'] ?? body['message']?['id'] ?? id)
            .toString();
        setState(() {
          _applyDeleteLocally(mid);
          _deletingIds.remove(mid);
        });
      } catch (_) {
        setState(() {
          _applyDeleteLocally(id);
          _deletingIds.remove(id);
        });
      }
    } else {
      if (!mounted) return;
      setState(() => _deletingIds.remove(id));
      final msg = r.statusCode == 403
          ? 'Only the sender can delete this message for everyone'
          : 'Delete failed (${r.statusCode})';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  Future<void> _reconcileDeleted(String id) async {
    await _loadHistory();
    if (!mounted) return;
    setState(() {
      _applyDeleteLocally(id);
      _deletingIds.remove(id);
    });
  }

  Future<void> _logout() async {
    await AuthStore.clear();
    SocketService.I.disconnect();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginPage()),
      (_) => false,
    );
  }

  @override
  void dispose() {
    // Restore system UI
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.dark);
    _peerTypingClear?.cancel();
    _searchController.dispose();
    _searchFocusNode.dispose();
    _presenceTicker?.cancel();
    _readDebounce?.cancel();
    _presencePulse.dispose();
    _input.dispose();
    _inputFocusNode.dispose();
    _scroll.dispose();
    _voiceService.dispose();
    SocketService.I.off('call:incoming', _onCallIncoming);
    SocketService.I.off('call:ringing', _onCallRinging);
    SocketService.I.off('call:ended', _onCallEnded);
    SocketService.I.off('call:answer', _onCallAnswer);
    SocketService.I.off('call:hangup', _onCallHangup);
    SocketService.I.off('call:declined', _onCallDeclined);
    _callStatusTimer?.cancel();
    SocketService.I.off('message', _onMessage);
    SocketService.I.off('chat_request_accepted', _onAccepted);
    SocketService.I.off('message_deleted', _onDeleted);
    SocketService.I.off('delivered', _onDeliveredEvt);
    SocketService.I.off('read_up_to', _onReadUpToEvt);
    SocketService.I.off('presence', _onPresence);
    SocketService.I.off('presence:initial', _onPresenceInitial);
    SocketService.I.off('typing', _onTyping);
    SocketService.I.off('message_edited', _onEdited);
    ForegroundChat.currentPeerId = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.peerName?.trim().isNotEmpty == true
        ? widget.peerName!.trim()
        : widget.partnerEmail;

    final bool canSend = composerEnabled && _hasText;

    // Get background from theme service
    final themeService = ThemeService();
    final chatBackground = themeService.getChatBackground();

    // Default gradient if no custom background - Light blue gradient
    final defaultGradientBg = LinearGradient(
      colors: [
        const Color(0xFFE3F2FD), // Light blue (top)
        const Color(0xFFBBDEFB), // Slightly darker blue (bottom)
      ],
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
    );

    // Hide system status bar completely
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.edgeToEdge,
      overlays: [
        SystemUiOverlay.bottom,
      ], // Only show navigation bar, hide status bar
    );
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        systemNavigationBarColor: Colors.transparent,
      ),
    );

    return Scaffold(
      extendBody: true,
      appBar: _buildAppBar(context),
      body: Container(
        decoration:
            chatBackground ?? BoxDecoration(gradient: defaultGradientBg),
        child: Column(
          children: [
            // Viber-style call status banner
            if (_activeCallId != null && _activeCallStatus != null)
              CallStatusBanner(
                peerName: widget.peerName ?? widget.partnerEmail,
                isVideoCall: _isActiveCallVideo,
                isOutgoing: _isActiveCallOutgoing,
                status: _activeCallStatus!,
                onReturnToCall: () {
                  // Navigate back to call page
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => CallPage(
                        peerId: peerId!,
                        peerName: widget.peerName ?? widget.partnerEmail,
                        outgoing: _isActiveCallOutgoing,
                        video: _isActiveCallVideo,
                        initialCallId: _activeCallId,
                      ),
                    ),
                  );
                },
                onEndCall: () {
                  // End the call
                  SocketService.I.emit('call:hangup', {
                    'callId': _activeCallId,
                  });
                  setState(() {
                    _activeCallId = null;
                    _activeCallStatus = null;
                  });
                },
              ),
            if (_showSearchBar)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                child: Row(
                  children: [
                    Expanded(child: _buildSearchBar(context)),
                    const SizedBox(width: 4),
                    TextButton(
                      onPressed: _closeSearchOverlay,
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Text(
                        'Cancel',
                        style: TextStyle(
                          fontSize: 14,
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            if (!composerEnabled)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.all(12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.amber.withOpacity(.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.hourglass_top, size: 18),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Pending… receiver must accept your request.',
                      ),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: Stack(
                children: [
                  loading
                      ? const Center(child: CircularProgressIndicator())
                      : ListView.builder(
                          controller: _scroll,
                          reverse: true, // Start at bottom (last message)
                          padding: const EdgeInsets.fromLTRB(12, 96, 12, 12),
                          itemCount: _items.length,
                          itemBuilder: (_, i) {
                            // Reverse index to show newest messages at bottom
                            final reversedIndex = _items.length - 1 - i;
                            final m = _items[reversedIndex];
                            final id = (m['_id'] ?? m['id'] ?? '').toString();
                            final mine = m['from']?.toString() == myId;
                            final isDeleted =
                                (m['deleted'] == true) ||
                                (m['deletedForMe'] == true);
                            final deleting =
                                _deletingIds.contains(id) && !isDeleted;
                            final createdAt = _fmtTime(
                              m['createdAt']?.toString(),
                            );
                            final edited = (m['edited'] == true);
                            final fileUrl = m['fileUrl']?.toString();
                            final fileName = m['fileName']?.toString();
                            final fileType = m['fileType']?.toString();
                            final hasFile =
                                fileUrl != null && fileUrl.isNotEmpty;
                            
                            // Debug logging for video messages
                            if (fileType == 'video' || (fileName != null && fileName.toLowerCase().endsWith('.mp4'))) {
                              debugPrint('Video message detected: fileType=$fileType, fileName=$fileName, fileUrl=$fileUrl');
                            }
                            // Improved image detection: check fileType, file extension, and URL extension
                            final urlExt =
                                fileUrl != null && fileUrl.contains('.')
                                ? fileUrl
                                      .toLowerCase()
                                      .split('.')
                                      .last
                                      .split('?')
                                      .first
                                : '';
                            final isImage =
                                hasFile &&
                                (fileType == 'image' ||
                              _fileService.isImageFile(fileName) ||
                                    (urlExt.isNotEmpty &&
                                        [
                                          'jpg',
                                          'jpeg',
                                          'png',
                                          'gif',
                                          'webp',
                                          'bmp',
                                        ].contains(urlExt)));
                            final isVoice =
                                hasFile &&
                                (fileType == 'audio' ||
                                    fileType == 'voice' ||
                                    (fileName?.endsWith('.m4a') ?? false) ||
                                    (fileName?.endsWith('.mp3') ?? false));
                            final isVideo =
                                hasFile &&
                                (fileType == 'video' ||
                                    (urlExt.isNotEmpty &&
                                        [
                                          'mp4',
                                          'mov',
                                          'avi',
                                          'mkv',
                                          'webm',
                                          '3gp',
                                        ].contains(urlExt)) ||
                                    (fileName != null &&
                                        (fileName.toLowerCase().endsWith('.mp4') ||
                                            fileName.toLowerCase().endsWith('.mov') ||
                                            fileName.toLowerCase().endsWith('.avi') ||
                                            fileName.toLowerCase().endsWith('.mkv') ||
                                            fileName.toLowerCase().endsWith('.webm') ||
                                            fileName.toLowerCase().endsWith('.3gp'))));
                            
                            // Check if this is a call activity message
                            final text = m['text']?.toString() ?? '';
                            // Check if this is an image-only message (no text, just image)
                            final isImageOnly =
                                isImage &&
                                (text.isEmpty ||
                                    text.trim().isEmpty ||
                                    text == '📎 ${fileName ?? "File"}');
                            // Check if this is a video-only message (no text, just video)
                            final isVideoOnly =
                                isVideo &&
                                (text.isEmpty ||
                                    text.trim().isEmpty ||
                                    text == '📎 ${fileName ?? "File"}');
                            // Check if this is a voice-only message (no text, just voice)
                            // Hide text if: empty, default file text, voice emoji placeholder, or filename matches voice pattern
                            final isVoiceOnly =
                                isVoice &&
                                (text.isEmpty ||
                                    text.trim().isEmpty ||
                                    text.trim() == '🎤' ||
                                    text == '📎 ${fileName ?? "File"}' ||
                                    (fileName != null && text.trim() == fileName) ||
                                    (fileName != null && fileName.startsWith('voice_')) ||
                                    (fileName != null && fileName.endsWith('.m4a') && text.trim().contains(fileName)));
                            final isCallActivity =
                                m['messageType']?.toString() ==
                                    'call_activity' ||
                                m['callActivity'] == true ||
                                text.startsWith('📞') ||
                                (text.contains('call') && 
                                 (text.contains('missed') ||
                                  text.contains('declined') ||
                                  text.contains('cancelled')));

                            // Slide+fade-in per item
                            return TweenAnimationBuilder<double>(
                              key: ValueKey(
                                id.isNotEmpty ? id : '$i-${m['createdAt']}',
                              ),
                              tween: Tween(begin: 1, end: 0),
                              duration: const Duration(milliseconds: 320),
                              curve: Curves.easeOutCubic,
                              builder: (context, value, child) => Opacity(
                                opacity: (1 - value).clamp(0, 1),
                                child: Transform.translate(
                                  offset: Offset(0, 12 * value),
                                  child: child,
                                ),
                              ),
                              child: Stack(
                                  clipBehavior: Clip.none,
                                  children: [
                                    // Selection checkbox - positioned at absolute left edge
                                    if (_isSelectMode)
                                      Positioned(
                                        left: 12,
                                        top: 0,
                                        bottom: 0,
                                        child: Center(
                                          child: GestureDetector(
                                            onTap: () => _toggleMessageSelection(id),
                                            child: Container(
                                              width: 24,
                                              height: 24,
                                              decoration: BoxDecoration(
                                                shape: BoxShape.circle,
                                                color: _selectedMessageIds.contains(id)
                                                    ? Theme.of(context).colorScheme.primary
                                                    : Colors.transparent,
                                                border: Border.all(
                                                  color: _selectedMessageIds.contains(id)
                                                      ? Theme.of(context).colorScheme.primary
                                                      : Colors.white,
                                                  width: 2,
                                                ),
                                              ),
                                              child: _selectedMessageIds.contains(id)
                                                  ? const Center(
                                                      child: Icon(
                                                        Icons.check,
                                                        color: Colors.white,
                                                        size: 16,
                                                      ),
                                                    )
                                                  : null,
                                            ),
                                          ),
                                        ),
                                      ),
                                    // Message content (call activity or regular message)
                                    // Make entire area tappable in select mode for call activity messages
                                    if (_isSelectMode && isCallActivity)
                                      Positioned.fill(
                                        child: GestureDetector(
                                          behavior: HitTestBehavior.opaque,
                                          onTap: () => _toggleMessageSelection(id),
                                        ),
                                      ),
                                    Align(
                                      alignment: isCallActivity
                                          ? Alignment.center
                                          : (mine ? Alignment.centerRight : Alignment.centerLeft),
                                      child: Padding(
                                        padding: EdgeInsets.only(
                                          left: _isSelectMode ? 48 : 0,
                                          right: 0,
                                        ),
                                        child: isCallActivity
                                            ? IgnorePointer(
                                                ignoring: _isSelectMode,
                                                child: _buildCallActivityMessage(
                                                  m,
                                                  mine,
                                                  onTap: null, // Don't pass onTap when in select mode
                                                ),
                                              )
                                            : Row(
                                                mainAxisSize: MainAxisSize.min,
                                                crossAxisAlignment: CrossAxisAlignment.end,
                                                children: [
                                                  // Profile picture for received messages (left side)
                                                  if (!mine && !isCallActivity)
                                                    Padding(
                                                      padding: const EdgeInsets.only(
                                                        right: 8,
                                                        bottom: 4,
                                                        left: 8,
                                                      ),
                                                      child: ClipOval(
                                                        child: _peerProfile?['avatarUrl'] != null &&
                                                                (_peerProfile!['avatarUrl']?.toString() ?? '').isNotEmpty
                                                            ? CachedNetworkImage(
                                                                imageUrl: _peerProfile!['avatarUrl'].toString(),
                                                                width: 36,
                                                                height: 36,
                                                                fit: BoxFit.cover,
                                                                errorWidget: (context, url, error) => CircleAvatar(
                                                                  radius: 18,
                                                                  backgroundColor: Colors.grey[300],
                                                                  child: Text(
                                                                    (widget.peerName ?? widget.partnerEmail)
                                                                        .substring(0, 1)
                                                                        .toUpperCase(),
                                                                    style: const TextStyle(
                                                                      color: Colors.white,
                                                                      fontSize: 14,
                                                                      fontWeight: FontWeight.bold,
                                                                    ),
                                                                  ),
                                                                ),
                                                                placeholder: (context, url) => CircleAvatar(
                                                                  radius: 18,
                                                                  backgroundColor: Colors.grey[300],
                                                                  child: const SizedBox(
                                                                    width: 18,
                                                                    height: 18,
                                                                    child: CircularProgressIndicator(strokeWidth: 2),
                                                                  ),
                                                                ),
                                                              )
                                                            : CircleAvatar(
                                                                radius: 18,
                                                                backgroundColor: Colors.grey[300],
                                                                child: Text(
                                                                  (widget.peerName ?? widget.partnerEmail)
                                                                      .substring(0, 1)
                                                                      .toUpperCase(),
                                                                  style: const TextStyle(
                                                                    color: Colors.white,
                                                                    fontSize: 14,
                                                                    fontWeight: FontWeight.bold,
                                                                  ),
                                                                ),
                                                              ),
                                                      ),
                                                    ),
                                                  Flexible(
                                                    child: GestureDetector(
                                  onTap: _isSelectMode
                                      ? () => _toggleMessageSelection(id)
                                      : null,
                                  // Swipe to reply gesture
                                  onHorizontalDragStart: (!isDeleted &&
                                          composerEnabled &&
                                          !deleting &&
                                          !isCallActivity &&
                                          !_isSelectMode)
                                      ? (DragStartDetails details) {
                                          setState(() {
                                            _swipingMessageId = id;
                                            _swipeOffset = 0.0;
                                          });
                                        }
                                      : null,
                                  onHorizontalDragUpdate: (!isDeleted &&
                                          composerEnabled &&
                                          !deleting &&
                                          !isCallActivity &&
                                          !_isSelectMode &&
                                          _swipingMessageId == id)
                                      ? (DragUpdateDetails details) {
                                          // For received messages (mine = false), swipe left (negative)
                                          // For sent messages (mine = true), swipe right (positive)
                                          final delta = details.primaryDelta ?? 0.0;
                                          final newOffset = _swipeOffset + delta;
                                          
                                          // Constrain swipe direction based on message alignment
                                          if (mine) {
                                            // Sent messages: only allow right swipe (positive)
                                            if (newOffset >= 0 && newOffset <= _swipeThreshold) {
                                              setState(() {
                                                _swipeOffset = newOffset;
                                              });
                                            }
                                          } else {
                                            // Received messages: only allow left swipe (negative)
                                            if (newOffset <= 0 && newOffset >= -_swipeThreshold) {
                                              setState(() {
                                                _swipeOffset = newOffset;
                                              });
                                            }
                                          }
                                        }
                                      : null,
                                  onHorizontalDragEnd: (!isDeleted &&
                                          composerEnabled &&
                                          !deleting &&
                                          !isCallActivity &&
                                          !_isSelectMode &&
                                          _swipingMessageId == id)
                                      ? (DragEndDetails details) {
                                          // Check if swipe threshold is reached
                                          final absOffset = _swipeOffset.abs();
                                          if (absOffset >= _swipeThreshold * 0.6) {
                                            // Trigger reply
                                            _startReply(m);
                                            // Haptic feedback
                                            HapticFeedback.lightImpact();
                                          }
                                          
                                          // Reset swipe state with animation
                                          setState(() {
                                            _swipeOffset = 0.0;
                                            _swipingMessageId = null;
                                          });
                                        }
                                      : null,
                                  onLongPressStart:
                                      (!isDeleted &&
                                          composerEnabled &&
                                          !deleting &&
                                          !isCallActivity) // Call activity messages are NOT editable/deletable
                                      ? (LongPressStartDetails details) async {
                                          if (_isSelectMode) {
                                            _toggleMessageSelection(id);
                                            return;
                                          }
                                          
                                          final action =
                                                    await _showMessageActionMenu(
                                                      m,
                                                      mine,
                                                      details.globalPosition,
                                                    );
                                          
                                          if (action == 'reply') {
                                            _startReply(m);
                                          } else if (action == 'copy') {
                                            await _copyMessage(m);
                                                } else if (action ==
                                                    'forward') {
                                            await _forwardMessage(m);
                                          } else if (action == 'info') {
                                            _showMessageInfo(m);
                                          } else if (action == 'select') {
                                            // Enter selection mode and select this message
                                            setState(() {
                                              _isSelectMode = true;
                                              _selectedMessageIds.add(id);
                                            });
                                          } else if (action == 'edit') {
                                            _startEdit(m);
                                          } else if (action == 'delete') {
                                            // Viber-style: Only show "Delete for everyone" for own messages
                                            final deleteType = await showDialog<String>(
                                              context: context,
                                              builder: (_) => AlertDialog(
                                                title: Text(
                                                        mine
                                                            ? 'Delete message?'
                                                            : 'Delete message for you?',
                                                ),
                                                content: Text(
                                                  mine
                                                      ? 'This message will be deleted. Choose an option:'
                                                      : 'This message will be deleted only for you. The other person will still see it.',
                                                ),
                                                actions: [
                                                  TextButton(
                                                    onPressed: () =>
                                                              Navigator.pop(
                                                                context,
                                                                null,
                                                              ),
                                                          child: const Text(
                                                            'Cancel',
                                                          ),
                                                  ),
                                                  TextButton(
                                                    onPressed: () =>
                                                              Navigator.pop(
                                                                context,
                                                                'me',
                                                              ),
                                                          style:
                                                              TextButton.styleFrom(
                                                                foregroundColor:
                                                                    Colors
                                                                        .orange,
                                                    ),
                                                          child: const Text(
                                                            'Delete for me',
                                                          ),
                                                  ),
                                                  // Only show "Delete for everyone" for own messages
                                                  if (mine)
                                                    FilledButton(
                                                      onPressed: () =>
                                                                Navigator.pop(
                                                                  context,
                                                                  'everyone',
                                                                ),
                                                            style:
                                                                FilledButton.styleFrom(
                                                                  backgroundColor:
                                                                      Colors
                                                                          .red,
                                                      ),
                                                            child: const Text(
                                                              'Delete for everyone',
                                                            ),
                                                    ),
                                                ],
                                              ),
                                            );
                                            if (deleteType == 'me') {
                                                    await _deleteMessage(
                                                      id,
                                                      deleteForEveryone: false,
                                                      isMine: mine,
                                                    );
                                                  } else if (deleteType ==
                                                          'everyone' &&
                                                      mine) {
                                                    await _deleteMessage(
                                                      id,
                                                      deleteForEveryone: true,
                                                      isMine: mine,
                                                    );
                                            }
                                          }
                                        }
                                      : null,
                                  child: Stack(
                                    clipBehavior: Clip.none,
                                    children: [
                                      // Reply icon (shown behind message during swipe)
                                      if (_swipingMessageId == id && _swipeOffset.abs() > 10)
                                        Positioned(
                                          left: mine ? null : 20,
                                          right: mine ? 20 : null,
                                          top: 0,
                                          bottom: 0,
                                          child: Center(
                                            child: Opacity(
                                              opacity: (_swipeOffset.abs() / _swipeThreshold).clamp(0.0, 1.0),
                                              child: Transform.scale(
                                                scale: (_swipeOffset.abs() / _swipeThreshold * 0.5 + 0.5).clamp(0.5, 1.0),
                                                child: Icon(
                                                  Icons.reply,
                                                  color: Theme.of(context).colorScheme.primary,
                                                  size: 24,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      // Message bubble with swipe transform
                                      Transform.translate(
                                        offset: Offset(_swipingMessageId == id ? _swipeOffset : 0.0, 0),
                                        child: AnimatedContainer(
                                              duration: const Duration(
                                                milliseconds: 220,
                                              ),
                                        constraints: BoxConstraints(
                                          maxWidth: MediaQuery.of(context).size.width * 0.75,
                                        ),
                                        margin: EdgeInsets.only(
                                          top: 4,
                                          bottom: 4,
                                          left: mine ? 50 : 8,
                                          right: mine ? 8 : 50,
                                        ),
                                              padding: (isImageOnly || isVideoOnly)
                                                  ? EdgeInsets.zero
                                                  : const EdgeInsets.symmetric(
                                          vertical: 10,
                                          horizontal: 14,
                                        ),
                                              decoration: (isImageOnly || isVideoOnly)
                                                  ? (_contextMenuMessageId == id
                                                      ? BoxDecoration(
                                                          border: Border.all(
                                                            color: Theme.of(context).colorScheme.primary.withOpacity(0.5),
                                                            width: 2,
                                                          ),
                                                          borderRadius: BorderRadius.only(
                                                            topLeft: const Radius.circular(18),
                                                            topRight: const Radius.circular(18),
                                                            bottomLeft: Radius.circular(mine ? 18 : 4),
                                                            bottomRight: Radius.circular(mine ? 4 : 18),
                                                          ),
                                                          boxShadow: [
                                                            BoxShadow(
                                                              color: Theme.of(context).colorScheme.primary.withOpacity(0.3),
                                                              blurRadius: 8,
                                                              spreadRadius: 1,
                                                              offset: const Offset(0, 0),
                                                            ),
                                                          ],
                                                        )
                                                      : null)
                                                  : BoxDecoration(
                                          gradient: isDeleted
                                              ? null
                                              : LinearGradient(
                                                  colors: [
                                                          // White bubbles for all messages (matching image)
                                                          Colors.white,
                                                          Colors.white,
                                                        ],
                                                              begin: Alignment
                                                                  .topLeft,
                                                              end: Alignment
                                                                  .bottomRight,
                                                ),
                                          color: isDeleted
                                              ? Colors.grey.shade400
                                              : null,
                                          border: _contextMenuMessageId == id
                                              ? Border.all(
                                                  color: Theme.of(context).colorScheme.primary.withOpacity(0.5),
                                                  width: 2,
                                                )
                                              : null,
                                          borderRadius: BorderRadius.only(
                                                        topLeft:
                                                            const Radius.circular(
                                                              18,
                                                            ),
                                                        topRight:
                                                            const Radius.circular(
                                                              18,
                                                            ),
                                                        bottomLeft:
                                                            Radius.circular(
                                                              mine ? 18 : 4,
                                                            ),
                                                        bottomRight:
                                                            Radius.circular(
                                                              mine ? 4 : 18,
                                                            ),
                                          ),
                                          boxShadow: [
                                            BoxShadow(
                                              color: Colors.black.withOpacity(0.1), // Subtle shadow for white bubbles
                                              blurRadius: 4,
                                              spreadRadius: 0,
                                              offset: const Offset(0, 2),
                                            ),
                                            // Add a subtle glow when context menu is open
                                            if (_contextMenuMessageId == id)
                                              BoxShadow(
                                                color: Theme.of(context).colorScheme.primary.withOpacity(0.3),
                                                blurRadius: 8,
                                                spreadRadius: 1,
                                                offset: const Offset(0, 0),
                                            ),
                                          ],
                                        ),
                                        child: Column(
                                          crossAxisAlignment: mine
                                              ? CrossAxisAlignment.end
                                              : CrossAxisAlignment.start,
                                          children: [
                                                  // Reply header for replied messages, using reusable ReplyBubble widget
                                                  Builder(
                                                    builder: (_) {
                                                      // Check if this message has reply data
                                                      // Handle different possible key formats
                                                      final replyTo = m['replyTo'] ?? m['reply_to'];
                                                      final replyToMessage = m['replyToMessage'] ?? m['reply_to_message'];
                                                      // Check if reply data exists (not null, not empty string, not empty map)
                                                      final hasReplyTo = replyTo != null && 
                                                        replyTo.toString().trim().isNotEmpty;
                                                      final hasReplyToMessage = replyToMessage != null && 
                                                        (replyToMessage is Map ? (replyToMessage as Map).isNotEmpty : 
                                                         replyToMessage.toString().trim().isNotEmpty);
                                                      final hasReply = !isDeleted && (hasReplyTo || hasReplyToMessage);
                                                      
                                                      // Debug: Log reply data with detailed info
                                                      if (replyTo != null || replyToMessage != null) {
                                                        debugPrint('🎨 REPLY DATA CHECK for message $id:');
                                                        debugPrint('   isDeleted: $isDeleted');
                                                        debugPrint('   replyTo: $replyTo (type: ${replyTo?.runtimeType})');
                                                        debugPrint('   replyToMessage: $replyToMessage (type: ${replyToMessage?.runtimeType})');
                                                        debugPrint('   hasReply: $hasReply');
                                                        if (replyToMessage is Map) {
                                                          debugPrint('   replyToMessage content: $replyToMessage');
                                                        }
                                                      } else {
                                                        debugPrint('🎨 NO REPLY DATA for message $id');
                                                      }
                                                      
                                                      if (!hasReply) {
                                                        return const SizedBox.shrink();
                                                      }
                                                      
                                                      // Try to resolve original message text and sender
                                                      // (replyTo and replyToMessage are already defined above)
                                                      final messageFrom = m['from']?.toString();
                                                      final isReceivedMessage = messageFrom != null && messageFrom != myId;
                                                      
                                                      String originalText = '';
                                                      String originalSender = widget.peerName ?? widget.partnerEmail;
                                                      String? originalFileUrl;
                                                      String? originalFileType;
                                                      String? originalFileName;
                                                      int? originalAudioDuration;

                                                      debugPrint('🎨 RENDERING REPLY UI: messageId=$id, isReceived=$isReceivedMessage, replyTo=$replyTo, replyToMessage=$replyToMessage');

                                                      // If replyToMessage is a Map, use it directly
                                                      if (replyToMessage is Map) {
                                                        final rm = Map<String, dynamic>.from(replyToMessage);
                                                        originalText = (rm['text'] ?? '').toString();
                                                        originalFileUrl = rm['fileUrl']?.toString();
                                                        originalFileType = rm['fileType']?.toString();
                                                        originalFileName = rm['fileName']?.toString();
                                                        originalAudioDuration = rm['audioDuration'] is int 
                                                            ? rm['audioDuration'] as int?
                                                            : (rm['audioDuration'] != null ? int.tryParse(rm['audioDuration'].toString()) : null);
                                                        final replyFrom = rm['from']?.toString();
                                                        
                                                        // Determine sender name: "You" if original message was from current user, otherwise peer name
                                                        if (replyFrom != null) {
                                                          if (replyFrom == myId) {
                                                            originalSender = 'You';
                                                          } else {
                                                            // Original message was from the peer - use peer name
                                                            originalSender = widget.peerName ?? widget.partnerEmail;
                                                          }
                                                        } else {
                                                          // Fallback: if no 'from' field, try to infer from context
                                                          // If this is a received message, the original was likely from the sender
                                                          if (isReceivedMessage && messageFrom != null) {
                                                            // The original message was from the person who sent this reply
                                                            originalSender = widget.peerName ?? widget.partnerEmail;
                                                          }
                                                        }
                                                        
                                                        debugPrint('🎨 REPLY PREVIEW: Using replyToMessage Map - sender=$originalSender, text=$originalText, fileType=$originalFileType, fileUrl=$originalFileUrl, fileName=$originalFileName, replyFrom=$replyFrom, myId=$myId, isReceived=$isReceivedMessage');
                                                        debugPrint('🎨 REPLY PREVIEW: Full replyToMessage Map: $rm');
                                                      } else if (replyTo != null) {
                                                        // If replyTo is an ID, look up the message in _items
                                                        final replyId = replyTo.toString();
                                                        try {
                                                          final found = _items.firstWhere(
                                                            (e) => _extractMessageId(e) == replyId,
                                                          );
                                                          originalText = (found['text'] ?? '').toString();
                                                          originalFileUrl = found['fileUrl']?.toString();
                                                          originalFileType = found['fileType']?.toString();
                                                          originalFileName = found['fileName']?.toString();
                                                          originalAudioDuration = found['audioDuration'] is int 
                                                              ? found['audioDuration'] as int?
                                                              : (found['audioDuration'] != null ? int.tryParse(found['audioDuration'].toString()) : null);
                                                          final from = found['from']?.toString();
                                                          
                                                          // Determine sender name based on who sent the original message
                                                          if (from == myId) {
                                                            originalSender = 'You';
                                                          } else {
                                                            // Original message was from the peer
                                                            originalSender = widget.peerName ?? widget.partnerEmail;
                                                          }
                                                          
                                                          debugPrint('🎨 REPLY PREVIEW: Found original message by ID - sender=$originalSender, text=$originalText, fileType=$originalFileType, fileUrl=$originalFileUrl, originalFrom=$from');
                                                        } catch (_) {
                                                          debugPrint('🎨 REPLY PREVIEW: Could not find original message with ID: $replyId');
                                                          // If we can't find the original message, show a default
                                                          originalText = 'Message';
                                                          // Try to infer sender from context
                                                          if (isReceivedMessage && messageFrom != null) {
                                                            originalSender = widget.peerName ?? widget.partnerEmail;
                                                          }
                                                        }
                                                      }

                                                      // If still empty and no file, show default
                                                      if (originalText.isEmpty && originalFileUrl == null) {
                                                        originalText = 'Message';
                                                      }

                                                      debugPrint('🎨 REPLY PREVIEW RENDERING: sender=$originalSender, text=$originalText, fileType=$originalFileType, fileUrl=$originalFileUrl, fileName=$originalFileName, audioDuration=$originalAudioDuration, messageId=$id, isReceived=$isReceivedMessage');
                                                      debugPrint('🎨 REPLY PREVIEW: isImage=${originalFileType == 'image' && originalFileUrl != null}, isVideo=${originalFileType == 'video' && originalFileUrl != null}, isAudio=${(originalFileType == 'audio' || originalFileType == 'voice') && originalFileUrl != null}');
                                                      return ReplyBubble(
                                                        senderName: originalSender,
                                                        messageText: originalText,
                                                        fileUrl: originalFileUrl,
                                                        fileType: originalFileType,
                                                        fileName: originalFileName,
                                                        audioDuration: originalAudioDuration,
                                                      );
                                                    },
                                                  ),
                                                  // File/Image/Video/Voice display
                                                  if (hasFile &&
                                                      !isDeleted) ...[
                                                    if (!isImageOnly && !isVideoOnly && !isVoiceOnly)
                                          const SizedBox(height: 4),
                                          if (isVoice)
                                            VoiceMessagePlayer(
                                              audioUrl: fileUrl!,
                                              isMe: mine,
                                                        duration:
                                                            m['audioDuration']
                                                                as int?,
                                            )
                                          else if (isImage)
                                                      Builder(
                                                        builder: (_) {
                                                          // Check if image has been seen
                                                          final createdIso =
                                                              m['createdAt']
                                                                  ?.toString() ??
                                                              '';
                                                          final created =
                                                              DateTime.tryParse(
                                                                createdIso,
                                                              );
                                                          final isSeen =
                                                              mine &&
                                                              created != null &&
                                                              _readUpToPeer !=
                                                                  null &&
                                                              !created.isAfter(
                                                                _readUpToPeer!,
                                                              );
                                                          final isDelivered =
                                                              mine &&
                                                              created != null &&
                                                              _deliveredUpToPeer !=
                                                                  null &&
                                                              !created.isAfter(
                                                                _deliveredUpToPeer!,
                                                              );

                                                          return GestureDetector(
                                                onTap: () {
                                                  Navigator.push(
                                                    context,
                                                    MaterialPageRoute(
                                                      builder: (_) => Scaffold(
                                                        appBar: AppBar(
                                                                      title: Text(
                                                                        fileName ??
                                                                            'Image',
                                                                      ),
                                                        ),
                                                        body: Center(
                                                          child: InteractiveViewer(
                                                            child: CachedNetworkImage(
                                                                          imageUrl:
                                                                              fileUrl!,
                                                                          fit: BoxFit
                                                                              .contain,
                                                                          placeholder:
                                                                              (
                                                                                context,
                                                                                url,
                                                                              ) => const Center(
                                                                child: CircularProgressIndicator(),
                                                              ),
                                                                          errorWidget:
                                                                              (
                                                                                context,
                                                                                url,
                                                                                error,
                                                                              ) => const Icon(
                                                                Icons.broken_image,
                                                                size: 64,
                                                                color: Colors.white,
                                                              ),
                                                            ),
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                  );
                                                },
                                                            child: Container(
                                                              decoration: BoxDecoration(
                                                                borderRadius:
                                                                    BorderRadius.circular(
                                                                      8,
                                                                    ),
                                                                border: isSeen
                                                                    ? Border.all(
                                                                        color: const Color(
                                                                          0xFF4A90E2,
                                                                        ).withOpacity(0.6),
                                                                        width:
                                                                            2.5,
                                                                      )
                                                                    : (isDelivered
                                                                          ? Border.all(
                                                                              color: Colors.white.withOpacity(
                                                                                0.3,
                                                                              ),
                                                                              width: 1.5,
                                                                            )
                                                                          : null),
                                                                boxShadow:
                                                                    isSeen
                                                                    ? [
                                                                        BoxShadow(
                                                                          color: const Color(
                                                                            0xFF4A90E2,
                                                                          ).withOpacity(0.3),
                                                                          blurRadius:
                                                                              8,
                                                                          spreadRadius:
                                                                              1,
                                                                        ),
                                                                      ]
                                                                    : null,
                                                              ),
                                                              child: ClipRRect(
                                                                borderRadius:
                                                                    BorderRadius.circular(
                                                                      6,
                                                                    ),
                                                child: CachedNetworkImage(
                                                                  imageUrl:
                                                                      fileUrl!,
                                                                  width: 280,
                                                                  height: 280,
                                                                  fit: BoxFit
                                                                      .cover,
                                                  placeholder: (context, url) => Container(
                                                                    width: 280,
                                                                    height: 280,
                                                                    color: Colors
                                                                        .grey[800],
                                                    child: const Center(
                                                      child: CircularProgressIndicator(
                                                                        strokeWidth:
                                                                            2,
                                                                        color: Colors
                                                                            .white54,
                                                      ),
                                                    ),
                                                  ),
                                                                  errorWidget:
                                                                      (
                                                                        context,
                                                                        url,
                                                                        error,
                                                                      ) => Container(
                                                                        width:
                                                                            280,
                                                                        height:
                                                                            280,
                                                                        color: Colors
                                                                            .grey[800],
                                                    child: const Icon(
                                                                          Icons
                                                                              .broken_image,
                                                                          size:
                                                                              48,
                                                                          color:
                                                                              Colors.white54,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                                            ),
                                                          );
                                                        },
                                                      )
                                                    else if (isVideo)
                                                      // Use FullScreenVideoPlayerPage directly for video messages
                                                      _VideoMessagePreview(
                                                        videoUrl: fileUrl!,
                                                        fileName: fileName,
                                                      )
                                          else
                                            InkWell(
                                              onTap: () => _openFileUrl(fileUrl),
                                              child: Container(
                                                        padding:
                                                            const EdgeInsets.all(
                                                              12,
                                                            ),
                                              decoration: BoxDecoration(
                                                          color: Colors.white
                                                              .withOpacity(0.2),
                                                          borderRadius:
                                                              BorderRadius.circular(
                                                                8,
                                                              ),
                                              ),
                                              child: Row(
                                                          mainAxisSize:
                                                              MainAxisSize.min,
                                                children: [
                                                  // Circular blue icon with white document symbol
                                                  Container(
                                                    width: 40,
                                                    height: 40,
                                                    decoration: BoxDecoration(
                                                      color: Colors.blue,
                                                      shape: BoxShape.circle,
                                                    ),
                                                    child: Icon(
                                                      _fileService.getFileIcon(fileName),
                                                      color: Colors.white,
                                                      size: 24,
                                                    ),
                                                  ),
                                                            const SizedBox(
                                                              width: 12,
                                                            ),
                                                  Expanded(
                                                    child: Column(
                                                                crossAxisAlignment:
                                                                    CrossAxisAlignment
                                                                        .start,
                                                      mainAxisSize: MainAxisSize.min,
                                                      children: [
                                                        // File name in blue
                                                        Text(
                                                                    fileName ??
                                                                        'File',
                                                          style: const TextStyle(
                                                                      color: Colors.blue,
                                                                      fontSize:
                                                                          14,
                                                                      fontWeight:
                                                                          FontWeight
                                                                              .w500,
                                                          ),
                                                          maxLines: 2,
                                                                    overflow:
                                                                        TextOverflow
                                                                            .ellipsis,
                                                        ),
                                                                  if (m['fileSize'] !=
                                                                      null)
                                                          Text(
                                                            _fileService.formatFileSize(
                                                                        int.tryParse(
                                                                              m['fileSize'].toString(),
                                                                            ) ??
                                                                            0,
                                                            ),
                                                            style: const TextStyle(
                                                                        color: Colors
                                                                            .white,
                                                                        fontSize:
                                                                            12,
                                                            ),
                                                          ),
                                                      ],
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                                    if (!isImageOnly && !isVideoOnly && !isVoiceOnly)
                                          const SizedBox(height: 8),
                                        ],
                                                  // Deleted message indicator - show for both text and image messages
                                        AnimatedSwitcher(
                                          duration: const Duration(
                                            milliseconds: 150,
                                          ),
                                          child: isDeleted
                                              ? Row(
                                                  key: const ValueKey(
                                                    'deleted',
                                                  ),
                                                  mainAxisSize:
                                                                MainAxisSize
                                                                    .min,
                                                  children: [
                                                    Icon(
                                                                Icons
                                                                    .delete_outline,
                                                      size: 16,
                                                                color: mine
                                                                    ? Colors
                                                                          .white70
                                                                    : Colors
                                                                          .black54,
                                                    ),
                                                              const SizedBox(
                                                                width: 6,
                                                              ),
                                                    Text(
                                                      'Message deleted',
                                                      style: TextStyle(
                                                                  color: mine
                                                                      ? Colors
                                                                            .white70
                                                                      : Colors
                                                                            .black54,
                                                                  fontStyle:
                                                                      FontStyle
                                                                          .italic,
                                                      ),
                                                    ),
                                                  ],
                                                )
                                                        : (!isImageOnly && !isVideoOnly && !isVoiceOnly
                                                              ? (deleting
                                                    ? Row(
                                                        key: const ValueKey(
                                                          'deleting',
                                                        ),
                                                        mainAxisSize:
                                                            MainAxisSize.min,
                                                        children: [
                                                          SizedBox(
                                                                            width:
                                                                                14,
                                                                            height:
                                                                                14,
                                                            child: CircularProgressIndicator(
                                                              strokeWidth: 2,
                                                                              color: mine
                                                                                  ? Colors.white70
                                                                                  : Colors.black54,
                                                            ),
                                                          ),
                                                                          const SizedBox(
                                                                            width:
                                                                                8,
                                                                          ),
                                                          Text(
                                                            'Deleting…',
                                                            style: TextStyle(
                                                                              color: mine
                                                                                  ? Colors.white70
                                                                                  : Colors.black54,
                                                            ),
                                                          ),
                                                        ],
                                                      )
                                                                    : (() {
                                                                        final messageText =
                                                                            m['text']?.toString() ??
                                                                            '';
                                                                        final hasText =
                                                                            messageText.isNotEmpty;
                                                                        // Double-check if it's an image by checking fileType directly
                                                                        final fileTypeDirect = m['fileType']?.toString();
                                                                        final isImageDirect = fileTypeDirect == 'image' || (fileName != null && _fileService.isImageFile(fileName));
                                                                        final isImageFinal = isImage || isImageDirect;
                                                                        // Check if it's a video message
                                                                        final isVideoFinal = isVideo || (fileTypeDirect == 'video' || 
                                                                            (fileName != null && (fileName.toLowerCase().endsWith('.mp4') || 
                                                                             fileName.toLowerCase().endsWith('.mov') || 
                                                                             fileName.toLowerCase().endsWith('.avi') || 
                                                                             fileName.toLowerCase().endsWith('.mkv') || 
                                                                             fileName.toLowerCase().endsWith('.webm'))));
                                                                        final isDefaultImageText =
                                                                            isImageFinal &&
                                                                            (messageText.trim().isEmpty ||
                                                                                messageText ==
                                                                                    '📎 ${fileName ?? "File"}');
                                                                        final isDefaultVideoText =
                                                                            isVideoFinal &&
                                                                            (messageText.trim().isEmpty ||
                                                                                messageText ==
                                                                                    '📎 ${fileName ?? "File"}');
                                                                        final isDefaultVoiceText =
                                                                            isVoice &&
                                                                            (messageText.trim().isEmpty ||
                                                                                messageText.trim() == '🎤' ||
                                                                                messageText ==
                                                                                    '📎 ${fileName ?? "File"}' ||
                                                                                (fileName != null && messageText.trim() == fileName) ||
                                                                                (fileName != null && fileName.startsWith('voice_') && messageText.trim().contains(fileName)));
                                                                        // Always show "voice message" for voice messages with empty text or mic emoji
                                                                        if (isVoice) {
                                                                          final trimmedText = messageText.trim();
                                                                          if (trimmedText.isEmpty || 
                                                                              trimmedText == '🎤' || 
                                                                              isVoiceOnly ||
                                                                              (fileName != null && (fileName.startsWith('voice_') || fileName.endsWith('.m4a')))) {
                                                                            return Text(
                                                                              'voice message',
                                                                              key: const ValueKey('voice-message-text'),
                                                                              style: TextStyle(
                                                                                fontSize: 15,
                                                                                color: Colors.black,
                                                                                fontWeight: FontWeight.w400,
                                                                                height: 1.4,
                                                                              ),
                                                                            );
                                                                          }
                                                                          // If voice message has text but contains mic emoji, remove it completely
                                                                          if (messageText.contains('🎤')) {
                                                                            final displayText = messageText.replaceAll('🎤', '').trim();
                                                                            // If after removing mic emoji, text is empty, show "voice message"
                                                                            if (displayText.isEmpty) {
                                                                              return Text(
                                                                                'voice message',
                                                                                key: const ValueKey('voice-message-text-replaced'),
                                                                                style: TextStyle(
                                                                                  fontSize: 15,
                                                                                  color: Colors.black,
                                                                                  fontWeight: FontWeight.w400,
                                                                                  height: 1.4,
                                                                                ),
                                                                              );
                                                                            }
                                                                            // Otherwise show text without mic emoji
                                                                            return Text(
                                                                              displayText,
                                                                              key: const ValueKey('voice-message-text-replaced'),
                                                                              style: TextStyle(
                                                                                fontSize: 15,
                                                                                color: Colors.black,
                                                                                fontWeight: FontWeight.w400,
                                                                                height: 1.4,
                                                                              ),
                                                                            );
                                                                          }
                                                                        }
                                                                        // For video messages, ALWAYS show "Video" if text is empty, filename, or default format
                                                                        if (isVideoFinal) {
                                                                          final trimmedText = messageText.trim();
                                                                          final trimmedTextLower = trimmedText.toLowerCase();
                                                                          
                                                                          // Check if text looks like a filename (contains common video extensions or matches filename)
                                                                          final hasVideoExtension = trimmedTextLower.contains('.mp4') ||
                                                                              trimmedTextLower.contains('.mov') ||
                                                                              trimmedTextLower.contains('.avi') ||
                                                                              trimmedTextLower.contains('.mkv') ||
                                                                              trimmedTextLower.contains('.webm');
                                                                          
                                                                          // Extract filename part for comparison
                                                                          String? fileNameOnly;
                                                                          if (fileName != null && fileName.isNotEmpty) {
                                                                            fileNameOnly = fileName.split('/').last.split('\\').last.toLowerCase();
                                                                          }
                                                                          
                                                                          // Show "Video" if: empty, video-only, has video extension, matches filename, or is default format
                                                                          final shouldShowVideo = trimmedText.isEmpty ||
                                                                              isVideoOnly ||
                                                                              hasVideoExtension ||
                                                                              trimmedText == '📎 ${fileName ?? "File"}' ||
                                                                              trimmedText.startsWith('📎 ') ||
                                                                              (fileName != null && (trimmedText == fileName || trimmedTextLower == fileName.toLowerCase())) ||
                                                                              (fileNameOnly != null && (trimmedTextLower == fileNameOnly || trimmedTextLower.contains(fileNameOnly))) ||
                                                                              (fileName != null && fileName.isNotEmpty && trimmedTextLower.contains(fileName.toLowerCase()));
                                                                          
                                                                          if (shouldShowVideo) {
                                                                            return Text(
                                                                              'Video',
                                                                              key: const ValueKey('video-message-text'),
                                                                              style: TextStyle(
                                                                                fontSize: 15,
                                                                                color: Colors.black,
                                                                                fontWeight: FontWeight.w400,
                                                                                height: 1.4,
                                                                              ),
                                                                            );
                                                                          }
                                                                        }
                                                                        
                                                                        // For image messages, ALWAYS show "Photo" if text is empty, filename, or default format
                                                                        if (isImageFinal) {
                                                                          final trimmedText = messageText.trim();
                                                                          final trimmedTextLower = trimmedText.toLowerCase();
                                                                          
                                                                          // Check if text looks like a filename (contains common image extensions or matches filename)
                                                                          final hasImageExtension = trimmedTextLower.contains('.jpg') ||
                                                                              trimmedTextLower.contains('.jpeg') ||
                                                                              trimmedTextLower.contains('.png') ||
                                                                              trimmedTextLower.contains('.gif') ||
                                                                              trimmedTextLower.contains('.webp') ||
                                                                              trimmedTextLower.contains('.bmp');
                                                                          
                                                                          // Extract filename part for comparison
                                                                          String? fileNameOnly;
                                                                          if (fileName != null && fileName.isNotEmpty) {
                                                                            fileNameOnly = fileName.split('/').last.split('\\').last.toLowerCase();
                                                                          }
                                                                          
                                                                          // Show "Photo" if: empty, image-only, has image extension, matches filename, or is default format
                                                                          final shouldShowPhoto = trimmedText.isEmpty ||
                                                                              isImageOnly ||
                                                                              hasImageExtension ||
                                                                              trimmedText == '📎 ${fileName ?? "File"}' ||
                                                                              trimmedText.startsWith('📎 ') ||
                                                                              (fileName != null && (trimmedText == fileName || trimmedTextLower == fileName.toLowerCase())) ||
                                                                              (fileNameOnly != null && (trimmedTextLower == fileNameOnly || trimmedTextLower.contains(fileNameOnly))) ||
                                                                              (fileName != null && fileName.isNotEmpty && trimmedTextLower.contains(fileName.toLowerCase()));
                                                                          
                                                                          if (shouldShowPhoto) {
                                                                            return Text(
                                                                              'Photo',
                                                                              key: const ValueKey('photo-message-text'),
                                                                              style: TextStyle(
                                                                                fontSize: 15,
                                                                                color: Colors.black,
                                                                                fontWeight: FontWeight.w400,
                                                                                height: 1.4,
                                                                              ),
                                                                            );
                                                                          }
                                                                        }
                                                                        // Remove mic emoji and paperclip emoji from any message text
                                                                        String displayText = messageText.replaceAll('🎤', '').trim();
                                                                        
                                                                        // For images, replace any filename or paperclip text with "Photo"
                                                                        if (isImageFinal) {
                                                                          // Check if text starts with paperclip emoji or contains filename
                                                                          if (displayText.startsWith('📎 ') || 
                                                                              displayText.toLowerCase().contains('.jpg') ||
                                                                              displayText.toLowerCase().contains('.jpeg') ||
                                                                              displayText.toLowerCase().contains('.png') ||
                                                                              displayText.toLowerCase().contains('.gif') ||
                                                                              displayText.toLowerCase().contains('.webp') ||
                                                                              displayText.toLowerCase().contains('.bmp') ||
                                                                              (fileName != null && fileName.isNotEmpty && displayText.toLowerCase().contains(fileName.toLowerCase()))) {
                                                                            displayText = 'Photo';
                                                                          }
                                                                        }
                                                                        // For videos, replace any filename or paperclip text with "Video"
                                                                        else if (isVideoFinal) {
                                                                          // Check if text starts with paperclip emoji or contains video filename
                                                                          if (displayText.startsWith('📎 ') || 
                                                                              displayText.toLowerCase().contains('.mp4') ||
                                                                              displayText.toLowerCase().contains('.mov') ||
                                                                              displayText.toLowerCase().contains('.avi') ||
                                                                              displayText.toLowerCase().contains('.mkv') ||
                                                                              displayText.toLowerCase().contains('.webm') ||
                                                                              (fileName != null && fileName.isNotEmpty && displayText.toLowerCase().contains(fileName.toLowerCase()))) {
                                                                            displayText = 'Video';
                                                                          }
                                                                        }
                                                                        // For other files (not image/video/voice), don't show text - file name is shown in the file component
                                                                        else if (hasFile && !isImageFinal && !isVideoFinal && !isVoice) {
                                                                          // Hide the text since file name is displayed in the file component
                                                                          displayText = '';
                                                                        }
                                                                        // Only show text if it's not empty and not default image/video/voice text
                                                                        if (displayText.isNotEmpty && !isDefaultImageText && !isDefaultVideoText && !isDefaultVoiceText) {
                                                                          return Text(
                                                                            displayText,
                                                                            key: const ValueKey('text'),
                                                                            style: TextStyle(
                                                                              fontSize: 15,
                                                                              color: Colors.black, // Black text for white bubbles
                                                                              fontWeight: FontWeight.w400,
                                                                              height: 1.4,
                                                                            ),
                                                                          );
                                                                        }
                                                                        return const SizedBox.shrink();
                                                                      })())
                                                              : const SizedBox.shrink()),
                                        ),
                                                  // Status row - show for all messages including images
                                        const SizedBox(height: 6),
                                        if (!isDeleted)
                                                    Padding(
                                                      padding: (isImageOnly || isVideoOnly)
                                                          ? const EdgeInsets.symmetric(
                                                              horizontal: 8,
                                                              vertical: 4,
                                                            )
                                                          : EdgeInsets.zero,
                                                      child: Row(
                                                        mainAxisSize:
                                                            MainAxisSize.min,
                                            crossAxisAlignment:
                                                            CrossAxisAlignment
                                                                .center,
                                                        mainAxisAlignment: mine
                                                            ? MainAxisAlignment
                                                                  .end
                                                            : MainAxisAlignment
                                                                  .start,
                                            children: [
                                              Text(
                                                createdAt,
                                                style: TextStyle(
                                                  fontSize: 11,
                                                              color: (isImageOnly || isVideoOnly)
                                                                  ? Colors.white70
                                                                  : Colors.grey[600], // Gray for timestamp on white bubbles
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w400,
                                                ),
                                              ),
                                              if (edited) ...[
                                                            const SizedBox(
                                                              width: 6,
                                                            ),
                                                Icon(
                                                  Icons.edit,
                                                  size: 12,
                                                              color: Colors.grey[600], // Gray for edit icon on white bubbles
                                                ),
                                                            const SizedBox(
                                                              width: 2,
                                                            ),
                                                Text(
                                                  '(edited)',
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                                color: Colors.grey[600], // Gray for edited text on white bubbles
                                                  ),
                                                ),
                                              ],
                                              if (mine) ...[
                                                            const SizedBox(
                                                              width: 6,
                                                            ),
                                                _tickForMessage(m),
                                                            const SizedBox(
                                                              width: 4,
                                                            ),
                                                Builder(
                                                  builder: (_) {
                                                    final status =
                                                                    _msgStatusFor(
                                                                      m,
                                                                    );
                                                                if (status
                                                                    .isEmpty || status == 'sent')
                                                      return const SizedBox.shrink();
                                                    // Show text for "delivered" (brown) and "seen" (blue)
                                                    return Text(
                                                      status,
                                                      style: TextStyle(
                                                                    fontSize:
                                                                        11,
                                                                    color:
                                                                        (isImageOnly || isVideoOnly)
                                                                        ? (status == 'seen' 
                                                                            ? const Color(0xFF0084FF) // Blue for seen images/videos
                                                                            : const Color(0xFF8B4513)) // Brown for delivered images/videos
                                                                        : _msgStatusColor(
                                                          status,
                                                        ),
                                                        fontStyle:
                                                                        status ==
                                                                            'seen'
                                                                        ? FontStyle
                                                                              .normal
                                                                        : FontStyle
                                                                              .italic,
                                                      ),
                                                    );
                                                  },
                                                ),
                                              ],
                                            ],
                                                      ),
                                          ),
                                        ],
                                      ), // Close Column
                                      ), // Close AnimatedContainer
                                      ), // Close Transform.translate
                                    ], // Close Stack children
                                  ), // Close Stack
                            ), // Close GestureDetector
                                                  ), // Close Flexible
                                                ], // Close Row children
                                              ), // Close Row
                                            ), // Close Padding
                                        ), // Close Align
                                        ], // Close Stack children
                                      ), // Close Stack
                            ); // Close TweenAnimationBuilder (return statement)
                          },
                        ),
                ],
              ),
            ),
            // Message input composer
            if (composerEnabled && !_isSelectMode)
              Container(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  boxShadow: [
                    BoxShadow(
                      color: Theme.of(context).brightness == Brightness.dark
                          ? Colors.black.withOpacity(0.3)
                          : Colors.black.withOpacity(0.05),
                      blurRadius: 8,
                      offset: const Offset(0, -2),
                    ),
                  ],
                ),
                child: SafeArea(
                  top: false,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Emoji picker
                      if (_showEmojiPicker)
                        Container(
                          height: 250,
                          decoration: BoxDecoration(
                            color: Theme.of(context).brightness == Brightness.dark
                                ? Theme.of(context).colorScheme.surfaceContainerHighest
                                : Colors.grey.shade50,
                          ),
                          clipBehavior: Clip.hardEdge,
                          child: EmojiPickerWidget(
                            onEmojiSelected: (emoji) {
                              // Insert emoji into text field
                              setState(() {
                                _input.text = _input.text + emoji;
                                _input.selection = TextSelection.fromPosition(
                                  TextPosition(offset: _input.text.length),
                                );
                              });
                              // Keep emoji picker open (Telegram-style)
                              // Don't close the picker, don't request focus
                              // User can continue selecting more emojis
                            },
                            onBackspace: () {
                              if (_input.text.isNotEmpty) {
                                setState(() {
                                  _input.text = _input.text.substring(
                                    0,
                                    _input.text.length - 1,
                                  );
                                  _input.selection = TextSelection.fromPosition(
                                    TextPosition(offset: _input.text.length),
                                  );
                                });
                              }
                            },
                          ),
                        ),
                      // Voice recording UI (Telegram/Viber style)
                      if (_isRecordingVoice)
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 8,
                          ),
                          child: ValueListenableBuilder<int>(
                            valueListenable: _voiceService.durationNotifier,
                            builder: (context, duration, child) {
                              return VoiceRecordingUI(
                                duration: duration,
                                onStop: _stopVoiceRecording,
                                onCancel: _cancelVoiceRecording,
                                showCancel: true,
                              );
                            },
                          ),
                        ),
                      // Edit Message preview (above input field)
                      if (_editingId != null)
                        Column(
                          children: [
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: Theme.of(context).brightness == Brightness.dark
                                    ? Theme.of(context).colorScheme.surfaceContainerHighest
                                    : Colors.white,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  // Edit Message header row
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.edit,
                                        size: 16,
                                        color: Theme.of(context).colorScheme.primary,
                                      ),
                                      Container(
                                        width: 1,
                                        height: 14,
                                        margin: const EdgeInsets.symmetric(horizontal: 6),
                                        color: Theme.of(context).colorScheme.primary,
                                      ),
                                      Text(
                                        'Edit Message',
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w500,
                                          color: Theme.of(context).colorScheme.primary,
                                        ),
                                      ),
                                      const Spacer(),
                                      IconButton(
                                        icon: Icon(
                                          Icons.close,
                                          size: 18,
                                          color: Theme.of(context).colorScheme.primary,
                                        ),
                                        onPressed: _cancelEdit,
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(
                                          minWidth: 28,
                                          minHeight: 28,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  // Original message preview
                                  Padding(
                                    padding: const EdgeInsets.only(left: 23), // Align with text after icon and line
                                    child: Text(
                                      _editingOriginalText,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: Theme.of(context).colorScheme.onSurface,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            // Separator line
                            Container(
                              height: 1,
                              color: Theme.of(context).brightness == Brightness.dark
                                  ? Theme.of(context).colorScheme.outline.withOpacity(0.2)
                                  : Colors.grey[300],
                            ),
                          ],
                        ),
                      // Reply preview (Messenger-style, above input field)
                      if (_replyingToMessage != null)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: Theme.of(context).brightness == Brightness.dark
                                ? Theme.of(context).colorScheme.surfaceContainerHighest
                                : Colors.grey[50],
                            border: Border(
                              bottom: BorderSide(
                                color: Theme.of(context).brightness == Brightness.dark
                                    ? Theme.of(context).colorScheme.outline.withOpacity(0.2)
                                    : Colors.grey[200]!,
                                width: 1,
                              ),
                            ),
                          ),
                          child: Row(
                            children: [
                              // Reply icon (curved arrow)
                              Icon(
                                Icons.reply,
                                size: 20,
                                color: const Color(0xFF0084FF), // Messenger blue
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    // "Reply to [Name]"
                                    Text(
                                      'Reply to ${_replyingToMessage!['from']?.toString() == myId ? 'You' : (widget.peerName ?? widget.partnerEmail)}',
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w500,
                                        color: Color(0xFF0084FF), // Messenger blue
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    // Message preview
                                    Text(
                                      () {
                                        final text = _replyingToMessage!['text']?.toString() ?? '';
                                        final fileType = _replyingToMessage!['fileType']?.toString();
                                        final fileName = _replyingToMessage!['fileName']?.toString();
                                        final isVoice = fileType == 'audio' || fileType == 'voice';
                                        final isImage = fileType == 'image';
                                        final isVideo = fileType == 'video' || (fileName != null && 
                                            (fileName.toLowerCase().endsWith('.mp4') || 
                                             fileName.toLowerCase().endsWith('.mov') || 
                                             fileName.toLowerCase().endsWith('.avi') || 
                                             fileName.toLowerCase().endsWith('.mkv') || 
                                             fileName.toLowerCase().endsWith('.webm')));
                                        // Remove mic emoji from text
                                        final cleanedText = text.replaceAll('🎤', '').trim();
                                        
                                        if (isVoice && (cleanedText.isEmpty || text.trim() == '🎤')) {
                                          return '🎤 Voice message';
                                        }
                                        if (isImage && (cleanedText.isEmpty || text == '📎 ${_replyingToMessage!['fileName'] ?? "File"}' || text.startsWith('📎 '))) {
                                          return '📷 Photo';
                                        }
                                        if (isVideo && (cleanedText.isEmpty || text == '📎 ${_replyingToMessage!['fileName'] ?? "File"}' || text.startsWith('📎 '))) {
                                          return '🎥 Video';
                                        }
                                        // Check if it's a file message (has fileUrl or fileName but not image/video/voice)
                                        final hasFile = _replyingToMessage!['fileUrl'] != null || _replyingToMessage!['fileName'] != null;
                                        if (hasFile && !isImage && !isVideo && !isVoice && 
                                            (cleanedText.isEmpty || text == '📎 ${_replyingToMessage!['fileName'] ?? "File"}' || text.startsWith('📎 '))) {
                                          return '📎 File';
                                        }
                                        return cleanedText.isEmpty ? 'Message' : cleanedText;
                                      }(),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: Theme.of(context).colorScheme.onSurface,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              // Close button
                              IconButton(
                                icon: Icon(
                                  Icons.close,
                                  size: 20,
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                ),
                                onPressed: _cancelReply,
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(
                                  minWidth: 32,
                                  minHeight: 32,
                                ),
                              ),
                            ],
                          ),
                        ),
                      // Main input row - hide when recording, show recording UI instead
                      if (!_isRecordingVoice)
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 8,
                          ),
                          child: Row(
                            children: [
                              // Attachment button - always visible with explicit color for dark mode
                              IconButton(
                                icon: const Icon(Icons.attach_file),
                                color: composerEnabled
                                    ? Theme.of(context).colorScheme.onSurface
                                    : Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant
                                        .withOpacity(.5),
                                onPressed: composerEnabled
                                    ? _showAttachmentOptions
                                    : null,
                                tooltip: 'Attachment',
                                iconSize: 24,
                              ),
                              // Text input field
                              Expanded(
                                child: Container(
                                  constraints: const BoxConstraints(
                                    minHeight: 48,
                                  ),
                                  decoration: BoxDecoration(
                                    color: _editingId != null
                                        ? (Theme.of(context).brightness == Brightness.dark
                                            ? Theme.of(context).colorScheme.surfaceContainerHighest
                                            : Colors.grey[300])
                                        : Theme.of(context)
                                            .colorScheme
                                            .surfaceContainerLowest,
                                    borderRadius: BorderRadius.circular(24),
                                    border: Border.all(
                                      color:
                                          Theme.of(context).colorScheme.outlineVariant.withOpacity(0.3),
                                      width: 0.5,
                                    ),
                                  ),
                                  child: TextFormField(
                                    controller: _input,
                                    focusNode: _inputFocusNode,
                                    maxLines: null,
                                    textCapitalization:
                                        TextCapitalization.sentences,
                                    keyboardAppearance: Theme.of(context).brightness == Brightness.dark
                                        ? Brightness.dark
                                        : Brightness.light,
                                    decoration: InputDecoration(
                                      hintText: _editingId != null
                                          ? 'Edit message…'
                                          : 'Send Message',
                                      hintStyle: TextStyle(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant
                                            .withOpacity(.7),
                                      ),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(24),
                                        borderSide: BorderSide.none,
                                      ),
                                      enabledBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(24),
                                        borderSide: BorderSide.none,
                                      ),
                                      focusedBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(24),
                                        borderSide: BorderSide.none,
                                      ),
                                      disabledBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(24),
                                        borderSide: BorderSide.none,
                                      ),
                                      errorBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(24),
                                        borderSide: BorderSide.none,
                                      ),
                                      focusedErrorBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(24),
                                        borderSide: BorderSide.none,
                                      ),
                                      filled: true,
                                      fillColor: _editingId != null
                                          ? (Theme.of(context).brightness == Brightness.dark
                                              ? Theme.of(context).colorScheme.surfaceContainerHighest
                                              : Colors.grey[300])
                                          : Theme.of(context)
                                              .colorScheme
                                              .surfaceContainerHighest,
                                      contentPadding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 10,
                                      ),
                                      prefixIcon: IconButton(
                                        icon: Icon(
                                          _showEmojiPicker
                                              ? Icons.keyboard
                                              : Icons.emoji_emotions_outlined,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurfaceVariant,
                                        ),
                                        onPressed: _toggleEmojiPicker,
                                        tooltip: _showEmojiPicker
                                            ? 'Show keyboard'
                                            : 'Show emoji',
                                        iconSize: 24,
                                      ),
                                      suffixIcon: (_hasText || _editingId != null)
                                          ? _editingId != null
                                              ? Container(
                                                  margin: const EdgeInsets.all(4),
                                                  decoration: BoxDecoration(
                                                    color: Theme.of(context).colorScheme.primary,
                                                    shape: BoxShape.circle,
                                                  ),
                                                  child: IconButton(
                                                    icon: const Icon(
                                                      Icons.check,
                                                      color: Colors.white,
                                                      size: 20,
                                                    ),
                                                    onPressed: canSend ? _saveEdit : null,
                                                    padding: EdgeInsets.zero,
                                                    constraints: const BoxConstraints(
                                                      minWidth: 36,
                                                      minHeight: 36,
                                                    ),
                                                  ),
                                                )
                                              : IconButton(
                                                  icon: Icon(
                                                    Icons.send,
                                                    color: canSend
                                                        ? Theme.of(context)
                                                            .colorScheme
                                                            .primary
                                                        : Theme.of(context)
                                                            .colorScheme
                                                            .onSurfaceVariant,
                                                  ),
                                                  onPressed: canSend ? _send : null,
                                                )
                                          : null,
                                    ),
                                    style: TextStyle(
                                      color:
                                          Theme.of(context).colorScheme.onSurface,
                                    ),
                                    onTap: () {
                                      // Telegram-style: Don't close emoji picker when tapping input field
                                      // Only request focus to show keyboard if emoji picker is not showing
                                      if (!_showEmojiPicker) {
                                        // Request focus to show keyboard on mobile
                                        if (!_inputFocusNode.hasFocus) {
                                          _inputFocusNode.requestFocus();
                                        }
                                      }
                                      // If emoji picker is showing, keep it open (Telegram behavior)
                                    },
                                    onFieldSubmitted: (_) {
                                      if (canSend) {
                                        _send();
                                      }
                                    },
                                  ),
                                ),
                              ),
                            const SizedBox(width: 8),
                            // Microphone button (circular light blue) - hide when recording
                            if (!_hasText && _editingId == null && !_isRecordingVoice)
                              GestureDetector(
                                onTap: _startVoiceRecording,
                                onLongPress: _startVoiceRecording,
                                child: Container(
                                  width: 48,
                                  height: 48,
                                  decoration: BoxDecoration(
                                    color: Theme.of(context).brightness == Brightness.dark
                                        ? Theme.of(context).colorScheme.primaryContainer
                                        : const Color(0xFF81D4FA), // Light blue
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    Icons.mic_none,
                                    color: Theme.of(context).brightness == Brightness.dark
                                        ? Theme.of(context).colorScheme.onPrimaryContainer
                                        : Colors.white,
                                    size: 24,
                                  ),
                                ),
                              )
                            else if (!_isRecordingVoice)
                              const SizedBox(width: 48),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
      resizeToAvoidBottomInset: true, // Keep true to allow proper keyboard handling
      // Floating action button for selected messages
      floatingActionButton: _isSelectMode && _selectedMessageIds.isNotEmpty
          ? FloatingActionButton.extended(
              onPressed: () {
                // Show action menu for selected messages
                showModalBottomSheet(
                  context: context,
                  backgroundColor: Colors.transparent,
                  builder: (context) => Container(
                    decoration: BoxDecoration(
                      color: Theme.of(context).scaffoldBackgroundColor,
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(20),
                        topRight: Radius.circular(20),
                      ),
                    ),
                    child: SafeArea(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            margin: const EdgeInsets.only(top: 12, bottom: 8),
                            width: 40,
                            height: 4,
                            decoration: BoxDecoration(
                              color: Colors.grey.shade300,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          ListTile(
                            leading: const Icon(
                              Icons.delete_outline,
                              color: Colors.red,
                            ),
                            title: Text(
                              'Delete ${_selectedMessageIds.length} message${_selectedMessageIds.length > 1 ? 's' : ''}',
                              style: const TextStyle(
                                color: Colors.red,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            onTap: () {
                              Navigator.pop(context);
                              _deleteSelectedMessages();
                            },
                          ),
                          ListTile(
                            leading: Icon(
                              Icons.forward,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                            title: const Text('Forward'),
                            onTap: () {
                              Navigator.pop(context);
                              _forwardSelectedMessages();
                            },
                          ),
                          ListTile(
                            leading: Icon(
                              Icons.content_copy,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                            title: const Text('Copy'),
                            onTap: () {
                              Navigator.pop(context);
                              _copySelectedMessages();
                            },
                          ),
                          SizedBox(
                            height: MediaQuery.of(context).padding.bottom,
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.more_vert),
              label: Text('${_selectedMessageIds.length}'),
              backgroundColor: Theme.of(context).colorScheme.primary,
            )
          : null,
    );
  }

  String _fmtTime(String? iso) {
    if (iso == null || iso.isEmpty) return '';
    final dt = DateTime.tryParse(iso);
    if (dt == null) return '';
    final local = dt.toLocal();
    final h = local.hour == 0
        ? 12
        : (local.hour > 12 ? local.hour - 12 : local.hour);
    final mm = local.minute.toString().padLeft(2, '0');
    final ampm = local.hour >= 12 ? 'pm' : 'am';
    return '$h:$mm $ampm';
  }

  /// Build call activity message widget
  Widget _buildCallActivityMessage(Map<String, dynamic> m, bool isMe, {VoidCallback? onTap}) {
    try {
      // Parse call log data from message metadata
      // IMPORTANT: We use the metadata fields, NOT the message text
      final callTypeStr = m['callType']?.toString() ?? 'outgoing';
      final callStatusStr = m['callStatus']?.toString() ?? 'completed';
      final isVideoCall = m['isVideoCall'] == true;
      final startTimeStr =
          m['callStartTime']?.toString() ?? m['createdAt']?.toString();
      final durationStr = m['callDuration']?.toString();
      
      // Parse call type and status
      final callType = CallType.fromString(callTypeStr);
      final callStatus = CallStatus.fromString(callStatusStr);
      
      debugPrint(
        'Building call activity: type=$callTypeStr, status=$callStatusStr, isVideo=$isVideoCall',
      );
      
      DateTime? startTime;
      Duration? duration;
      
      if (startTimeStr != null) {
        startTime = DateTime.tryParse(startTimeStr);
      }
      
      if (durationStr != null) {
        final seconds = int.tryParse(durationStr);
        if (seconds != null && seconds > 0) {
          duration = Duration(seconds: seconds);
        }
      }

      // IMPORTANT: Flip the call type based on who receives the message
      // If the message says "outgoing" but it's from someone else, it's incoming from our perspective
      final messageFrom = m['from']?.toString() ?? '';
      final isActuallyOutgoing =
          callType == CallType.outgoing && messageFrom == myId;
      final actualCallType = isActuallyOutgoing
          ? CallType.outgoing
          : CallType.incoming;
      
      // Create CallLog object with parsed data (flipped perspective)
      final callLog = CallLog(
        id: m['_id']?.toString() ?? m['id']?.toString() ?? '',
        peerId: peerId ?? '',
        peerName: widget.peerName,
        peerEmail: widget.partnerEmail,
        type: actualCallType, // Use flipped call type based on perspective
        status: callStatus, // Use parsed call status - THIS IS KEY!
        startTime: startTime ?? DateTime.now(),
        duration: duration,
        isVideoCall: isVideoCall,
      );

      // Format exact timestamp (no "just now" formatting)
      String? formattedTime;
      if (startTime != null) {
        final localTime = startTime.toLocal();
        final hour = localTime.hour == 0
            ? 12
            : (localTime.hour > 12 ? localTime.hour - 12 : localTime.hour);
        final minute = localTime.minute.toString().padLeft(2, '0');
        final ampm = localTime.hour >= 12 ? 'pm' : 'am';
        formattedTime = '$hour:$minute $ampm';
      } else {
        // Fallback to message timestamp
        final createdAt = m['createdAt']?.toString();
        if (createdAt != null) {
          formattedTime = _fmtTime(createdAt);
        }
      }

      // For Viber-style: outgoing calls appear on RIGHT, incoming on LEFT
      // Use the flipped call type to determine alignment
      return CallActivityMessage(
        callLog:
            callLog, // Widget will generate text based on callLog.status and type
        isMe:
            actualCallType ==
            CallType.outgoing, // Outgoing = RIGHT, Incoming = LEFT
        onTap: onTap,
        timestamp: formattedTime,
      );
    } catch (e) {
      debugPrint('Error building call activity message: $e');
      // Fallback to text message if parsing fails
      return Align(
        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.grey.shade300,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Text(
            m['text']?.toString() ?? 'Call activity',
            style: const TextStyle(color: Colors.black87, fontSize: 14),
          ),
        ),
      );
    }
  }

  Widget _tickForMessage(Map<String, dynamic> m) {
    final createdIso = (m['createdAt'] ?? '').toString();
    final created = DateTime.tryParse(createdIso);
    if (created == null) return const SizedBox.shrink();

    final delivered =
        _deliveredUpToPeer != null && !created.isAfter(_deliveredUpToPeer!);
    final read = _readUpToPeer != null && !created.isAfter(_readUpToPeer!);

    // Messenger-style: 
    // - Single gray checkmark for sent
    // - Single brown checkmark for delivered
    // - Double blue checkmark for seen
    final icon = read ? Icons.done_all : Icons.done;
    final color = read
        ? const Color(0xFF0084FF) // Blue for seen
        : (delivered 
            ? const Color(0xFF8B4513) // Brown for delivered
            : (Colors.grey[600] ?? Colors.grey)); // Gray for sent

    return Icon(icon, size: 16, color: color);
  }

  Future<void> _startVoiceRecording() async {
    debugPrint(
      '_startVoiceRecording called, composerEnabled: $composerEnabled',
    );
    if (!composerEnabled) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please wait for chat to be accepted')),
        );
      }
      return;
    }
    
    if (_isRecordingVoice) {
      debugPrint('Already recording, ignoring');
      return;
    }
    
    // Request microphone permission and start recording
    try {
      debugPrint('Starting recording...');
      final started = await _voiceService.startRecording();
      debugPrint('Recording started: $started');
      
      if (started && mounted) {
        setState(() {
          _isRecordingVoice = true;
          _showEmojiPicker = false; // Hide emoji picker when recording
        });
        debugPrint('Recording state updated: $_isRecordingVoice');
      } else {
        if (mounted) {
          final hasPermission = await _voiceService.hasMicrophonePermission();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                hasPermission 
                    ? 'Failed to start recording. Please try again.'
                    : 'Microphone permission denied. Please grant microphone access in settings.',
              ),
              duration: const Duration(seconds: 3),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Error in _startVoiceRecording: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error starting recording: $e'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  Future<void> _stopVoiceRecording() async {
    debugPrint(
      '_stopVoiceRecording called, _isRecordingVoice: $_isRecordingVoice',
    );
    if (!_isRecordingVoice) {
      debugPrint('Not recording, returning');
      return;
    }
    
    if (mounted) {
      setState(() {
        _isRecordingVoice = false;
      });
    }
    
    final audioPath = await _voiceService.stopRecording();
    debugPrint('Recording stopped, path: $audioPath');

    if (audioPath == null || audioPath.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Recording failed - no audio file created'),
          ),
        );
      }
      return;
    }

    // Upload and send voice message
    setState(() => _uploadingFile = true);
    try {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 12),
                Text('Sending voice message...'),
              ],
            ),
            duration: Duration(seconds: 30),
          ),
        );
      }

      final fileUrl = await _voiceService.uploadAndGetUrl(audioPath);
      if (!mounted) {
        setState(() => _uploadingFile = false);
        return;
      }

      ScaffoldMessenger.of(context).hideCurrentSnackBar();

      if (fileUrl != null) {
        final duration = _voiceService.recordingDuration;
        await _send(
          fileUrl: fileUrl,
          fileName: 'voice_${DateTime.now().millisecondsSinceEpoch}.m4a',
          fileType: 'audio',
          audioDuration: duration,
        );
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to upload voice message')),
          );
        }
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      setState(() => _uploadingFile = false);
    }
  }

  Future<void> _cancelVoiceRecording() async {
    await _voiceService.cancelRecording();
    if (mounted) {
      setState(() {
        _isRecordingVoice = false;
      });
    }
  }
  
  Future<void> _forwardSelectedMessages() async {
    // TODO: Implement forward selected messages
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Forward feature coming soon')),
    );
  }
  
  Future<void> _copySelectedMessages() async {
    final selectedMessages = _items.where((m) {
      final id = (m['_id'] ?? m['id'] ?? '').toString();
      return _selectedMessageIds.contains(id);
    }).toList();
    
    final texts = selectedMessages
        .map((m) => m['text']?.toString() ?? '')
        .where((t) => t.isNotEmpty)
        .join('\n');
    
    if (texts.isNotEmpty) {
      await Clipboard.setData(ClipboardData(text: texts));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${selectedMessages.length} message${selectedMessages.length > 1 ? 's' : ''} copied',
            ),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }
}

/// Video message preview widget that opens FullScreenVideoPlayerPage when tapped
class _VideoMessagePreview extends StatefulWidget {
  final String videoUrl;
  final String? fileName;

  const _VideoMessagePreview({
    required this.videoUrl,
    this.fileName,
  });

  @override
  State<_VideoMessagePreview> createState() => _VideoMessagePreviewState();
}

class _VideoMessagePreviewState extends State<_VideoMessagePreview> {
  VideoPlayerController? _controller;
  bool _isInitialized = false;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _initializeThumbnail();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _initializeThumbnail() async {
    try {
      _controller = VideoPlayerController.networkUrl(
        Uri.parse(widget.videoUrl),
      );

      await _controller!.initialize();
      
      // Seek to the beginning to show first frame
      await _controller!.seekTo(Duration.zero);
      // Play briefly to decode first frame, then pause
      await _controller!.play();
      await Future.delayed(const Duration(milliseconds: 200));
      await _controller!.pause();
      await _controller!.seekTo(Duration.zero);
      
      if (mounted) {
        setState(() {
          _isInitialized = true;
        });
      }
    } catch (e) {
      debugPrint('Error loading video thumbnail: $e');
      if (mounted) {
        setState(() {
          _hasError = true;
        });
      }
    }
  }

  void _openFullScreenPlayer() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FullScreenVideoPlayerPage(
          videoUrl: widget.videoUrl,
          fileName: widget.fileName,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Fixed size for consistent display in chat (same as images)
    const double videoWidth = 280.0;
    const double videoHeight = 280.0;

    return GestureDetector(
      onTap: _openFullScreenPlayer,
      child: Container(
        width: videoWidth,
        height: videoHeight,
        decoration: BoxDecoration(
          color: Colors.grey[900],
          borderRadius: BorderRadius.circular(8),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Video thumbnail (first frame)
            if (_isInitialized && _controller != null && _controller!.value.isInitialized)
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: videoWidth,
                  height: videoHeight,
                  child: FittedBox(
                    fit: BoxFit.cover,
                    child: SizedBox(
                      width: _controller!.value.size.width,
                      height: _controller!.value.size.height,
                      child: VideoPlayer(_controller!),
                    ),
                  ),
                ),
              )
            else if (_hasError)
              Container(
                width: videoWidth,
                height: videoHeight,
                color: Colors.grey[900],
                child: const Icon(
                  Icons.videocam,
                  color: Colors.white54,
                  size: 48,
                ),
              )
            else
              Container(
                width: videoWidth,
                height: videoHeight,
                color: Colors.grey[900],
                child: const Center(
                  child: CircularProgressIndicator(
                    color: Colors.white,
                  ),
                ),
              ),
            
            // Large play button overlay (TikTok-style)
            Container(
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.6),
                shape: BoxShape.circle,
              ),
              padding: const EdgeInsets.all(16),
              child: const Icon(
                Icons.play_circle_filled,
                size: 64,
                color: Colors.white,
              ),
            ),
            
            // Video file name at bottom
            if (widget.fileName != null)
              Positioned(
                bottom: 8,
                left: 8,
                right: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.6),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    widget.fileName!,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
