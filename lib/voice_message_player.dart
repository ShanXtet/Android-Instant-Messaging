// lib/voice_message_player.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';

class VoiceMessagePlayer extends StatefulWidget {
  final String audioUrl;
  final bool isMe;
  final int? duration; // in seconds

  const VoiceMessagePlayer({
    super.key,
    required this.audioUrl,
    required this.isMe,
    this.duration,
  });

  @override
  State<VoiceMessagePlayer> createState() => _VoiceMessagePlayerState();
}

class _VoiceMessagePlayerState extends State<VoiceMessagePlayer> {
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isPlaying = false;
  bool _isLoading = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  StreamSubscription? _positionSubscription;
  StreamSubscription? _playerStateSubscription;

  @override
  void initState() {
    super.initState();
    _initPlayer();
  }

  Future<void> _initPlayer() async {
    _playerStateSubscription = _audioPlayer.onPlayerStateChanged.listen((state) {
      if (mounted) {
        setState(() {
          _isPlaying = state == PlayerState.playing;
          // Note: audioplayers doesn't have a loading state, we'll track it differently
        });
      }
    });

    _positionSubscription = _audioPlayer.onPositionChanged.listen((position) {
      if (mounted) {
        setState(() {
          _position = position;
        });
      }
    });

    _audioPlayer.onDurationChanged.listen((duration) {
      if (mounted) {
        setState(() {
          _duration = duration;
        });
      }
    });
  }

  Future<void> _togglePlayPause() async {
    try {
      setState(() {
        _isLoading = true;
      });
      
      if (_isPlaying) {
        await _audioPlayer.pause();
        setState(() {
          _isLoading = false;
        });
      } else {
        // Ensure URL is valid and accessible
        final audioUrl = widget.audioUrl;
        if (audioUrl.isEmpty) {
          throw Exception('Audio URL is empty');
        }
        
        // For HTTP URLs, ensure they're properly formatted
        Uri? uri;
        try {
          uri = Uri.parse(audioUrl);
          if (!uri.hasScheme) {
            // If no scheme, assume it's a relative path - this shouldn't happen but handle it
            throw Exception('Invalid audio URL: missing scheme');
          }
        } catch (e) {
          throw Exception('Invalid audio URL format: $e');
        }
        
        if (_position == Duration.zero || _position >= _duration) {
          await _audioPlayer.play(UrlSource(audioUrl));
        } else {
          await _audioPlayer.resume();
        }
        // Loading will be set to false when state changes to playing
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted) {
            setState(() {
              _isLoading = false;
            });
          }
        });
      }
    } catch (e) {
      debugPrint('Error playing audio: $e');
      debugPrint('Audio URL: ${widget.audioUrl}');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isPlaying = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error playing voice message: ${e.toString()}'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '${minutes.toString().padLeft(1, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  String _formatTime(int seconds) {
    final minutes = seconds ~/ 60;
    final secs = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  // Generate waveform bars (simulated - in real app, you'd use actual audio data)
  List<double> _generateWaveformBars() {
    // Generate random heights for waveform visualization
    // In a real implementation, you'd use actual audio waveform data
    final random = DateTime.now().millisecondsSinceEpoch;
    final bars = <double>[];
    for (int i = 0; i < 50; i++) {
      bars.add((random + i) % 100 / 100.0);
    }
    return bars;
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    _playerStateSubscription?.cancel();
    _audioPlayer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final effectiveDuration = _duration.inSeconds > 0
        ? _duration.inSeconds
        : (widget.duration ?? 0);
    
    final currentTime = _position.inSeconds;
    final totalTime = effectiveDuration;
    final remainingTime = totalTime > currentTime ? totalTime - currentTime : 0;
    
    // Calculate progress for waveform highlighting
    final progress = totalTime > 0 ? currentTime / totalTime : 0.0;
    
    // Use blue color for the voice message UI (matching screenshot)
    const primaryColor = Color(0xFF2196F3); // Blue color
    const waveformColor = Color(0xFF2196F3); // Blue waveform

    // The message bubble already provides the white background
    // Return the content with proper padding to match the design
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Large circular blue play button
          GestureDetector(
            onTap: _togglePlayPause,
            child: Container(
              width: 56,
              height: 56,
              decoration: const BoxDecoration(
                color: primaryColor,
                shape: BoxShape.circle,
              ),
              child: _isLoading
                  ? const Padding(
                      padding: EdgeInsets.all(12.0),
                      child: CircularProgressIndicator(
                        strokeWidth: 3,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : Icon(
                      _isPlaying ? Icons.pause : Icons.play_arrow,
                      color: Colors.white,
                      size: 28,
                    ),
            ),
          ),
          const SizedBox(width: 16),
          // Waveform and time display
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Audio waveform visualization
                SizedBox(
                  height: 32,
                  child: _AudioWaveform(
                    progress: progress,
                    isPlaying: _isPlaying,
                    color: waveformColor,
                  ),
                ),
                const SizedBox(height: 6),
                // Time display: current time on left, remaining time on right
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Current/Elapsed time
                    Text(
                      _formatTime(currentTime),
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.grey,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    // Remaining time
                    Text(
                      _formatTime(remainingTime),
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.grey,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Audio waveform widget that displays animated bars
class _AudioWaveform extends StatefulWidget {
  final double progress;
  final bool isPlaying;
  final Color color;

  const _AudioWaveform({
    required this.progress,
    required this.isPlaying,
    required this.color,
  });

  @override
  State<_AudioWaveform> createState() => _AudioWaveformState();
}

class _AudioWaveformState extends State<_AudioWaveform>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late List<double> _barHeights;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    )..repeat();
    
    // Generate random waveform bar heights (simulated)
    // In a real app, you'd use actual audio waveform data
    _barHeights = _generateWaveformBars();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  List<double> _generateWaveformBars() {
    // Generate varied bar heights for realistic waveform look
    final random = DateTime.now().millisecondsSinceEpoch;
    final bars = <double>[];
    for (int i = 0; i < 60; i++) {
      // Create varied heights with some randomness
      final baseHeight = (i % 10) / 10.0;
      final variation = ((random + i * 7) % 30) / 100.0;
      bars.add((baseHeight * 0.3 + variation * 0.7).clamp(0.15, 1.0));
    }
    return bars;
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animationController,
      builder: (context, child) {
        return CustomPaint(
          painter: _WaveformPainter(
            barHeights: _barHeights,
            progress: widget.progress,
            isPlaying: widget.isPlaying,
            color: widget.color,
            animationValue: _animationController.value,
          ),
          size: Size.infinite,
        );
      },
    );
  }
}

/// Custom painter for drawing the audio waveform
class _WaveformPainter extends CustomPainter {
  final List<double> barHeights;
  final double progress;
  final bool isPlaying;
  final Color color;
  final double animationValue;

  _WaveformPainter({
    required this.barHeights,
    required this.progress,
    required this.isPlaying,
    required this.color,
    required this.animationValue,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final barWidth = 2.0;
    final barSpacing = 1.5;
    final totalBarWidth = barWidth + barSpacing;
    final maxBars = (size.width / totalBarWidth).floor();
    final barsToShow = barHeights.length.clamp(0, maxBars);
    
    final startX = 0.0;
    final barMaxHeight = size.height;
    
    for (int i = 0; i < barsToShow; i++) {
      final x = startX + i * totalBarWidth;
      final barHeight = barHeights[i] * barMaxHeight;
      
      // Determine if this bar is before or after the progress point
      final barProgress = i / barsToShow;
      final isPlayed = barProgress <= progress;
      
      // Color: played bars are full color, unplayed bars are lighter
      final barColor = isPlayed 
          ? color 
          : color.withOpacity(0.3);
      
      // Add subtle animation to bars when playing
      double animatedHeight = barHeight;
      if (isPlaying && isPlayed) {
        // Slight pulsing effect for played bars
        final pulse = (animationValue * 2 * 3.14159 + i * 0.1) % (2 * 3.14159);
        animatedHeight = barHeight * (1.0 + 0.1 * (pulse < 3.14159 ? pulse / 3.14159 : (2 * 3.14159 - pulse) / 3.14159));
      }
      
      final paint = Paint()
        ..color = barColor
        ..style = PaintingStyle.fill;
      
      // Draw vertical bar
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            x,
            (barMaxHeight - animatedHeight) / 2,
            barWidth,
            animatedHeight,
          ),
          const Radius.circular(1),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_WaveformPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.isPlaying != isPlaying ||
        oldDelegate.animationValue != animationValue;
  }
}

