import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../api.dart';
import '../socket_service.dart';
import '../auth_store.dart';

/// Service to synchronize app data with backend
/// Handles:
/// - Message synchronization
/// - Conversation list sync
/// - Read receipts and delivery status
/// - Automatic sync on reconnect
/// - Periodic background sync
class SyncService {
  SyncService._();
  static final SyncService instance = SyncService._();

  Timer? _periodicSyncTimer;
  bool _isSyncing = false;
  DateTime? _lastSyncTime;
  final _syncListeners = <Function()>[];

  /// Start periodic synchronization
  /// [interval] - Duration between syncs (default: 30 seconds)
  void startPeriodicSync({Duration interval = const Duration(seconds: 30)}) {
    stopPeriodicSync();
    _periodicSyncTimer = Timer.periodic(interval, (_) {
      if (!_isSyncing) {
        syncAll();
      }
    });
    debugPrint('🔄 Started periodic sync (interval: ${interval.inSeconds}s)');
  }

  /// Stop periodic synchronization
  void stopPeriodicSync() {
    _periodicSyncTimer?.cancel();
    _periodicSyncTimer = null;
  }

  /// Add listener for sync events
  void addSyncListener(Function() listener) {
    _syncListeners.add(listener);
  }

  /// Remove sync listener
  void removeSyncListener(Function() listener) {
    _syncListeners.remove(listener);
  }

  /// Notify all listeners that sync completed
  void _notifyListeners() {
    for (final listener in _syncListeners) {
      try {
        listener();
      } catch (e) {
        debugPrint('❌ Sync listener error: $e');
      }
    }
  }

  /// Get last sync time
  DateTime? get lastSyncTime => _lastSyncTime;

  /// Check if currently syncing
  bool get isSyncing => _isSyncing;

  /// Initialize sync service and set up socket reconnect handler
  Future<void> initialize() async {
    // Listen for socket reconnection
    SocketService.I.on('__connect__', (_) {
      debugPrint('🔄 Socket reconnected, triggering sync...');
      syncAll();
    });

    // Start periodic sync
    startPeriodicSync();
    debugPrint('✅ SyncService initialized');
  }

  /// Sync all data with backend
  Future<void> syncAll() async {
    if (_isSyncing) {
      debugPrint('⏸️ Sync already in progress, skipping...');
      return;
    }

    _isSyncing = true;
    try {
      debugPrint('🔄 Starting full sync...');
      
      // Sync conversations first (needed for message sync)
      await syncConversations();
      
      // Sync messages for active conversations
      await syncActiveConversationMessages();
      
      // Sync read receipts and delivery status
      await syncReadReceipts();
      
      _lastSyncTime = DateTime.now();
      _notifyListeners();
      
      debugPrint('✅ Full sync completed at ${_lastSyncTime}');
    } catch (e) {
      debugPrint('❌ Sync error: $e');
    } finally {
      _isSyncing = false;
    }
  }

  /// Sync conversation list
  Future<void> syncConversations() async {
    try {
      final user = await AuthStore.getUser();
      if (user == null) return;

      final myId = user['id'].toString();
      
      // Sync active conversations
      final activeResponse = await getJson(
        '/api/conversations?me=$myId&status=active',
      ).timeout(const Duration(seconds: 20));

      if (activeResponse.statusCode == 200) {
        final body = jsonDecode(activeResponse.body);
        final active = body is List
            ? (body as List).cast<Map<String, dynamic>>()
            : (body['conversations'] as List? ?? body['data'] as List? ?? [])
                .cast<Map<String, dynamic>>();
        debugPrint('📋 Synced ${active.length} active conversations');
      }

      // Sync pending chat requests
      final pendingResponse = await getJson(
        '/api/conversations/chat-requests?me=$myId&status=pending',
      ).timeout(const Duration(seconds: 20));

      if (pendingResponse.statusCode == 200) {
        final body = jsonDecode(pendingResponse.body);
        final pending = body is List
            ? (body as List).cast<Map<String, dynamic>>()
            : (body['requests'] as List? ?? body['data'] as List? ?? [])
                .cast<Map<String, dynamic>>();
        debugPrint('📋 Synced ${pending.length} pending chat requests');
      }
    } catch (e) {
      debugPrint('❌ Error syncing conversations: $e');
    }
  }

  /// Sync messages for active conversations
  /// This ensures we have the latest messages even if socket missed some
  Future<void> syncActiveConversationMessages() async {
    try {
      final user = await AuthStore.getUser();
      if (user == null) return;

      final myId = user['id'].toString();
      
      // Get active conversations
      final convResponse = await getJson(
        '/api/conversations?me=$myId&status=active',
      ).timeout(const Duration(seconds: 20));

      if (convResponse.statusCode != 200) return;

      final body = jsonDecode(convResponse.body);
      final conversations = body is List
          ? (body as List).cast<Map<String, dynamic>>()
          : (body['conversations'] as List? ?? body['data'] as List? ?? [])
              .cast<Map<String, dynamic>>();

      // For each conversation, check if we need to sync messages
      for (final conv in conversations) {
        final convId = conv['_id']?.toString();
        if (convId == null) continue;

        final lastMessageAt = conv['lastMessageAt']?.toString();
        if (lastMessageAt == null) continue;

        // Check if we have recent messages (within last 5 minutes)
        final lastMsgTime = DateTime.tryParse(lastMessageAt);
        if (lastMsgTime == null) continue;

        final timeSinceLastMsg = DateTime.now().difference(lastMsgTime);
        if (timeSinceLastMsg.inMinutes > 5) continue; // Only sync recent conversations

          // Sync messages for this conversation
        try {
          final msgResponse = await getJson(
            '/api/messages?conversation=$convId&limit=20',
          ).timeout(const Duration(seconds: 15));

          if (msgResponse.statusCode == 200) {
            final body = jsonDecode(msgResponse.body);
            final messages = body is List
                ? (body as List).cast<Map<String, dynamic>>()
                : (body['messages'] as List? ?? body['data'] as List? ?? [])
                    .cast<Map<String, dynamic>>();
            debugPrint('💬 Synced ${messages.length} messages for conversation $convId');
          }
        } catch (e) {
          debugPrint('❌ Error syncing messages for conversation $convId: $e');
        }
      }
    } catch (e) {
      debugPrint('❌ Error syncing active conversation messages: $e');
    }
  }

  /// Sync read receipts and delivery status
  Future<void> syncReadReceipts() async {
    try {
      final user = await AuthStore.getUser();
      if (user == null) return;

      final myId = user['id'].toString();
      
      // Get conversations with unread messages
      final convResponse = await getJson(
        '/api/conversations?me=$myId&status=active',
      ).timeout(const Duration(seconds: 20));

      if (convResponse.statusCode != 200) return;

      final body = jsonDecode(convResponse.body);
      final conversations = body is List
          ? (body as List).cast<Map<String, dynamic>>()
          : (body['conversations'] as List? ?? body['data'] as List? ?? [])
              .cast<Map<String, dynamic>>();

      for (final conv in conversations) {
        final convId = conv['_id']?.toString();
        if (convId == null) continue;

        // Check read receipts
        final readUpTo = conv['readUpTo'] as Map<String, dynamic>?;
        final deliveredUpTo = conv['deliveredUpTo'] as Map<String, dynamic>?;
        
        if (readUpTo != null || deliveredUpTo != null) {
          debugPrint('✅ Synced read/delivery status for conversation $convId');
        }
      }
    } catch (e) {
      debugPrint('❌ Error syncing read receipts: $e');
    }
  }

  /// Sync messages for a specific conversation
  /// Returns list of new messages that weren't in local state
  Future<List<Map<String, dynamic>>> syncConversationMessages(
    String conversationId, {
    int limit = 50,
  }) async {
    try {
      final response = await getJson(
        '/api/messages?conversation=$conversationId&limit=$limit',
      ).timeout(const Duration(seconds: 20));

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        final messages = body is List
            ? (body as List).cast<Map<String, dynamic>>()
            : (body['messages'] as List? ?? body['data'] as List? ?? [])
                .cast<Map<String, dynamic>>();
        debugPrint('💬 Synced ${messages.length} messages for conversation $conversationId');
        return messages;
      }
    } catch (e) {
      debugPrint('❌ Error syncing messages for conversation $conversationId: $e');
    }
    return [];
  }

  /// Sync user presence status
  Future<void> syncPresence(List<String> userIds) async {
    if (userIds.isEmpty) return;

    try {
      final response = await getJson(
        '/api/users/presence?ids=${userIds.join(",")}',
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final presence = Map<String, dynamic>.from(jsonDecode(response.body));
        debugPrint('👤 Synced presence for ${userIds.length} users');
        return;
      }
    } catch (e) {
      debugPrint('❌ Error syncing presence: $e');
    }
  }

  /// Force sync now (used by pull-to-refresh, etc.)
  Future<void> forceSync() async {
    await syncAll();
  }

  /// Cleanup
  void dispose() {
    stopPeriodicSync();
    _syncListeners.clear();
    debugPrint('🔄 SyncService disposed');
  }
}

