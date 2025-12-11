import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class AuthStore {
  static const _kToken = 'jwt';
  static const _kUser = 'user';

  /// Save token + user
  static Future<void> save(String token, Map<String, dynamic> user) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_kToken, token);
    await sp.setString(_kUser, jsonEncode(user));
  }

  /// Get token (nullable)
  static Future<String?> getToken() async {
    final sp = await SharedPreferences.getInstance();
    return sp.getString(_kToken);
  }

  static Future<void> setUser(Map<String, dynamic> user) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_kUser, jsonEncode(user));
  }

  static Future<void> setToken(String token) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_kToken, token);
  }

  /// Get user (nullable)
  static Future<Map<String, dynamic>?> getUser() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(_kUser);
    return raw == null ? null : jsonDecode(raw) as Map<String, dynamic>;
  }

  /// Clear all auth info
  static Future<void> clear() async {
    final sp = await SharedPreferences.getInstance();
    await sp.remove(_kToken);
    await sp.remove(_kUser);
  }
}
