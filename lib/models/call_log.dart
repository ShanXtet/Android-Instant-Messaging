/// Call Log Model
/// Represents a single call entry in the call history
class CallLog {
  final String id;
  final String peerId;
  final String? peerName;
  final String? peerEmail;
  final String? peerAvatarUrl;
  final CallType type;
  final CallStatus status;
  final DateTime startTime;
  final DateTime? endTime;
  final Duration? duration;
  final bool isVideoCall;

  CallLog({
    required this.id,
    required this.peerId,
    this.peerName,
    this.peerEmail,
    this.peerAvatarUrl,
    required this.type,
    required this.status,
    required this.startTime,
    this.endTime,
    this.duration,
    this.isVideoCall = false,
  });

  /// Create from JSON map
  factory CallLog.fromJson(Map<String, dynamic> json) {
    final startTimeStr = json['startTime']?.toString() ?? json['createdAt']?.toString();
    final endTimeStr = json['endTime']?.toString();
    
    DateTime? endTime;
    Duration? duration;
    
    if (endTimeStr != null) {
      endTime = DateTime.tryParse(endTimeStr);
      if (endTime != null && startTimeStr != null) {
        final start = DateTime.tryParse(startTimeStr);
        if (start != null) {
          duration = endTime.difference(start);
        }
      }
    }

    // Parse duration from JSON if not calculated from times
    if (duration == null && json['duration'] != null) {
      final durationSeconds = json['duration'];
      if (durationSeconds is num) {
        duration = Duration(seconds: durationSeconds.toInt());
      }
    }

    return CallLog(
      id: json['_id']?.toString() ?? json['id']?.toString() ?? '',
      peerId: json['peerId']?.toString() ?? json['to']?.toString() ?? '',
      peerName: json['peerName']?.toString(),
      peerEmail: json['peerEmail']?.toString(),
      peerAvatarUrl: json['peerAvatarUrl']?.toString(),
      type: CallType.fromString(json['type']?.toString() ?? 'outgoing'),
      status: CallStatus.fromString(json['status']?.toString() ?? 'completed'),
      startTime: DateTime.tryParse(startTimeStr ?? '') ?? DateTime.now(),
      endTime: endTime,
      duration: duration,
      isVideoCall: json['isVideoCall'] == true || json['kind']?.toString() == 'video',
    );
  }

  /// Convert to JSON map
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'peerId': peerId,
      'peerName': peerName,
      'peerEmail': peerEmail,
      'peerAvatarUrl': peerAvatarUrl,
      'type': type.toString(),
      'status': status.toString(),
      'startTime': startTime.toIso8601String(),
      'endTime': endTime?.toIso8601String(),
      'duration': duration?.inSeconds,
      'isVideoCall': isVideoCall,
    };
  }

  /// Get display name for the peer
  String getDisplayName() {
    if (peerName != null && peerName!.isNotEmpty) {
      return peerName!;
    }
    if (peerEmail != null && peerEmail!.isNotEmpty) {
      return peerEmail!;
    }
    return 'Unknown';
  }

  /// Get initials for avatar
  String getInitials() {
    final name = getDisplayName();
    if (name.isEmpty) return '?';
    final parts = name.trim().split(' ');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return name[0].toUpperCase();
  }

  /// Format duration as string (e.g., "5:23" or "1:23:45")
  String formatDuration() {
    if (duration == null) return '--:--';
    final totalSeconds = duration!.inSeconds;
    
    // Format as "X sec" for short durations (matching call history UI)
    if (totalSeconds < 60) {
      return '$totalSeconds sec';
    }
    
    // For longer durations, show minutes and seconds
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;
    
    if (hours > 0) {
      return '${hours}h ${minutes}m';
    }
    if (minutes > 0) {
      return '${minutes}m ${seconds}s';
    }
    return '$totalSeconds sec';
  }

  /// Format time as relative string (e.g., "2 hours ago", "Yesterday")
  String formatTime() {
    final now = DateTime.now();
    final diff = now.difference(startTime);
    
    if (diff.inMinutes < 1) {
      return 'Just now';
    } else if (diff.inHours < 1) {
      return '${diff.inMinutes}m ago';
    } else if (diff.inDays < 1) {
      return '${diff.inHours}h ago';
    } else if (diff.inDays == 1) {
      return 'Yesterday';
    } else if (diff.inDays < 7) {
      return '${diff.inDays}d ago';
    } else {
      // Format as date
      final month = startTime.month.toString().padLeft(2, '0');
      final day = startTime.day.toString().padLeft(2, '0');
      return '$month/$day';
    }
  }
}

/// Call Type Enum
enum CallType {
  incoming,
  outgoing;

  static CallType fromString(String value) {
    switch (value.toLowerCase()) {
      case 'incoming':
        return CallType.incoming;
      case 'outgoing':
      default:
        return CallType.outgoing;
    }
  }

  @override
  String toString() {
    switch (this) {
      case CallType.incoming:
        return 'incoming';
      case CallType.outgoing:
        return 'outgoing';
    }
  }

  String getDisplayName() {
    switch (this) {
      case CallType.incoming:
        return 'Incoming';
      case CallType.outgoing:
        return 'Outgoing';
    }
  }
}

/// Call Status Enum
enum CallStatus {
  completed,
  missed,
  rejected,
  cancelled;

  static CallStatus fromString(String value) {
    switch (value.toLowerCase()) {
      case 'missed':
        return CallStatus.missed;
      case 'rejected':
        return CallStatus.rejected;
      case 'cancelled':
        return CallStatus.cancelled;
      case 'completed':
      default:
        return CallStatus.completed;
    }
  }

  @override
  String toString() {
    switch (this) {
      case CallStatus.completed:
        return 'completed';
      case CallStatus.missed:
        return 'missed';
      case CallStatus.rejected:
        return 'rejected';
      case CallStatus.cancelled:
        return 'cancelled';
    }
  }

  String getDisplayName() {
    switch (this) {
      case CallStatus.completed:
        return 'Completed';
      case CallStatus.missed:
        return 'Missed';
      case CallStatus.rejected:
        return 'Rejected';
      case CallStatus.cancelled:
        return 'Cancelled';
    }
  }
}

/// Call Filter Enum
enum CallFilter {
  all,
  missed,
  outgoing,
  incoming;

  String getDisplayName() {
    switch (this) {
      case CallFilter.all:
        return 'All';
      case CallFilter.missed:
        return 'Missed';
      case CallFilter.outgoing:
        return 'Outgoing';
      case CallFilter.incoming:
        return 'Incoming';
    }
  }
}

