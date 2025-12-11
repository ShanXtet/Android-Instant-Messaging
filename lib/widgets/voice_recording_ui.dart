// lib/widgets/voice_recording_ui.dart
import 'package:flutter/material.dart';
import 'dart:math' as math;

/// Modern minimalist voice recording UI widget
class VoiceRecordingUI extends StatefulWidget {
  final int duration; // Duration in seconds
  final VoidCallback onStop;
  final VoidCallback onCancel;
  final bool showCancel;

  const VoiceRecordingUI({
    super.key,
    required this.duration,
    required this.onStop,
    required this.onCancel,
    this.showCancel = true,
  });

  @override
  State<VoiceRecordingUI> createState() => _VoiceRecordingUIState();
}

class _VoiceRecordingUIState extends State<VoiceRecordingUI>
    with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late AnimationController _waveformController;
  late Animation<double> _pulseAnimation;
  late Animation<double> _waveformAnimation;

  @override
  void initState() {
    super.initState();
    
    // Pulse animation for recording indicator
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
    
    _pulseAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(
        parent: _pulseController,
        curve: Curves.easeInOut,
      ),
    );
    
    // Waveform animation
    _waveformController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat();
    
    _waveformAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _waveformController,
        curve: Curves.easeInOut,
      ),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _waveformController.dispose();
    super.dispose();
  }

  String _formatDuration(int seconds) {
    final minutes = seconds ~/ 60;
    final secs = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF667EEA), // Purple-blue gradient
            const Color(0xFF764BA2),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF667EEA).withOpacity(0.3),
            blurRadius: 10,
            spreadRadius: 1,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Animated recording indicator with pulse effect
          AnimatedBuilder(
            animation: _pulseAnimation,
            builder: (context, child) {
              return Transform.scale(
                scale: _pulseAnimation.value,
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.white.withOpacity(0.5),
                        blurRadius: 6,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.mic,
                    color: Color(0xFF667EEA),
                    size: 18,
                  ),
                ),
              );
            },
          ),
          const SizedBox(width: 12),
          // Waveform and time display - centered
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Modern animated waveform - centered
                SizedBox(
                  height: 24,
                  child: AnimatedBuilder(
                    animation: _waveformAnimation,
                    builder: (context, child) {
                      return _ModernWaveform(
                        progress: _waveformAnimation.value,
                      );
                    },
                  ),
                ),
                const SizedBox(height: 6),
                // Time display - centered and styled
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    _formatDuration(widget.duration),
                    style: const TextStyle(
                      fontSize: 11,
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          // Stop button (square with rounded corners)
          GestureDetector(
            onTap: widget.onStop,
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 3,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: const Icon(
                Icons.stop,
                color: Color(0xFF667EEA),
                size: 20,
              ),
            ),
          ),
          // Cancel button
          if (widget.showCancel) ...[
            const SizedBox(width: 6),
            GestureDetector(
              onTap: widget.onCancel,
              child: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.close,
                  color: Colors.white,
                  size: 18,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Modern animated waveform visualization
class _ModernWaveform extends StatelessWidget {
  final double progress;

  const _ModernWaveform({
    required this.progress,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(double.infinity, 24),
      painter: _ModernWaveformPainter(progress: progress),
    );
  }
}

/// Custom painter for modern waveform style
class _ModernWaveformPainter extends CustomPainter {
  final double progress;
  final Color waveformColor = Colors.white;

  _ModernWaveformPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = waveformColor
      ..style = PaintingStyle.fill;

    final barWidth = 2.5;
    final barSpacing = 3.0;
    final maxBarHeight = size.height;
    final minBarHeight = 6.0;
    
    final totalBars = 40;
    final totalWidth = (totalBars * barWidth) + ((totalBars - 1) * barSpacing);
    final startX = (size.width - totalWidth) / 2;

    // Generate animated heights with smoother, more modern pattern
    for (int i = 0; i < totalBars; i++) {
      final x = startX + (i * (barWidth + barSpacing));
      
      // Create smoother waveform with multiple frequencies
      final normalizedPos = i / totalBars;
      final phase1 = (normalizedPos * 4 * math.pi) + (progress * 2 * math.pi);
      final phase2 = (normalizedPos * 6 * math.pi) + (progress * 3 * math.pi);
      final phase3 = (normalizedPos * 2 * math.pi) + (progress * 1.5 * math.pi);
      
      // Use smoother curves
      final wave1 = (math.sin(phase1) + 1) / 2;
      final wave2 = (math.sin(phase2) + 1) / 2 * 0.6;
      final wave3 = (math.sin(phase3) + 1) / 2 * 0.4;
      
      // Combine with center emphasis (higher bars in middle)
      final centerFactor = 1.0 - (normalizedPos - 0.5).abs() * 1.5;
      final centerBoost = math.max(0.0, centerFactor);
      
      final normalizedHeight = (wave1 * 0.5 + wave2 * 0.3 + wave3 * 0.2) * (0.7 + centerBoost * 0.3);
      final barHeight = minBarHeight + (normalizedHeight * (maxBarHeight - minBarHeight));
      
      // Center the bars vertically
      final y = (size.height - barHeight) / 2;
      
      // Draw rounded bars
      final rect = Rect.fromLTWH(x, y, barWidth, barHeight);
      final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(1.25));
      canvas.drawRRect(rrect, paint);
    }
  }

  @override
  bool shouldRepaint(_ModernWaveformPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}

