import 'package:flutter/material.dart';

/// Call Status Banner Widget
/// Viber-style call status indicator shown in chat during active calls
class CallStatusBanner extends StatelessWidget {
  final String peerName;
  final bool isVideoCall;
  final bool isOutgoing;
  final String status; // 'ringing', 'connecting', 'active'
  final VoidCallback? onReturnToCall;
  final VoidCallback? onEndCall;

  const CallStatusBanner({
    super.key,
    required this.peerName,
    required this.isVideoCall,
    required this.isOutgoing,
    required this.status,
    this.onReturnToCall,
    this.onEndCall,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    // Determine status text and icon
    String statusText;
    IconData statusIcon;
    Color bannerColor;
    
    switch (status) {
      case 'ringing':
        statusText = isOutgoing ? 'Calling...' : 'Incoming call';
        statusIcon = isVideoCall ? Icons.videocam : Icons.phone;
        bannerColor = Colors.blue.shade700;
        break;
      case 'connecting':
        statusText = 'Connecting...';
        statusIcon = isVideoCall ? Icons.videocam : Icons.phone;
        bannerColor = Colors.blue.shade700;
        break;
      case 'active':
        statusText = isVideoCall ? 'Video call' : 'Voice call';
        statusIcon = isVideoCall ? Icons.videocam : Icons.phone;
        bannerColor = Colors.green.shade700;
        break;
      default:
        statusText = 'Call';
        statusIcon = Icons.phone;
        bannerColor = Colors.blue.shade700;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: bannerColor,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Call icon
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(
              statusIcon,
              color: Colors.white,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          // Call info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  peerName,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  statusText,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Colors.white.withOpacity(0.9),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          // Action buttons
          if (status == 'active' && onReturnToCall != null) ...[
            IconButton(
              icon: const Icon(Icons.phone, color: Colors.white),
              tooltip: 'Return to call',
              onPressed: onReturnToCall,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(
                minWidth: 40,
                minHeight: 40,
              ),
            ),
          ],
          IconButton(
            icon: const Icon(Icons.call_end, color: Colors.white),
            tooltip: 'End call',
            onPressed: onEndCall,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(
              minWidth: 40,
              minHeight: 40,
            ),
          ),
        ],
      ),
    );
  }
}

