// lib/call_manager.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:study1/nav.dart';

import 'socket_service.dart';
import 'auth_store.dart';
import 'api.dart';
import 'call_page.dart';
// to use navigatorKey

class CallManager {
  CallManager._();
  static final CallManager I = CallManager._();

  bool _wired = false;

  void wire() {
    if (_wired) return;
    _wired = true;

    // A → B: server emits 'call:incoming' to B
    SocketService.I.on('call:incoming', (data) async {
      try {
        final m = Map<String, dynamic>.from(data ?? {});
        final from = (m['from'] ?? '').toString();
        final callId = (m['callId'] ?? '').toString();
        final kind = (m['kind'] ?? 'audio').toString(); // 'audio' or 'video'
        final sdp = (m['sdp'] is Map)
            ? Map<String, dynamic>.from(m['sdp'])
            : const {};
        if (from.isEmpty || callId.isEmpty || sdp.isEmpty) return;

        // self uid
        final u = await AuthStore.getUser();
        final myId = u?['id']?.toString();
        if (myId == null || myId.isEmpty) return;

        String display = from;
        try {
          final r = await http.get(
            Uri.parse('$apiBase/api/users/by-ids?ids=$from'),
            headers: await authHeaders(),
          );
          if (r.statusCode == 200) {
            final map = Map<String, dynamic>.from(jsonDecode(r.body));
            final obj = Map<String, dynamic>.from(map[from] ?? {});
            final n = (obj['name'] ?? '').toString().trim();
            final e = (obj['email'] ?? '').toString().trim();
            display = n.isNotEmpty ? n : (e.isNotEmpty ? e : from);
          }
        } catch (_) {}

        // Push CallPage for callee side
        navigatorKey.currentState?.push(
          MaterialPageRoute(
            builder: (_) => CallPage(
              peerId: from,
              peerName: display,
              outgoing: false, // ⬅️ incoming
              video: kind == 'video', // ⬅️ detect video call from kind
              initialCallId: callId, // ⬅️ pass it
              initialOffer: Map<String, dynamic>.from(sdp),
            ),
          ),
        );
      } catch (_) {}
    });

    // Show simple toasts for other states (optional)
    SocketService.I.on('call:busy', (_) {
      _showSnack('Peer is busy');
    });
    SocketService.I.on('call:ringing', (_) {
      /* caller-side status; ignore here */
    });
    SocketService.I.on('call:ended', (_) {
      /* handled inside CallPage */
    });
  }

  void _showSnack(String m) {
    final ctx = navigatorKey.currentContext;
    if (ctx == null) return;
    ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(m)));
  }
}
