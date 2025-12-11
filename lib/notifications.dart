import 'dart:convert';
import 'dart:io';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class Noti {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static const _channel = AndroidNotificationChannel(
    'messages_v3',
    'Messages',
    description: 'Incoming chat messages',
    importance: Importance.high,
  );

  static final Set<String> _seenIds = <String>{};

  static Future<void> init({void Function(String payload)? onTap}) async {
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const init = InitializationSettings(android: androidInit);
    await _plugin.initialize(
      init,
      onDidReceiveNotificationResponse: (resp) {
        final p = resp.payload;
        if (p != null && onTap != null) onTap(p);
      },
    );
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await android?.createNotificationChannel(_channel);
    if (Platform.isAndroid) {
      final ok = await android?.areNotificationsEnabled();
      if (ok != true) await android?.requestNotificationsPermission();
    }
  }

  static Future<void> show({
    required String title,
    required String body,
    Map<String, String>? payload,
  }) async {
    await _plugin.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channel.id,
          _channel.name,
          channelDescription: _channel.description,
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
      payload: payload == null ? null : jsonEncode(payload),
    );
  }

  static Future<void> showIfNew({
    required String messageId,
    required String title,
    required String body,
    Map<String, String>? payload,
  }) async {
    if (messageId.isEmpty) {
      return show(title: title, body: body, payload: payload);
    }
    if (_seenIds.contains(messageId)) return;
    _seenIds.add(messageId);
    await show(title: title, body: body, payload: payload);
    if (_seenIds.length > 500) _seenIds.remove(_seenIds.first);
  }
}
