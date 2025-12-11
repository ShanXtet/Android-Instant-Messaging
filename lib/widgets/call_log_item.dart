import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/call_log.dart';

/// Call Log Item Widget
/// Displays a single call log entry in the list
class CallLogItem extends StatelessWidget {
  final CallLog callLog;
  final VoidCallback? onTap;
  final VoidCallback? onCallTap;

  const CallLogItem({
    super.key,
    required this.callLog,
    this.onTap,
    this.onCallTap,
  });

  /// Get avatar color based on name (for consistent colors)
  Color _getAvatarColor(String name) {
    final hash = name.hashCode;
    final colors = [
      const Color(0xFF9C27B0), // Purple
      const Color(0xFF2196F3), // Bright blue
    ];
    return colors[hash.abs() % colors.length];
  }

  /// Get checkmark color based on call status
  /// Shows checkmark using theme primary color
  Color? _getCheckmarkColor() {
    // Return null to use theme primary color in build method
    // This allows the checkmark to match the app theme
    return null;
  }

  /// Format duration as "0:45" format
  String _formatDurationShort() {
    if (callLog.duration == null) return '0:00';
    final totalSeconds = callLog.duration!.inSeconds;
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '${minutes}:${seconds.toString().padLeft(2, '0')}';
  }

  /// Get call type text - shows "Unknown" when contact name is unknown, otherwise shows call type
  String _getCallTypeText() {
    // If the contact name is "Unknown", show "Unknown"
    final displayName = callLog.getDisplayName();
    if (displayName == 'Unknown') {
      return 'Unknown';
    }
    // Otherwise show the actual call type
    return callLog.type == CallType.incoming ? 'Incoming' : 'Outgoing';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final avatarColor = _getAvatarColor(callLog.getDisplayName());
    final checkmarkColor = _getCheckmarkColor();
    final isIncoming = callLog.type == CallType.incoming;
    final isMissed = callLog.status == CallStatus.missed;
    final isOutgoing = callLog.type == CallType.outgoing;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: colorScheme.surface, // Use theme surface color
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: colorScheme.outline.withOpacity(0.2), // Use theme outline color
            width: 1,
          ),
        ),
        child: Row(
          children: [
            // Avatar
            CircleAvatar(
              radius: 30,
              backgroundColor: avatarColor,
              child: callLog.peerAvatarUrl != null && callLog.peerAvatarUrl!.isNotEmpty
                  ? ClipOval(
                      child: CachedNetworkImage(
                        imageUrl: callLog.peerAvatarUrl!,
                        width: 56,
                        height: 56,
                        fit: BoxFit.cover,
                        errorWidget: (context, url, error) => Text(
                          callLog.getInitials(),
                          style: const TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    )
                  : Text(
                      callLog.getInitials(),
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
            ),
            const SizedBox(width: 14),
            // Middle section - Text details
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Top line: Name, checkmark, time
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          callLog.getDisplayName(),
                          style: TextStyle(
                            color: colorScheme.onSurface, // Use theme onSurface color
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      // Always show checkmark (as shown in images)
                      Icon(
                        Icons.check_circle,
                        size: 16,
                        color: checkmarkColor ?? colorScheme.primary, // Use theme primary if no checkmark color
                      ),
                      const SizedBox(width: 4),
                      Text(
                        callLog.formatTime(),
                        style: TextStyle(
                          color: colorScheme.onSurfaceVariant, // Use theme onSurfaceVariant color
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  // Bottom line: Call type and status on same line
                  Row(
                    children: [
                      // Call type text
                      Text(
                        _getCallTypeText(),
                        style: TextStyle(
                          color: colorScheme.onSurface, // Use theme onSurface color
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Red/orange phone icon with curved arrow
                      Icon(
                        isIncoming ? Icons.call_received : Icons.call_made,
                        size: 16,
                        color: isOutgoing 
                            ? Colors.orange.shade700 // Orange/red for outgoing (matching image)
                            : colorScheme.error, // Use theme error color for missed calls
                      ),
                      const SizedBox(width: 4),
                      // Call status text
                      Text(
                        isMissed
                            ? (callLog.duration != null 
                                ? 'Missed ${_formatDurationShort()}' 
                                : 'Missed')
                            : isOutgoing
                                ? 'Outgoing ${_formatDurationShort()}'
                                : 'Missed ${_formatDurationShort()}',
                        style: TextStyle(
                          color: colorScheme.onSurface, // Use theme onSurface color
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // Right chevron
            const SizedBox(width: 8),
            Icon(
              Icons.chevron_right,
              color: colorScheme.onSurfaceVariant, // Use theme onSurfaceVariant color
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}

