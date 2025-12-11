// Friends Page (Flutter)
// Shows only users who are already "friends" (accepted conversations = status: active)
// -------------------------------------------------------------------------------
// Requirements (pubspec.yaml):
// dependencies:
//   flutter:
//     sdk: flutter
//   http: ^1.2.1
//   socket_io_client: ^2.0.3
//
// Notes:
// - Default API base below targets Android emulator (10.0.2.2). For iOS/simulator or web, use localhost.
// - Backend endpoints used:
//   GET   /conversations?me=<uid>&status=active
//   GET   /users/by-ids?ids=<comma-separated-ids>
//   WS    socket.io with auth { token: <JWT> }
// - Tap row -> callback (onOpenChat) with (conversationId, partnerId)

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'widgets/avatar_with_status.dart';

const String kDefaultApiBase =
    'http://192.168.2.30:3000'; // Android emulator. Use 'http://localhost:3000' on iOS/web.

class FriendsPage extends StatefulWidget {
  final String myUserId;
  final String token;
  final String apiBaseUrl;
  final void Function(String conversationId, String partnerId)? onOpenChat;

  const FriendsPage({
    super.key,
    required this.myUserId,
    required this.token,
    this.apiBaseUrl = kDefaultApiBase,
    this.onOpenChat,
  });

  @override
  State<FriendsPage> createState() => _FriendsPageState();
}

class _FriendsPageState extends State<FriendsPage> {
  final List<_FriendRow> _rows = [];
  bool _loading = true;
  String? _error;
  io.Socket? _socket;

  @override
  void initState() {
    super.initState();
    _refresh();
    _connectSocket();
  }

  @override
  void dispose() {
    _socket?.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final conversations = await _fetchActiveConversations();
      if (!mounted) return;

      final partnerIds = <String>{};
      for (final c in conversations) {
        final partnerId = _partnerOf(c.participants, widget.myUserId);
        if (partnerId != null) partnerIds.add(partnerId);
      }

      final profiles = await _fetchProfiles(partnerIds.toList());

      final rows = <_FriendRow>[];
      for (final c in conversations) {
        final partnerId = _partnerOf(c.participants, widget.myUserId);
        if (partnerId == null) continue;
        final p = profiles[partnerId];
        final row = _FriendRow(
          conversationId: c.id,
          partnerId: partnerId,
          name: p?.name ?? 'Unknown',
          email: p?.email ?? '',
          avatarUrl: p?.avatarUrl,
          lastMessageAt: c.lastMessageAt ?? c.updatedAt ?? c.createdAt,
        );
        debugPrint('✅ FriendsPage: Created row for $partnerId (${row.name}), avatarUrl: ${row.avatarUrl}');
        rows.add(row);
      }

      // Backend already sorts by lastMessageAt desc, but re-assert here just in case.
      rows.sort(
        (a, b) => (b.lastMessageAt ?? DateTime.fromMillisecondsSinceEpoch(0))
            .compareTo(
              a.lastMessageAt ?? DateTime.fromMillisecondsSinceEpoch(0),
            ),
      );

      setState(() {
        _rows
          ..clear()
          ..addAll(rows);
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<List<_Conversation>> _fetchActiveConversations() async {
    final uri = Uri.parse(
      '${widget.apiBaseUrl}/conversations?me=${Uri.encodeQueryComponent(widget.myUserId)}&status=active',
    );
    final res = await http.get(
      uri,
      headers: {
        'Authorization': 'Bearer ${widget.token}',
        'Accept': 'application/json',
      },
    );

    if (res.statusCode == 401) {
      throw Exception('Unauthorized (401) – please log in again.');
    }
    if (res.statusCode >= 400) {
      throw Exception('Failed to load conversations (${res.statusCode}).');
    }

    final data = json.decode(res.body);
    if (data is! List) return [];
    return data.map<_Conversation>((e) => _Conversation.fromJson(e)).toList();
  }

  Future<Map<String, _Profile>> _fetchProfiles(List<String> ids) async {
    if (ids.isEmpty) return {};
    final uri = Uri.parse(
      '${widget.apiBaseUrl}/users/by-ids?ids=${Uri.encodeQueryComponent(ids.join(','))}',
    );
    final res = await http.get(
      uri,
      headers: {
        'Authorization': 'Bearer ${widget.token}',
        'Accept': 'application/json',
      },
    );

    if (res.statusCode == 401) {
      throw Exception('Unauthorized (401) – please log in again.');
    }
    if (res.statusCode >= 400) {
      throw Exception('Failed to load profiles (${res.statusCode}).');
    }

    final Map<String, dynamic> map = json.decode(res.body);
    debugPrint('📥 FriendsPage: Loaded ${map.length} profiles from /users/by-ids');
    final out = <String, _Profile>{};
    for (final entry in map.entries) {
      final profile = _Profile.fromJson(entry.value);
      debugPrint('  User ${entry.key}: name=${profile.name}, avatarUrl=${profile.avatarUrl}');
      out[entry.key] = profile;
    }
    return out;
  }

  void _connectSocket() {
    final s = io.io(
      widget.apiBaseUrl,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .enableReconnection()
          .setAuth({'token': widget.token})
          .build(),
    );

    s.onConnect((_) {
      // debugPrint('socket connected');
    });
    s.onDisconnect((_) {
      // debugPrint('socket disconnected');
    });

    // New message: bump recency
    s.on('message', (payload) {
      try {
        final convId = payload['conversationId']?.toString();
        final from = payload['from']?.toString();
        final to = payload['to']?.toString();
        final lm = payload['lastMessageAt']?.toString();
        if (convId == null) return;

        final partnerId = (from == widget.myUserId) ? to : from;
        DateTime? ts;
        if (lm != null) {
          ts = DateTime.tryParse(lm)?.toLocal();
        }

        // Update/inject row
        setState(() {
          final idx = _rows.indexWhere((r) => r.conversationId == convId);
          if (idx >= 0) {
            _rows[idx] = _rows[idx].copyWith(
              lastMessageAt: ts ?? DateTime.now(),
            );
          } else if (partnerId != null) {
            _rows.add(
              _FriendRow(
                conversationId: convId,
                partnerId: partnerId,
                name: 'Unknown',
                email: '',
                lastMessageAt: ts ?? DateTime.now(),
              ),
            );
          }

          _rows.sort(
            (a, b) =>
                (b.lastMessageAt ?? DateTime.fromMillisecondsSinceEpoch(0))
                    .compareTo(
                      a.lastMessageAt ?? DateTime.fromMillisecondsSinceEpoch(0),
                    ),
          );
        });
      } catch (_) {}
    });

    // A request was accepted; make sure it appears
    s.on('chat_request_accepted', (payload) async {
      try {
        // payload: { conversationId, partnerId }
        await _refresh();
      } catch (_) {}
    });

    // On delete, backend recomputes lastMessageAt; safest is a light refresh.
    s.on('message_deleted', (_) async {
      try {
        await _refresh();
      } catch (_) {}
    });

    // Listen for profile updates (avatar changes)
    s.on('user_profile_updated', (payload) async {
      try {
        debugPrint('📸 FriendsPage: Received user_profile_updated event: $payload');
        final userId = payload['userId']?.toString();
        final userData = payload['user'] as Map<String, dynamic>?;
        
        if (userId == null || userData == null) {
          debugPrint('⚠️ FriendsPage: Invalid profile update data');
          return;
        }
        
        debugPrint('🔄 FriendsPage: Updating profile for user: $userId, new avatarUrl: ${userData['avatarUrl']}');
        
        // Add timestamp for cache-busting
        final avatarUrl = userData['avatarUrl']?.toString();
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        String? updatedAvatarUrl;
        if (avatarUrl != null && avatarUrl.isNotEmpty) {
          final separator = avatarUrl.contains('?') ? '&' : '?';
          updatedAvatarUrl = '$avatarUrl${separator}_t=$timestamp';
          debugPrint('✅ FriendsPage: Updated avatar URL with timestamp: $updatedAvatarUrl');
        } else {
          // Explicitly set to null if avatar was removed
          updatedAvatarUrl = null;
          debugPrint('✅ FriendsPage: Avatar cleared for user: $userId');
        }
        
        // Update the row with new avatar if it exists
        if (mounted) {
          setState(() {
            final idx = _rows.indexWhere((r) => r.partnerId == userId);
            if (idx >= 0) {
              debugPrint('✅ FriendsPage: Found row at index $idx, updating avatar');
              final updatedRow = _rows[idx].copyWith(
                avatarUrl: updatedAvatarUrl,
                name: userData['name']?.toString() ?? _rows[idx].name,
                email: userData['email']?.toString() ?? _rows[idx].email,
              );
              _rows[idx] = updatedRow;
              debugPrint('✅ FriendsPage: Row updated successfully, new avatarUrl: $updatedAvatarUrl');
              // Force a rebuild by creating a new list reference
              _rows.sort(
                (a, b) => (b.lastMessageAt ?? DateTime.fromMillisecondsSinceEpoch(0))
                    .compareTo(
                      a.lastMessageAt ?? DateTime.fromMillisecondsSinceEpoch(0),
                    ),
              );
            } else {
              debugPrint('⚠️ FriendsPage: User $userId not found in rows list');
            }
          });
        }
      } catch (e) {
        debugPrint('❌ FriendsPage: Error handling profile update: $e');
      }
    });

    _socket = s;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // appBar: AppBar(
      //   title: const Text('Friends'),
      //   actions: [
      //     IconButton(
      //       icon: const Icon(Icons.refresh),
      //       onPressed: _refresh,
      //       tooltip: 'Refresh',
      //     ),
      //   ],
      // ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? _ErrorView(message: _error!, onRetry: _refresh)
            : RefreshIndicator(
                onRefresh: _refresh,
                child: _rows.isEmpty
                    ? ListView(
                        children: const [SizedBox(height: 80), _EmptyState()],
                      )
                    : ListView.separated(
                        itemCount: _rows.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, i) {
                          final r = _rows[i];
                          return ListTile(
                            leading: AvatarWithStatus(
                              avatarUrl: r.avatarUrl,
                              fallbackText: _initials(r.name.isNotEmpty ? r.name : r.email),
                              radius: 20,
                              isOnline: false, // Friends page doesn't track online status
                              imageKey: ValueKey('avatar_${r.partnerId}_${r.avatarUrl}'),
                            ),
                            title: Text(
                              r.name.isNotEmpty ? r.name : r.email,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Row(
                              children: [
                                if (r.email.isNotEmpty)
                                  Flexible(
                                    child: Text(
                                      r.email,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(
                                        context,
                                      ).textTheme.bodySmall,
                                    ),
                                  ),
                                if (r.email.isNotEmpty)
                                  const SizedBox(width: 8),
                                Text(
                                  _relativeTime(r.lastMessageAt),
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(fontStyle: FontStyle.italic),
                                ),
                              ],
                            ),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => widget.onOpenChat?.call(
                              r.conversationId,
                              r.partnerId,
                            ),
                          );
                        },
                      ),
              ),
      ),
    );
  }
}

/* ======================= Models & helpers ======================= */

class _Conversation {
  final String id;
  final List<String> participants;
  final String status;
  final DateTime? lastMessageAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  _Conversation({
    required this.id,
    required this.participants,
    required this.status,
    this.lastMessageAt,
    this.createdAt,
    this.updatedAt,
  });

  factory _Conversation.fromJson(Map<String, dynamic> j) {
    String asString(dynamic x) => x?.toString() ?? '';
    DateTime? toDt(dynamic x) =>
        x == null ? null : DateTime.tryParse(x.toString())?.toLocal();

    final partsRaw = (j['participants'] as List?) ?? const [];
    final parts = partsRaw.map((e) => e.toString()).toList(growable: false);

    return _Conversation(
      id: asString(j['_id']),
      participants: parts,
      status: asString(j['status']),
      lastMessageAt: toDt(j['lastMessageAt']),
      createdAt: toDt(j['createdAt']),
      updatedAt: toDt(j['updatedAt']),
    );
  }
}

class _Profile {
  final String name;
  final String email;
  final String? avatarUrl;
  _Profile({required this.name, required this.email, this.avatarUrl});
  factory _Profile.fromJson(Map<String, dynamic> j) => _Profile(
    name: (j['name'] ?? '').toString(),
    email: (j['email'] ?? '').toString(),
    avatarUrl: j['avatarUrl']?.toString(),
  );
}

class _FriendRow {
  final String conversationId;
  final String partnerId;
  final String name;
  final String email;
  final String? avatarUrl;
  final DateTime? lastMessageAt;

  const _FriendRow({
    required this.conversationId,
    required this.partnerId,
    required this.name,
    required this.email,
    this.avatarUrl,
    required this.lastMessageAt,
  });

  _FriendRow copyWith({
    String? conversationId,
    String? partnerId,
    String? name,
    String? email,
    String? avatarUrl,
    DateTime? lastMessageAt,
  }) => _FriendRow(
    conversationId: conversationId ?? this.conversationId,
    partnerId: partnerId ?? this.partnerId,
    name: name ?? this.name,
    email: email ?? this.email,
    avatarUrl: avatarUrl ?? this.avatarUrl,
    lastMessageAt: lastMessageAt ?? this.lastMessageAt,
  );
}

String? _partnerOf(List<String> participants, String me) {
  for (final p in participants) {
    if (p.toString() != me) return p.toString();
  }
  return null;
}

String _initials(String nameOrEmail) {
  final s = nameOrEmail.trim();
  if (s.isEmpty) return '?';
  final parts = s.split(RegExp(r"\s+"));
  if (parts.length >= 2) {
    return (parts[0].isNotEmpty ? parts[0][0] : '') +
        (parts[1].isNotEmpty ? parts[1][0] : '');
  }
  // Use email/local part if needed
  final base = s.contains('@') ? s.split('@').first : s;
  return base.substring(0, 1).toUpperCase();
}

String _relativeTime(DateTime? t) {
  if (t == null) return '';
  final now = DateTime.now();
  final d = now.difference(t);
  if (d.inSeconds < 45) return 'just now';
  if (d.inMinutes < 1) return '${d.inSeconds}s';
  if (d.inMinutes < 60) return '${d.inMinutes}m';
  if (d.inHours < 24) return '${d.inHours}h';
  if (d.inDays < 7) return '${d.inDays}d';
  final y = t.year.toString().padLeft(4, '0');
  final mo = t.month.toString().padLeft(2, '0');
  final da = t.day.toString().padLeft(2, '0');
  final hh = t.hour.toString().padLeft(2, '0');
  final mm = t.minute.toString().padLeft(2, '0');
  return '$y-$mo-$da $hh:$mm';
}

/* ======================= UI bits ======================= */

class _ErrorView extends StatelessWidget {
  final String message;
  final Future<void> Function() onRetry;
  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();
  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.people_outline, size: 64),
        const SizedBox(height: 12),
        Text('No friends yet', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(
          'Accept a chat request to start a conversation.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}
