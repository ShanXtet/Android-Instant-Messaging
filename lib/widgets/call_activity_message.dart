import 'package:flutter/material.dart';
import '../models/call_log.dart';
import '../call_page.dart';

/// Call Activity Message Widget
/// Viber-style call history in chat - appears as message bubbles with smooth animations
class CallActivityMessage extends StatefulWidget {
  final CallLog callLog;
  final bool isMe;
  final String? timestamp;
  final VoidCallback? onTap;

  const CallActivityMessage({
    super.key,
    required this.callLog,
    required this.isMe,
    this.timestamp,
    this.onTap,
  });

  @override
  State<CallActivityMessage> createState() => _CallActivityMessageState();
}

class _CallBubbleIcon extends StatelessWidget {
  final bool isVideo;
  final Color color;
  final Size size;

  const _CallBubbleIcon({
    required this.isVideo,
    required this.color,
    this.size = const Size(28, 20),
  });

  @override
  Widget build(BuildContext context) {
    if (!isVideo) {
      return Icon(
        Icons.phone_outlined,
        size: 20,
        color: color,
      );
    }

    // Use Material icon for to ensure visibility
    return Icon(
      Icons.videocam_outlined,
      size: 20,
      color: color,
    );
  }
}

class _VideoCallIconPainter extends CustomPainter {
  final Color color;

  _VideoCallIconPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // Draw camera body (rounded rectangle)
    final bodyWidth = size.width * 0.65;
    final bodyHeight = size.height * 0.64;
    final bodyTop = size.height * 0.18;
    final bodyRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, bodyTop, bodyWidth, bodyHeight),
      const Radius.circular(4),
    );
    canvas.drawRRect(bodyRect, paint);

    // Draw camera lens/viewfinder (small circle on the body)
    final lensCenterX = bodyWidth * 0.5;
    final lensCenterY = bodyTop + bodyHeight * 0.5;
    final lensRadius = bodyWidth * 0.15;
    canvas.drawCircle(
      Offset(lensCenterX, lensCenterY),
      lensRadius,
      paint,
    );

    // Draw camera viewfinder/screen (trapezoid on the right)
    final startX = bodyWidth - paint.strokeWidth;
    final path = Path()
      ..moveTo(startX, bodyTop + bodyHeight * 0.15)
      ..lineTo(size.width, size.height * 0.05)
      ..lineTo(size.width, size.height * 0.95)
      ..lineTo(startX, bodyTop + bodyHeight * 0.85)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _CallActivityMessageState extends State<CallActivityMessage>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;
  bool _isPressed = false;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.95).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: Curves.easeInOut,
      ),
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _handleTapDown(TapDownDetails details) {
    setState(() => _isPressed = true);
    _animationController.forward();
  }

  void _handleTapUp(TapUpDetails details) {
    setState(() => _isPressed = false);
    _animationController.reverse();
  }

  void _handleTapCancel() {
    setState(() => _isPressed = false);
    _animationController.reverse();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Determine direction from chat context first (isMe), otherwise fallback to log type
    final isOutgoing = widget.isMe || widget.callLog.type == CallType.outgoing;
    
    // Determine icon, status text, and colors based on call type and status
    IconData icon;
    String callTypeText;
    String statusText;
    Color statusColor;
    IconData statusIcon;
    bool showCheckmarks = false;

    // Set icon and text based on call type (video or voice)
    if (widget.callLog.isVideoCall) {
      icon = Icons.videocam_outlined;
      callTypeText = isOutgoing ? 'Outgoing Video Call' : 'Incoming Video Call';
    } else {
      icon = Icons.phone_outlined;
      callTypeText = isOutgoing ? 'Outgoing Call' : 'Incoming Call';
    }

    // Determine status text and color based on call status
    if (isOutgoing) {
      // OUTGOING CALLS (You called) - RIGHT side, Light green bubble
      switch (widget.callLog.status) {
        case CallStatus.completed:
          // Completed: call was answered and connected - show duration
          if (widget.callLog.duration != null && widget.callLog.duration!.inSeconds > 0) {
            statusText = widget.callLog.formatDuration();
            statusColor = Colors.green;
            statusIcon = Icons.arrow_upward;
            showCheckmarks = true;
          } else {
            statusText = 'Completed';
            statusColor = Colors.green;
            statusIcon = Icons.arrow_upward;
            showCheckmarks = true;
          }
          break;
        case CallStatus.cancelled:
          // Cancelled: outgoing call cancelled before answer
          statusText = 'Canceled';
          statusColor = Colors.red;
          statusIcon = Icons.arrow_upward;
          showCheckmarks = true;
          break;
        case CallStatus.rejected:
          // Rejected: outgoing call was rejected by callee
          statusText = 'Canceled';
          statusColor = Colors.red;
          statusIcon = Icons.arrow_upward;
          showCheckmarks = true;
          break;
        case CallStatus.missed:
          // Missed: shouldn't happen for outgoing, but handle it
          statusText = 'Canceled';
          statusColor = Colors.red;
          statusIcon = Icons.arrow_upward;
          showCheckmarks = true;
          break;
      }
    } else {
      // INCOMING CALLS (They called you) - LEFT side
      switch (widget.callLog.status) {
        case CallStatus.completed:
          // Completed: call was answered and connected - show duration
          if (widget.callLog.duration != null && widget.callLog.duration!.inSeconds > 0) {
            statusText = widget.callLog.formatDuration();
            statusColor = Colors.green;
            statusIcon = Icons.arrow_downward;
          } else {
            statusText = 'Completed';
            statusColor = Colors.green;
            statusIcon = Icons.arrow_downward;
          }
          break;
        case CallStatus.missed:
          // Missed: incoming call not answered
          statusText = 'Missed';
          statusColor = Colors.red;
          statusIcon = Icons.arrow_downward;
          break;
        case CallStatus.rejected:
          // Declined: incoming call rejected
          statusText = 'Declined';
          statusColor = Colors.red;
          statusIcon = Icons.arrow_downward;
          break;
        case CallStatus.cancelled:
          // Cancelled: shouldn't happen for incoming
          statusText = 'Missed';
          statusColor = Colors.red;
          statusIcon = Icons.arrow_downward;
          break;
      }
    }

    // Light green bubble style matching the call history UI
    return GestureDetector(
      onTapDown: _handleTapDown,
      onTapUp: _handleTapUp,
      onTapCancel: _handleTapCancel,
      onTap: widget.onTap ?? () {
        // Initiate a call (voice or video) based on the call activity type
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => CallPage(
              peerId: widget.callLog.peerId,
              peerName: widget.callLog.getDisplayName(),
              outgoing: true,
              video: widget.callLog.isVideoCall, // Use the same call type as the original call
            ),
          ),
        );
      },
      child: Center(
        child: ScaleTransition(
          scale: _scaleAnimation,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeInOut,
            margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.green.shade50, // Light green background
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: Colors.green.shade100,
                width: 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Icon on the left
                _CallBubbleIcon(
                  isVideo: widget.callLog.isVideoCall,
                  color: Colors.black87,
                  size: const Size(32, 22),
                ),
                const SizedBox(width: 12),
                // Call type and status
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Call type text
                    Text(
                      callTypeText,
                      style: const TextStyle(
                        color: Colors.black87,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    // Status with icon
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          statusIcon,
                          size: 14,
                          color: statusColor,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          statusText,
                          style: TextStyle(
                            color: statusColor,
                            fontSize: 12,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(width: 12),
                // Time and checkmarks on the right
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Time
                    if (widget.timestamp != null)
                      Text(
                      widget.timestamp!,
                        style: const TextStyle(
                          color: Colors.black87,
                          fontSize: 12,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                    // Checkmarks (only for outgoing completed calls)
                    // Icons.done_all already represents double checkmarks, so we only need one icon
                    if (showCheckmarks && isOutgoing)
                      Icon(
                        Icons.done_all,
                        size: 14,
                        color: Colors.green,
                      ),
                ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
