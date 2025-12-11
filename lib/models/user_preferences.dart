import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// User Preferences Model
/// Contains all user settings and preferences
class UserPreferences {
  // Theme Settings
  final AppTheme theme;
  
  // Chat Settings
  final double fontSize;
  final String? chatWallpaper;
  final bool autoDownloadMedia;
  final bool showReadReceipts;
  final bool showTypingIndicator;
  
  // Notification Settings
  final bool pushNotifications;
  final bool messageSound;
  final bool messageVibration;
  final bool groupNotifications;
  final bool callNotifications;
  
  // Call Settings
  final String? callRingtone;
  final VideoCallQuality videoCallQuality;
  final bool autoAnswerCalls;
  final bool callRecording;
  
  // Privacy Settings
  final bool showOnlineStatus;
  final bool showLastSeen;
  final bool twoFactorEnabled;

  UserPreferences({
    this.theme = AppTheme.system,
    this.fontSize = 14.0,
    this.chatWallpaper,
    this.autoDownloadMedia = true,
    this.showReadReceipts = true,
    this.showTypingIndicator = true,
    this.pushNotifications = true,
    this.messageSound = true,
    this.messageVibration = true,
    this.groupNotifications = true,
    this.callNotifications = true,
    this.callRingtone,
    this.videoCallQuality = VideoCallQuality.high,
    this.autoAnswerCalls = false,
    this.callRecording = false,
    this.showOnlineStatus = true,
    this.showLastSeen = true,
    this.twoFactorEnabled = false,
  });

  /// Create from JSON map
  factory UserPreferences.fromJson(Map<String, dynamic> json) {
    return UserPreferences(
      theme: AppTheme.fromString(json['theme']?.toString() ?? 'system'),
      fontSize: (json['fontSize'] as num?)?.toDouble() ?? 14.0,
      chatWallpaper: json['chatWallpaper']?.toString(),
      autoDownloadMedia: json['autoDownloadMedia'] == true,
      showReadReceipts: json['showReadReceipts'] == true,
      showTypingIndicator: json['showTypingIndicator'] == true,
      pushNotifications: json['pushNotifications'] == true,
      messageSound: json['messageSound'] == true,
      messageVibration: json['messageVibration'] == true,
      groupNotifications: json['groupNotifications'] == true,
      callNotifications: json['callNotifications'] == true,
      callRingtone: json['callRingtone']?.toString(),
      videoCallQuality: VideoCallQuality.fromString(
        json['videoCallQuality']?.toString() ?? 'high',
      ),
      autoAnswerCalls: json['autoAnswerCalls'] == true,
      callRecording: json['callRecording'] == true,
      showOnlineStatus: json['showOnlineStatus'] == true,
      showLastSeen: json['showLastSeen'] == true,
      twoFactorEnabled: json['twoFactorEnabled'] == true,
    );
  }

  /// Convert to JSON map
  Map<String, dynamic> toJson() {
    return {
      'theme': theme.toString(),
      'fontSize': fontSize,
      'chatWallpaper': chatWallpaper,
      'autoDownloadMedia': autoDownloadMedia,
      'showReadReceipts': showReadReceipts,
      'showTypingIndicator': showTypingIndicator,
      'pushNotifications': pushNotifications,
      'messageSound': messageSound,
      'messageVibration': messageVibration,
      'groupNotifications': groupNotifications,
      'callNotifications': callNotifications,
      'callRingtone': callRingtone,
      'videoCallQuality': videoCallQuality.toString(),
      'autoAnswerCalls': autoAnswerCalls,
      'callRecording': callRecording,
      'showOnlineStatus': showOnlineStatus,
      'showLastSeen': showLastSeen,
      'twoFactorEnabled': twoFactorEnabled,
    };
  }

  /// Create a copy with updated fields
  UserPreferences copyWith({
    AppTheme? theme,
    double? fontSize,
    String? chatWallpaper,
    bool? autoDownloadMedia,
    bool? showReadReceipts,
    bool? showTypingIndicator,
    bool? pushNotifications,
    bool? messageSound,
    bool? messageVibration,
    bool? groupNotifications,
    bool? callNotifications,
    String? callRingtone,
    VideoCallQuality? videoCallQuality,
    bool? autoAnswerCalls,
    bool? callRecording,
    bool? showOnlineStatus,
    bool? showLastSeen,
    bool? twoFactorEnabled,
  }) {
    return UserPreferences(
      theme: theme ?? this.theme,
      fontSize: fontSize ?? this.fontSize,
      chatWallpaper: chatWallpaper ?? this.chatWallpaper,
      autoDownloadMedia: autoDownloadMedia ?? this.autoDownloadMedia,
      showReadReceipts: showReadReceipts ?? this.showReadReceipts,
      showTypingIndicator: showTypingIndicator ?? this.showTypingIndicator,
      pushNotifications: pushNotifications ?? this.pushNotifications,
      messageSound: messageSound ?? this.messageSound,
      messageVibration: messageVibration ?? this.messageVibration,
      groupNotifications: groupNotifications ?? this.groupNotifications,
      callNotifications: callNotifications ?? this.callNotifications,
      callRingtone: callRingtone ?? this.callRingtone,
      videoCallQuality: videoCallQuality ?? this.videoCallQuality,
      autoAnswerCalls: autoAnswerCalls ?? this.autoAnswerCalls,
      callRecording: callRecording ?? this.callRecording,
      showOnlineStatus: showOnlineStatus ?? this.showOnlineStatus,
      showLastSeen: showLastSeen ?? this.showLastSeen,
      twoFactorEnabled: twoFactorEnabled ?? this.twoFactorEnabled,
    );
  }

  /// Load preferences from SharedPreferences
  static Future<UserPreferences> load() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString('user_preferences');
    if (jsonStr == null) {
      return UserPreferences();
    }
    try {
      final json = jsonDecode(jsonStr) as Map<String, dynamic>;
      return UserPreferences.fromJson(json);
    } catch (e) {
      return UserPreferences();
    }
  }

  /// Save preferences to SharedPreferences
  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_preferences', jsonEncode(toJson()));
  }
}

/// App Theme Enum
enum AppTheme {
  light,
  dark,
  system;

  static AppTheme fromString(String value) {
    switch (value.toLowerCase()) {
      case 'light':
        return AppTheme.light;
      case 'dark':
        return AppTheme.dark;
      case 'system':
      default:
        return AppTheme.system;
    }
  }

  @override
  String toString() {
    switch (this) {
      case AppTheme.light:
        return 'light';
      case AppTheme.dark:
        return 'dark';
      case AppTheme.system:
        return 'system';
    }
  }

  String getDisplayName() {
    switch (this) {
      case AppTheme.light:
        return 'Light';
      case AppTheme.dark:
        return 'Dark';
      case AppTheme.system:
        return 'System';
    }
  }
}

/// Video Call Quality Enum
enum VideoCallQuality {
  low,
  medium,
  high,
  ultra;

  static VideoCallQuality fromString(String value) {
    switch (value.toLowerCase()) {
      case 'low':
        return VideoCallQuality.low;
      case 'medium':
        return VideoCallQuality.medium;
      case 'high':
        return VideoCallQuality.high;
      case 'ultra':
        return VideoCallQuality.ultra;
      default:
        return VideoCallQuality.high;
    }
  }

  @override
  String toString() {
    switch (this) {
      case VideoCallQuality.low:
        return 'low';
      case VideoCallQuality.medium:
        return 'medium';
      case VideoCallQuality.high:
        return 'high';
      case VideoCallQuality.ultra:
        return 'ultra';
    }
  }

  String getDisplayName() {
    switch (this) {
      case VideoCallQuality.low:
        return 'Low (240p)';
      case VideoCallQuality.medium:
        return 'Medium (480p)';
      case VideoCallQuality.high:
        return 'High (720p)';
      case VideoCallQuality.ultra:
        return 'Ultra (1080p)';
    }
  }
}


