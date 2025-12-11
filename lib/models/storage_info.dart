/// Storage Information Model
/// Contains storage usage statistics
class StorageInfo {
  final int usedSpace; // in bytes
  final int totalSpace; // in bytes
  final int mediaCount;
  final int messageCount;
  final Map<String, int> breakdown; // category -> bytes

  StorageInfo({
    required this.usedSpace,
    required this.totalSpace,
    this.mediaCount = 0,
    this.messageCount = 0,
    this.breakdown = const {},
  });

  /// Create from JSON map
  factory StorageInfo.fromJson(Map<String, dynamic> json) {
    return StorageInfo(
      usedSpace: (json['usedSpace'] as num?)?.toInt() ?? 0,
      totalSpace: (json['totalSpace'] as num?)?.toInt() ?? 0,
      mediaCount: (json['mediaCount'] as num?)?.toInt() ?? 0,
      messageCount: (json['messageCount'] as num?)?.toInt() ?? 0,
      breakdown: json['breakdown'] != null
          ? Map<String, int>.from(
              (json['breakdown'] as Map).map(
                (k, v) => MapEntry(k.toString(), (v as num).toInt()),
              ),
            )
          : {},
    );
  }

  /// Convert to JSON map
  Map<String, dynamic> toJson() {
    return {
      'usedSpace': usedSpace,
      'totalSpace': totalSpace,
      'mediaCount': mediaCount,
      'messageCount': messageCount,
      'breakdown': breakdown,
    };
  }

  /// Get used space percentage
  double get usedPercentage {
    if (totalSpace == 0) return 0.0;
    return (usedSpace / totalSpace) * 100;
  }

  /// Get free space in bytes
  int get freeSpace => totalSpace - usedSpace;

  /// Format bytes to human readable string
  static String formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  /// Get formatted used space
  String get formattedUsedSpace => formatBytes(usedSpace);

  /// Get formatted total space
  String get formattedTotalSpace => formatBytes(totalSpace);

  /// Get formatted free space
  String get formattedFreeSpace => formatBytes(freeSpace);
}


