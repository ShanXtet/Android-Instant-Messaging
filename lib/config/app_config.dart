// lib/config/app_config.dart
import 'package:flutter/material.dart';

class AppConfig {
  // ========== Network Configuration ==========
  // IMPORTANT: For real devices, set your computer's LAN IP address here
  // Find your IP: 
  //   Windows: ipconfig (look for IPv4 Address)
  //   macOS/Linux: ifconfig or ipconfig getifaddr en0
  // 
  // This IP will be used for:
  //   - Real Android devices
  //   - Real iOS devices
  //   - iOS Simulator (can also use localhost)
  //
  // For Android Emulator: Uses 10.0.2.2 automatically (no change needed)
  //192.168.2.146 
  static const String serverIpAddress = '192.168.2.242';
  static const int serverPort = 3000;
  
  // Message settings
  static const int maxMessageLength = 4000;
  static const int maxFileSizeMB = 50;
  static const int maxVoiceDurationSeconds = 300; // 5 minutes
  
  // UI Settings
  static const double defaultPadding = 12.0;
  static const double messageBorderRadius = 16.0;
  static const double avatarRadius = 24.0;
  
  // Animation durations
  static const Duration shortAnimation = Duration(milliseconds: 200);
  static const Duration mediumAnimation = Duration(milliseconds: 300);
  static const Duration longAnimation = Duration(milliseconds: 500);
  
  // Colors
  static const Color primaryColor = Color(0xFF3A7BD5);
  static const Color secondaryColor = Color(0xFF00D2FF);
  static const Color successColor = Color(0xFF00C853);
  static const Color errorColor = Color(0xFFD32F2F);
  
  // Message bubble colors
  static const List<Color> myMessageColors = [
    Color(0xFF3A7BD5),
    Color(0xFF00D2FF),
  ];
  
  static const List<Color> peerMessageColors = [
    Color(0xFF00C853),
    Color(0xFFB2FF59),
  ];
  
  // Typography
  static const double messageFontSize = 15.0;
  static const double timestampFontSize = 11.0;
  static const double nameFontSize = 16.0;
  
  // Spacing
  static const double messageSpacing = 4.0;
  static const double sectionSpacing = 16.0;
  
  // Feature flags
  static bool enableVoiceMessages = true;
  static bool enableFileSharing = true;
  static bool enableImageSharing = true;
  static bool enableEmojiPicker = true;
  static bool enableVideoCalls = true;
  static bool enableVoiceCalls = true;
  
  // Notification settings
  static bool enableNotifications = true;
  static bool enableSoundNotifications = true;
  static bool enableVibration = true;
  
  // Privacy settings
  static bool showReadReceipts = true;
  static bool showTypingIndicator = true;
  static bool showOnlineStatus = true;
  static bool showLastSeen = true;
  
  // Update feature flags
  static void updateFeatureFlag(String feature, bool value) {
    switch (feature) {
      case 'voiceMessages':
        enableVoiceMessages = value;
        break;
      case 'fileSharing':
        enableFileSharing = value;
        break;
      case 'imageSharing':
        enableImageSharing = value;
        break;
      case 'emojiPicker':
        enableEmojiPicker = value;
        break;
      case 'videoCalls':
        enableVideoCalls = value;
        break;
      case 'voiceCalls':
        enableVoiceCalls = value;
        break;
    }
  }
  
  // Get responsive value
  static double getResponsivePadding(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (width > 1200) return 24.0;
    if (width > 600) return 16.0;
    return defaultPadding;
  }
  
  // Get message max width
  static double getMessageMaxWidth(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (width > 1200) return 600.0;
    if (width > 600) return 500.0;
    return width * 0.8;
  }
}


