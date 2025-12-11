import 'package:flutter/material.dart';
import 'package:study1/call_page.dart';
import 'splash_gate.dart';
import 'nav.dart'; // 👈 navigatorKey here
import 'services/theme_service.dart';

void onIncomingCall(dynamic data) {
  final m = Map<String, dynamic>.from(data ?? {});
  debugPrint('=== onIncomingCall received data: $m ===');
  final from = (m['from'] ?? '').toString();
  final callId = (m['callId'] ?? '').toString();
  // Check for kind field - handle different cases and variations
  final kindRaw = m['kind'] ?? m['type'] ?? 'audio';
  final kind = kindRaw.toString().toLowerCase().trim();
  debugPrint('Incoming call - from: $from, callId: $callId, kind raw: $kindRaw, kind normalized: $kind');
  
  // Determine if it's a video call (check for 'video' in kind string)
  final isVideo = kind == 'video' || kind.contains('video');
  debugPrint('Incoming call detected as video: $isVideo');
  
  final sdpObj = (m['sdp'] is Map)
      ? Map<String, dynamic>.from(m['sdp'])
      : <String, dynamic>{};

  if (from.isEmpty || callId.isEmpty || sdpObj.isEmpty) {
    debugPrint('Incoming call rejected - missing required fields');
    return;
  }

  debugPrint('Creating CallPage with video=$isVideo for incoming call from $from');
  navigatorKey.currentState?.push(
    MaterialPageRoute(
      builder: (_) => CallPage(
        peerId: from,
        peerName: 'Incoming call',
        outgoing: false,
        video: isVideo, // ⬅️ detect video call from kind
        initialCallId: callId,
        initialOffer: sdpObj,
      ),
    ),
  );
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final ThemeService _themeService = ThemeService();

  @override
  void initState() {
    super.initState();
    _themeService.loadPreferences();
    _themeService.addListener(_onThemeChanged);
  }

  @override
  void dispose() {
    _themeService.removeListener(_onThemeChanged);
    super.dispose();
  }

  void _onThemeChanged() {
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _themeService,
      builder: (context, child) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      navigatorKey: navigatorKey, // 👈 IMPORTANT
          theme: _themeService.getLightTheme(),
          darkTheme: _themeService.getDarkTheme(),
          themeMode: _themeService.themeMode,
      home: const SplashGate(),
        );
      },
    );
  }
}
