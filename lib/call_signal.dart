// lib/call_signal.dart
import 'package:flutter/material.dart';
import 'socket_service.dart';
import 'call_page.dart';
import 'nav.dart'; // navigatorKey

class CallSignal {
  static bool _wired = false;

  static void setup() {
    if (_wired) return;
    _wired = true;
    SocketService.I.off('call:incoming', _onIncomingCall);
    SocketService.I.on('call:incoming', _onIncomingCall);
  }

  static void _onIncomingCall(dynamic data) {
    final m = (data is Map)
        ? Map<String, dynamic>.from(data)
        : <String, dynamic>{};
    final from = (m['from'] ?? '').toString();
    final callId = (m['callId'] ?? '').toString();
    final kind = (m['kind'] ?? 'audio').toString(); // 'audio' or 'video'
    final sdp = (m['sdp'] is Map)
        ? Map<String, dynamic>.from(m['sdp'])
        : <String, dynamic>{};

    if (from.isEmpty || callId.isEmpty || sdp.isEmpty) return;

    navigatorKey.currentState?.push(
      MaterialPageRoute(
        builder: (_) => CallPage(
          peerId: from,
          peerName: 'Incoming call',
          outgoing: false,
          video: kind == 'video', // ⬅️ detect video call from kind
          initialCallId: callId,
          initialOffer: sdp,
        ),
      ),
    );
  }
}
