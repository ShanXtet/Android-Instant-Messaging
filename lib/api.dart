import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'auth_store.dart';
import 'config/app_config.dart';

/// Get the API base URL based on the platform
/// 
/// Detection logic:
/// - Web: http://localhost:3000
/// - Android Emulator: http://10.0.2.2:3000 (special IP that maps to host's localhost)
/// - Android Real Device: http://<serverIpAddress>:3000 (from AppConfig)
/// - iOS Simulator: http://localhost:3000 (shares network with Mac)
/// - iOS Real Device: http://<serverIpAddress>:3000 (from AppConfig)
/// 
/// IMPORTANT: Update AppConfig.serverIpAddress with your computer's LAN IP address
/// for real device connections. Never use localhost for real devices!
String get apiBase {
  if (kIsWeb) {
    return 'http://localhost:${AppConfig.serverPort}';
  }
  
  if (Platform.isAndroid) {
    // For Android, try emulator first (most common during development)
    // Android Emulator uses 10.0.2.2 to access host's localhost
    // If this fails, users can manually switch to LAN IP for real devices
    // TODO: Better emulator detection using platform channels
    try {
      // Try to detect if running on emulator by checking hostname or other indicators
      // For now, default to emulator (10.0.2.2) for development
      // You can override by setting ANDROID_USE_LAN_IP=true environment variable
      final useLanIp = Platform.environment['ANDROID_USE_LAN_IP']?.toLowerCase() == 'true';
      
      if (useLanIp) {
        // Android Real Device: Use configured server IP
        return 'http://${AppConfig.serverIpAddress}:${AppConfig.serverPort}';
      } else {
        // Android Emulator: Use special IP that maps to host's localhost
        return 'http://10.0.2.2:${AppConfig.serverPort}';
      }
    } catch (e) {
      // Fallback to emulator IP
      return 'http://10.0.2.2:${AppConfig.serverPort}';
    }
  }
  
  if (Platform.isIOS) {
    // For iOS, we can't easily detect simulator vs real device in pure Dart
    // iOS Simulator can use localhost, but real device needs LAN IP
    // To be safe for real devices, we'll use LAN IP by default
    // If you're testing on iOS Simulator and want localhost, you can temporarily
    // change this, but remember to change back for real device testing!
    return 'http://${AppConfig.serverIpAddress}:${AppConfig.serverPort}';
  }
  
  // Default fallback (desktop platforms)
  return 'http://${AppConfig.serverIpAddress}:${AppConfig.serverPort}';
}

/// Detect if running on Android emulator
/// Uses heuristics based on common emulator characteristics
/// 
/// Note: This is a simple heuristic. For more accurate detection,
/// you could use platform channels to access Android's Build class directly.
bool _isAndroidEmulator() {
  try {
    // Check environment variables that might indicate emulator
    // This is a simple check - for production, consider using platform channels
    // to access Android's Build.MODEL, Build.BRAND, etc.
    
    // Common emulator indicators in environment:
    // - ANDROID_EMULATOR environment variable
    // - Model names often contain "sdk", "google_sdk", "Emulator", "Android SDK"
    
    // For now, we'll use a conservative approach: 
    // Check if there's an environment variable, otherwise assume real device
    // Users can manually configure if needed
    
    // Since we can't easily access Build.MODEL in pure Dart without platform channels,
    // we'll default to assuming it's a real device for safety (real devices need LAN IP)
    // This ensures real devices work correctly
    
    // If you need to force emulator mode, you can set an environment variable
    // or modify this function to return true for testing
    final emulatorEnv = Platform.environment['ANDROID_EMULATOR'];
    if (emulatorEnv != null && emulatorEnv.toLowerCase() == 'true') {
      return true;
    }
    
    // Default to real device (safer for network connections)
    return false;
  } catch (e) {
    // If detection fails, assume real device (safer for network connections)
    return false;
  }
}

/// Test connection to the backend server
Future<Map<String, dynamic>> testConnection() async {
  try {
    final response = await http.get(
      Uri.parse('$apiBase/health'),
    ).timeout(
      const Duration(seconds: 10),
      onTimeout: () {
        throw TimeoutException('Connection timeout after 10 seconds');
      },
    );
    
    final body = jsonDecode(response.body);
    final dbStatus = body['database'] as Map<String, dynamic>?;
    
    return {
      'success': response.statusCode == 200 && (body['success'] == true),
      'statusCode': response.statusCode,
      'message': body['status'] ?? 'unknown',
      'apiBase': apiBase,
      'database': dbStatus != null ? {
        'connected': dbStatus['connected'] ?? false,
        'status': dbStatus['status'] ?? 'unknown',
        'host': dbStatus['host'] ?? 'unknown',
      } : null,
      'uptime': body['uptime'],
    };
  } catch (e) {
    return {
      'success': false,
      'error': e.toString(),
      'apiBase': apiBase,
    };
  }
}

/// Test database connection specifically
Future<Map<String, dynamic>> testDatabaseConnection() async {
  try {
    final response = await http.get(
      Uri.parse('$apiBase/health/db'),
      headers: await authHeaders(),
    ).timeout(
      const Duration(seconds: 10),
      onTimeout: () {
        throw TimeoutException('Database connection timeout after 10 seconds');
      },
    );
    
    final body = jsonDecode(response.body);
    
    return {
      'success': response.statusCode == 200 && (body['success'] == true),
      'statusCode': response.statusCode,
      'connected': body['database']?['readyState'] == 1,
      'status': body['status'] ?? 'unknown',
      'host': body['database']?['host'] ?? 'unknown',
      'database': body['database']?['name'] ?? 'unknown',
    };
  } catch (e) {
    return {
      'success': false,
      'error': e.toString(),
      'connected': false,
    };
  }
}

Future<Map<String, String>> authHeaders() async {
  final t = await AuthStore.getToken();
  return {
    'Content-Type': 'application/json',
    if (t != null) 'Authorization': 'Bearer $t',
  };
}

Future<http.Response> getJson(String path) async {
  try {
    return await http.get(
      Uri.parse('$apiBase$path'),
      headers: await authHeaders(),
    ).timeout(
      const Duration(seconds: 30), // Increased from 10 to 30 seconds for slow networks
      onTimeout: () {
        throw TimeoutException('Request timeout after 30s: $apiBase$path');
      },
    );
  } catch (e) {
    if (kDebugMode) {
      debugPrint('GET $apiBase$path error: $e');
    }
    rethrow;
  }
}

Future<http.Response> postJson(String path, Map<String, dynamic> body) async {
  try {
    return await http.post(
      Uri.parse('$apiBase$path'),
      headers: await authHeaders(),
      body: jsonEncode(body),
    ).timeout(
      const Duration(seconds: 30), // Increased from 10 to 30 seconds for slow networks
      onTimeout: () {
        throw TimeoutException('Request timeout after 30s: $apiBase$path');
      },
    );
  } catch (e) {
    if (kDebugMode) {
      debugPrint('POST $apiBase$path error: $e');
    }
    rethrow;
  }
}
